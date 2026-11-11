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
