return function(loader, expect)
	local Mutations = loader.require("src/shared/Garden/Mutations")
	local Economy = loader.require("src/shared/Garden/Economy")
	local Growth = loader.require("src/shared/Garden/Growth")
	local Seeds = loader.require("src/shared/Garden/Seeds")
	local PlayerData = loader.require("src/shared/Data/PlayerData")
	local SessionLock = loader.require("src/shared/Data/SessionLock")
	local Tutorial = loader.require("src/shared/Garden/Tutorial")
	local Strings = loader.require("src/shared/Strings")

	local function constant(v: number)
		return function()
			return v
		end
	end

	return {
		{
			"mutation never triggers when every roll is high",
			function()
				expect(Mutations.roll(30, 1.4, constant(0.99))).toBe(nil)
			end,
		},
		{
			"mutation picks the rarest one that succeeds",
			function()
				expect(Mutations.roll(0, 1, constant(0))).toBe("GoldenHour")
				-- 0.05 beats Vapor (0.10) but not GoldenHour (0.04)
				expect(Mutations.roll(0, 1, constant(0.05))).toBe("Vapor")
				expect(Mutations.roll(0, 1, constant(0.15))).toBe("Film")
			end,
		},
		{
			"longer perfect streaks and harder difficulty raise the chance",
			function()
				local film = Mutations.Defs[3]
				local base = Mutations.chance(film, 0, 1)
				expect(Mutations.chance(film, 10, 1) > base).toBeTruthy()
				expect(Mutations.chance(film, 0, 1.4) > base).toBeTruthy()
				-- streak counts up to the cap only
				expect(Mutations.chance(film, 999, 1)).toBe(Mutations.chance(film, Mutations.MaxStreakCounted, 1))
				expect(Mutations.chance(film, 999, 99) <= Mutations.MaxChance).toBeTruthy()
			end,
		},
		{
			"fruit value = base x mutation x weight",
			function()
				-- Sakura Pop sells for 30
				expect(Economy.fruitValue("seed_sakura", nil, 1)).toBe(30)
				expect(Economy.fruitValue("seed_sakura", "Film", 1)).toBe(45)
				expect(Economy.fruitValue("seed_sakura", "GoldenHour", 1.2)).toBe(108)
				expect(Economy.fruitValue("nope", nil, 1)).toBe(0)
				expect(Economy.fruitValue("seed_sakura", nil, 0.01) >= 1).toBeTruthy()
			end,
		},
		{
			"every fruit sells for more than its seed costs, even at the lowest weight",
			function()
				for _, seed in Seeds.List do
					local worst = Economy.fruitValue(seed.seedId, nil, Economy.WeightRange.min)
					expect(worst > seed.price).toBeTruthy()
				end
			end,
		},
		{
			"weight stays inside its range",
			function()
				expect(Economy.rollWeight(constant(0))).toBe(0.8)
				expect(Economy.rollWeight(constant(0.999))).toBe(1.2)
			end,
		},
		{
			"applyTend keeps the best streak and the best difficulty multiplier",
			function()
				local plot = Growth.newPlot("seed_sakura", 1000)
				Growth.applyTend(plot, 30, 8, 1.2, 1100)
				Growth.applyTend(plot, 20, 3, 1, 1200)
				expect(plot.careGauge).toBe(50)
				expect(plot.bestPerfectStreak).toBe(8)
				expect(plot.mutationMult).toBe(1.2)
				expect(plot.lastTendAt).toBe(1200)
			end,
		},
		{
			"new players get one free starter seed and no coins",
			function()
				local d = PlayerData.new()
				expect(d.coins).toBe(0)
				expect(d.seeds[Seeds.StarterSeedId]).toBe(1)
			end,
		},
		{
			"sanitize repairs damaged data and drops unknown things",
			function()
				local d = PlayerData.sanitize({
					coins = -50,
					seeds = { seed_sakura = 2.7, seed_unknown = 5, seed_matcha = "x" },
					fruits = { { seedId = "seed_sakura", weight = 99 }, { seedId = "nope" }, "junk" },
					plots = { ["1"] = { seedId = "seed_sora", plantedAt = 5 }, ["2"] = { seedId = "nope" } },
					settings = { latencyMs = 9999 },
				})
				expect(d.coins).toBe(0)
				expect(d.seeds.seed_sakura).toBe(2)
				expect(d.seeds.seed_unknown).toBe(nil)
				expect(d.seeds.seed_matcha).toBe(nil)
				expect(#d.fruits).toBe(1)
				expect(d.fruits[1].weight).toBe(10)
				expect(d.plots["1"].seedId).toBe("seed_sora")
				expect(d.plots["1"].mutationMult).toBe(1)
				expect(d.plots["2"]).toBe(nil)
				expect(d.settings.latencyMs).toBe(300)
			end,
		},
		{
			"sanitize accepts nil and nonsense",
			function()
				expect(PlayerData.sanitize(nil).coins).toBe(0)
				expect(PlayerData.sanitize("hello").v).toBe(PlayerData.Version)
			end,
		},
		{
			"sanitize keeps good data as it is",
			function()
				local d = PlayerData.new()
				d.coins = 120
				d.fruits = { { seedId = "seed_matcha", mutation = "Vapor", weight = 1.1 } }
				d.plots["1"] = Growth.newPlot("seed_matcha", 1234)
				local again = PlayerData.sanitize(d)
				expect(again.coins).toBe(120)
				expect(again.fruits[1].mutation).toBe("Vapor")
				expect(again.plots["1"].plantedAt).toBe(1234)
			end,
		},
		{
			"a fresh lock from another server blocks loading",
			function()
				local stored = { lock = SessionLock.make("other", 1000) }
				expect(SessionLock.heldByOther(stored, "me", 1050)).toBe(true)
			end,
		},
		{
			"my own lock, no lock and an expired lock do not block",
			function()
				expect(SessionLock.heldByOther({ lock = SessionLock.make("me", 1000) }, "me", 1050)).toBe(false)
				expect(SessionLock.heldByOther({ coins = 5 }, "me", 1050)).toBe(false)
				expect(SessionLock.heldByOther(nil, "me", 1050)).toBe(false)
				local old = { lock = SessionLock.make("other", 1000) }
				expect(SessionLock.heldByOther(old, "me", 1000 + SessionLock.ExpireSeconds)).toBe(false)
			end,
		},
		{
			"a damaged lock never blocks a player",
			function()
				expect(SessionLock.heldByOther({ lock = "x" }, "me", 1)).toBe(false)
				expect(SessionLock.heldByOther({ lock = { jobId = 5 } }, "me", 1)).toBe(false)
			end,
		},
		{
			"the tutorial moves forward only on the event the step waits for",
			function()
				expect(Tutorial.advance(1, "plant")).toBe(2)
				expect(Tutorial.advance(1, "sell")).toBe(1)
				expect(Tutorial.advance(2, "plant")).toBe(2)
				expect(Tutorial.advance(5, "buy")).toBe(Tutorial.Done)
				expect(Tutorial.advance(Tutorial.Done, "buy")).toBe(Tutorial.Done)
			end,
		},
		{
			"one full lap of the loop finishes the tutorial",
			function()
				local step = 1
				for _, event in { "plant", "tend", "harvest", "sell", "buy" } do
					expect(Tutorial.isActive(step)).toBe(true)
					step = Tutorial.advance(step, event)
				end
				expect(step).toBe(Tutorial.Done)
				expect(Tutorial.isActive(step)).toBe(false)
			end,
		},
		{
			"new players start the tutorial, players with progress skip it",
			function()
				expect(PlayerData.new().tutorialStep).toBe(1)
				expect(PlayerData.sanitize(nil).tutorialStep).toBe(1)
				-- data saved before the tutorial existed
				expect(PlayerData.sanitize({ coins = 10 }).tutorialStep).toBe(Tutorial.Done)
				expect(PlayerData.sanitize({ stats = { harvests = 3 } }).tutorialStep).toBe(Tutorial.Done)
				expect(PlayerData.sanitize({ plots = { ["1"] = { seedId = "seed_sakura" } } }).tutorialStep).toBe(
					Tutorial.Done
				)
			end,
		},
		{
			"a saved tutorial step is kept and kept in range",
			function()
				expect(PlayerData.sanitize({ tutorialStep = 3 }).tutorialStep).toBe(3)
				expect(PlayerData.sanitize({ tutorialStep = 99 }).tutorialStep).toBe(Tutorial.Done)
				expect(PlayerData.sanitize({ tutorialStep = -4 }).tutorialStep).toBe(1)
			end,
		},
		{
			"strings fall back to English and then to the key",
			function()
				expect(Strings.get("tutorial_skip", "ja")).toBe("スキップ")
				expect(Strings.get("tutorial_skip", "fr")).toBe("Skip")
				expect(Strings.get("no_such_key", "ja")).toBe("no_such_key")
				expect(Strings.langFromLocale("ja-jp")).toBe("ja")
				expect(Strings.langFromLocale("en-us")).toBe("en")
			end,
		},
		{
			"every tutorial step has text in both languages",
			function()
				for _, key in
					{
						"tutorial_plant",
						"tutorial_tend",
						"tutorial_harvest",
						"tutorial_sell",
						"tutorial_buy",
						"tutorial_done",
					}
				do
					expect(Strings.get(key, "en") ~= key).toBeTruthy()
					expect(Strings.get(key, "ja") ~= Strings.get(key, "en")).toBeTruthy()
				end
			end,
		},
		{
			"a rolled mutation survives the data sanitiser, an unknown one does not",
			function()
				local plots = {
					["1"] = { seedId = "seed_sakura", plantedAt = 5, careGauge = 1, rolled = true, mutation = "Vapor" },
					["2"] = {
						seedId = "seed_sakura",
						plantedAt = 5,
						careGauge = 1,
						rolled = true,
						mutation = "Nonsense",
					},
					["3"] = { seedId = "seed_sakura", plantedAt = 5, careGauge = 1, mutation = "Vapor" }, -- not rolled
				}
				local clean = PlayerData.sanitize({ plots = plots })
				expect(clean.plots["1"].mutation).toBe("Vapor")
				expect(clean.plots["1"].rolled).toBe(true)
				expect(clean.plots["2"].mutation).toBe(nil)
				expect(clean.plots["3"].mutation).toBe(nil)
			end,
		},
	}
end
