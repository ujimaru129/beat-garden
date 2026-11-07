return function(loader, expect)
	local PlayerData = loader.require("src/shared/Data/PlayerData")
	local Spirits = loader.require("src/shared/Garden/Spirits")
	local Trade = loader.require("src/shared/Garden/Trade")
	local DayNight = loader.require("src/shared/DayNight")

	local function constant(v: number)
		return function()
			return v
		end
	end

	-- A player with a few of everything.
	local function player(tag: string)
		local d = PlayerData.new()
		d.seeds = { seed_sakura = 3, seed_matcha = 1 }
		d.fruits = {
			{ seedId = "seed_sakura", weight = 1 },
			{ seedId = "seed_matcha", mutation = "Vapor", weight = 1 },
			{ seedId = "seed_sora", weight = 1 },
		}
		d.spirits = { { id = tag .. "_s1", kind = "Mochi" }, { id = tag .. "_s2", kind = "Kitsune" } }
		return d
	end

	local function offer(fruits, seeds, spirits)
		return { fruits = fruits or {}, seeds = seeds or {}, spirits = spirits or {} }
	end

	return {
		{
			"hatch odds follow the weights and add up to 100%",
			function()
				expect(Spirits.hatch(constant(0))).toBe("Mochi")
				expect(Spirits.hatch(constant(0.69))).toBe("Mochi")
				expect(Spirits.hatch(constant(0.71))).toBe("Kitsune")
				expect(Spirits.hatch(constant(0.999))).toBe("Kitsune")
				local sum = 0
				for _, o in Spirits.odds() do
					sum += o.percent
				end
				expect(sum).toBeNear(100, 0.2)
			end,
		},
		{
			"sanitize keeps eggs and spirits and drops broken ones",
			function()
				local d = PlayerData.sanitize({
					eggs = 3.9,
					spirits = {
						{ id = "a", kind = "Mochi" },
						{ id = "a", kind = "Kitsune" }, -- duplicate id
						{ id = "b", kind = "Nope" }, -- unknown kind
						"junk",
					},
					equippedSpirit = "a",
				})
				expect(d.eggs).toBe(3)
				expect(#d.spirits).toBe(1)
				expect(d.equippedSpirit).toBe("a")
				expect(PlayerData.sanitize({ equippedSpirit = "ghost" }).equippedSpirit).toBe(nil)
			end,
		},
		{
			"an offer from the client is cleaned up",
			function()
				local o = Trade.sanitizeOffer({
					fruits = { 1, 1, -2, "x", 2.7, 0 },
					seeds = { seed_sakura = 2, [5] = 1, seed_matcha = -1 },
					spirits = { "a", "a", 7 },
				})
				expect(#o.fruits).toBe(2) -- 1 and 2 (2.7 floors to 2); duplicates and bad values dropped
				expect(o.seeds.seed_sakura).toBe(2)
				expect(o.seeds.seed_matcha).toBe(nil)
				expect(#o.spirits).toBe(1)
				expect(Trade.isEmpty(Trade.sanitizeOffer("junk"))).toBe(true)
			end,
		},
		{
			"offers are capped",
			function()
				local many = {}
				for i = 1, 100 do
					table.insert(many, i)
				end
				expect(#Trade.sanitizeOffer({ fruits = many }).fruits).toBe(Trade.MaxItems)
			end,
		},
		{
			"check refuses items the player does not own",
			function()
				local a = player("a")
				expect((Trade.check(a, offer({ 1, 2 }, { seed_sakura = 3 }, { "a_s1" })))).toBe(true)
				expect((Trade.check(a, offer({ 9 })))).toBe(false)
				expect((Trade.check(a, offer({}, { seed_sakura = 4 })))).toBe(false)
				expect((Trade.check(a, offer({}, { seed_sora = 1 })))).toBe(false)
				expect((Trade.check(a, offer({}, {}, { "b_s1" })))).toBe(false)
			end,
		},
		{
			"estimated value adds up fruit, seeds and spirits",
			function()
				local a = player("a")
				-- Sakura fruit 30 + Vapor Matcha fruit 110*2 = 220, 2 Sakura seeds = 40, Mochi = 120
				expect(Trade.value(a, offer({ 1, 2 }, { seed_sakura = 2 }, { "a_s1" }))).toBe(30 + 220 + 40 + 120)
			end,
		},
		{
			"a swap moves everything and nothing is lost or duplicated",
			function()
				local a, b = player("a"), player("b")
				local ok =
					Trade.swap(a, b, offer({ 2 }, { seed_sakura = 1 }, { "a_s2" }), offer({ 1, 3 }, {}, { "b_s1" }))
				expect(ok).toBe(true)
				-- a gave 1 fruit, got 2; b gave 2, got 1
				expect(#a.fruits).toBe(4)
				expect(#b.fruits).toBe(2)
				expect(a.seeds.seed_sakura).toBe(2)
				expect(b.seeds.seed_sakura).toBe(4)
				-- spirits changed hands
				expect(#a.spirits).toBe(2)
				expect(#b.spirits).toBe(2)
				local aHas = {}
				for _, s in a.spirits do
					aHas[s.id] = true
				end
				expect(aHas.a_s1).toBe(true)
				expect(aHas.a_s2).toBe(nil)
				expect(aHas.b_s1).toBe(true)
				-- the Vapor fruit went to b
				local vapor = 0
				for _, f in b.fruits do
					if f.mutation == "Vapor" then
						vapor += 1
					end
				end
				expect(vapor).toBe(2)
			end,
		},
		{
			"a failed swap changes nothing",
			function()
				local a, b = player("a"), player("b")
				local ok, reason = Trade.swap(a, b, offer({ 1 }), offer({ 9 })) -- b has no fruit #9
				expect(ok).toBe(false)
				expect(reason ~= nil).toBeTruthy()
				expect(#a.fruits).toBe(3)
				expect(#b.fruits).toBe(3)
			end,
		},
		{
			"an empty trade is refused",
			function()
				local ok = Trade.swap(player("a"), player("b"), offer(), offer())
				expect(ok).toBe(false)
			end,
		},
		{
			"a traded-away equipped spirit is unequipped",
			function()
				local a, b = player("a"), player("b")
				a.equippedSpirit = "a_s1"
				expect(Trade.swap(a, b, offer({}, {}, { "a_s1" }), offer({ 1 }))).toBe(true)
				expect(a.equippedSpirit).toBe(nil)
			end,
		},
		{
			"a full bag stops the swap",
			function()
				local a, b = player("a"), player("b")
				for _ = 1, PlayerData.MaxFruits - 3 do
					table.insert(b.fruits, { seedId = "seed_sakura", weight = 1 })
				end
				-- b is at the cap; receiving one more fruit than it gives does not fit
				local ok, reason = Trade.swap(a, b, offer({ 1, 2 }), offer({ 1 }))
				expect(ok).toBe(false)
				expect(reason).toBe("someone's bag is full")
				expect(#b.fruits).toBe(PlayerData.MaxFruits)
			end,
		},
		{
			"night is the last five minutes of every hour",
			function()
				local hour = 7200 -- any whole hour
				expect(DayNight.isNight(hour)).toBe(false)
				expect(DayNight.isNight(hour + 3299)).toBe(false)
				expect(DayNight.isNight(hour + 3300)).toBe(true)
				expect(DayNight.isNight(hour + 3599)).toBe(true)
				expect(DayNight.isNight(hour + 3600)).toBe(false)
				expect(DayNight.timeOfDay(hour + 3400)).toBe("Night")
			end,
		},
		{
			"the countdown to the next change is right on both sides",
			function()
				expect(DayNight.secondsUntilChange(0)).toBe(3300)
				expect(DayNight.secondsUntilChange(3299)).toBe(1)
				expect(DayNight.secondsUntilChange(3300)).toBe(300)
				expect(DayNight.secondsUntilChange(3599)).toBe(1)
			end,
		},
	}
end
