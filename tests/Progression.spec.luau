return function(loader, expect)
	local Progression = loader.require("src/shared/Garden/Progression")
	local Seeds = loader.require("src/shared/Garden/Seeds")
	local Shop = loader.require("src/shared/Garden/Shop")
	local PlayerData = loader.require("src/shared/Data/PlayerData")

	return {
		{
			"levels rise with xp, start at 1 and stop at the max",
			function()
				expect(Progression.levelFor(0).level).toBe(1)
				expect(Progression.levelFor(Progression.xpToReach(5)).level).toBe(5)
				expect(Progression.levelFor(Progression.xpToReach(5) - 1).level).toBe(4)
				local top = Progression.levelFor(1e9)
				expect(top.level).toBe(Progression.MaxLevel)
				expect(top.need).toBe(0)
				for level = 2, Progression.MaxLevel do
					expect(Progression.xpToReach(level) > Progression.xpToReach(level - 1)).toBeTruthy()
				end
			end,
		},
		{
			"every seed opens at a level, the starter at 1, and the shop respects it",
			function()
				expect(Progression.unlockLevelOf(Seeds.StarterSeedId)).toBe(1)
				for _, seed in Seeds.List do
					expect(Progression.unlockLevelOf(seed.seedId) <= Progression.MaxLevel).toBeTruthy()
				end
				for slot = 1, 200 do
					for _, seedId in Shop.stock(slot, 3) do
						expect(Progression.unlockLevelOf(seedId) <= 3).toBeTruthy()
					end
				end
				expect(#Shop.stock(1, 1)).toBe(1 + math.min(Shop.RotatingSlots, 1)) -- sakura + yuzu only
			end,
		},
		{
			"stars come from harvest counts and make growing faster",
			function()
				expect(Progression.starsFor(0)).toBe(0)
				expect(Progression.starsFor(1)).toBe(1)
				expect(Progression.starsFor(15)).toBe(Progression.MaxStars)
				expect(Progression.starsFor(999)).toBe(Progression.MaxStars)
				expect(Progression.growTimeMult(0)).toBe(1)
				expect(Progression.growTimeMult(5) < 1).toBeTruthy()
				expect(Progression.growTimeMult(5) > 0.5).toBeTruthy()
				expect(Progression.mutationMult(5) > 1).toBeTruthy()
			end,
		},
		{
			"a harvest adds xp and mastery, and reports level-ups with the seeds they open",
			function()
				local progress = { xp = 0, mastery = {} :: { [string]: number } }
				local result = Progression.applyHarvest(progress, "seed_sakura", nil, true)
				expect(result.xpGained).toBe(Progression.harvestXp("seed_sakura", nil) + Progression.DiscoveryXp)
				expect(progress.mastery.seed_sakura).toBe(1)
				expect(result.newStar).toBeTruthy()
				-- a big jump in xp reports every seed opened on the way
				progress.xp = Progression.xpToReach(5) - 1
				local jump = Progression.applyHarvest(progress, "seed_hanabi", "GoldenHour", false)
				expect(jump.leveledUp).toBeTruthy()
				expect(jump.level >= 5).toBeTruthy()
				expect(table.find(jump.unlocked, "seed_momo") ~= nil).toBeTruthy() -- opens at level 5
			end,
		},
		{
			"progress survives the data sanitiser and bad values are dropped",
			function()
				local clean =
					PlayerData.sanitize({ xp = 120.7, mastery = { seed_sakura = 4, nonsense = 9, seed_yuzu = -2 } })
				expect(clean.xp).toBe(120)
				expect(clean.mastery.seed_sakura).toBe(4)
				expect(clean.mastery.nonsense).toBe(nil)
				expect(clean.mastery.seed_yuzu).toBe(nil)
				expect(PlayerData.sanitize(nil).xp).toBe(0)
			end,
		},
	}
end
