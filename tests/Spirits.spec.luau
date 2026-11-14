return function(loader, expect)
	local Spirits = loader.require("src/shared/Garden/Spirits")
	local PlayerData = loader.require("src/shared/Data/PlayerData")

	return {
		{
			"bond levels follow the steps and stop at the maximum",
			function()
				expect(Spirits.bondLevel(0)).toBe(1)
				expect(Spirits.bondLevel(7)).toBe(1)
				expect(Spirits.bondLevel(8)).toBe(2)
				expect(Spirits.bondLevel(60)).toBe(4)
				expect(Spirits.bondLevel(120)).toBe(Spirits.MaxBondLevel)
				expect(Spirits.bondLevel(1e9)).toBe(Spirits.MaxBondLevel)
			end,
		},
		{
			"nicknames come from a fixed list and are checked when loaded",
			function()
				expect(Spirits.nickname(1, "en")).toBe("Momo")
				expect(Spirits.nickname(1, "ja")).toBe("モモ")
				expect(Spirits.nickname(0, "en") == nil).toBe(true)
				expect(Spirits.nickname("x", "en") == nil).toBe(true)
				local data = PlayerData.sanitize({
					spirits = {
						{ id = "a", kind = "Mochi", nick = 3 },
						{ id = "b", kind = "Kitsune", nick = 999 },
						{ id = "c", kind = "Pon", nick = "Hello" },
					},
				})
				expect(data.spirits[1].nick).toBe(3)
				expect(data.spirits[2].nick == nil).toBe(true)
				expect(data.spirits[3].nick == nil).toBe(true)
			end,
		},
		{
			"levels follow the xp steps and a tend gives more for a better run on a harder chart",
			function()
				expect(Spirits.levelOf(0)).toBe(1)
				expect(Spirits.levelOf(10)).toBe(2)
				expect(Spirits.levelOf(99)).toBe(4)
				expect(Spirits.levelOf(1e9)).toBe(Spirits.MaxLevel)
				expect(Spirits.xpForTend(1, "Expert") > Spirits.xpForTend(0.5, "Easy")).toBe(true)
				expect(Spirits.xpForTend(0, "Easy") >= 1).toBe(true)
			end,
		},
		{
			"a trait roll never repeats, gives one ride at most and runs out",
			function()
				local owned = {}
				local rides = 0
				for _ = 1, #Spirits.Traits do
					local id = Spirits.rollTrait(owned, math.random)
					if id == nil then
						break
					end
					expect(table.find(owned, id) == nil).toBe(true)
					if Spirits.trait(id).kind == "Ride" then
						rides += 1
					end
					table.insert(owned, id)
				end
				expect(rides).toBe(1)
				expect(Spirits.rollTrait(owned, math.random) == nil).toBe(true)
				expect(Spirits.rollTrait({}, function()
					return 0
				end)).toBe("Glow")
			end,
		},
		{
			"growing past a trait level gives a trait; the size follows the level",
			function()
				local spirit = { xp = 0, traits = {} }
				local level, up, grown = Spirits.addXp(spirit, 5, math.random)
				expect(level).toBe(1)
				expect(up).toBe(false)
				expect(#grown).toBe(0)
				level, up, grown = Spirits.addXp(spirit, 55, math.random) -- 60 xp: level 4, passes level 3
				expect(level).toBe(4)
				expect(up).toBe(true)
				expect(#grown).toBe(1)
				expect(#spirit.traits).toBe(1)
				local big = Spirits.sizeFactor(10, { "Big" })
				expect(big > Spirits.sizeFactor(10, {})).toBe(true)
				expect(Spirits.sizeFactor(10, {}) > Spirits.sizeFactor(1, {})).toBe(true)
			end,
		},
		{
			"a spirit travels as text and reads back; old text without growth still reads",
			function()
				local text = Spirits.encode({
					id = "a1",
					kind = "Mochi",
					bond = 9,
					nick = 3,
					xp = 60,
					traits = { "Glow", "Cloud" },
				})
				local entry = Spirits.decode(text)
				expect(entry.id).toBe("a1")
				expect(entry.level).toBe(4)
				expect(#entry.traits).toBe(2)
				expect(entry.nick).toBe(3)
				local old = Spirits.decode("b2:Kitsune:5:0")
				expect(old.level).toBe(1)
				expect(#old.traits).toBe(0)
				expect(Spirits.decode("junk") == nil).toBe(true)
				expect(Spirits.decode("c:Nope:1:0:1:") == nil).toBe(true)
				expect(#Spirits.decode("d:Pon:1:0:2:Glow+Fake+Glow").traits).toBe(1)
			end,
		},
		{
			"saved spirits keep xp and traits; bad traits are dropped",
			function()
				local data = PlayerData.sanitize({
					spirits = {
						{
							id = "a",
							kind = "Mochi",
							xp = 120,
							traits = { "Glow", "Nope", "Glow", "Cloud", "Balloon", "Wings", "Big" },
						},
						{ id = "b", kind = "Pon" },
					},
				})
				expect(data.spirits[1].xp).toBe(120)
				expect(table.concat(data.spirits[1].traits, ",")).toBe("Glow,Cloud,Wings")
				expect(data.spirits[2].xp).toBe(0)
				expect(#data.spirits[2].traits).toBe(0)
			end,
		},
		{
			"saved spirits keep their bond; old saves start at 0",
			function()
				local data = PlayerData.sanitize({
					spirits = {
						{ id = "a", kind = "Mochi", bond = 42 },
						{ id = "b", kind = "Kitsune" },
						{ id = "c", kind = "Pon", bond = -5 },
					},
				})
				expect(data.spirits[1].bond).toBe(42)
				expect(data.spirits[2].bond).toBe(0)
				expect(data.spirits[3].bond).toBe(0)
				expect(data.stats.pats).toBe(0)
			end,
		},
	}
end
