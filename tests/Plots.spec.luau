return function(loader, expect)
	local Plots = loader.require("src/shared/Garden/Plots")
	local PlayerData = loader.require("src/shared/Data/PlayerData")
	local Growth = loader.require("src/shared/Garden/Growth")

	return {
		{
			"plot keys are '1'..Max and nothing else",
			function()
				expect(Plots.indexOf("1")).toBe(1)
				expect(Plots.indexOf("12")).toBe(Plots.Max)
				expect(Plots.indexOf("0")).toBe(nil)
				expect(Plots.indexOf("13")).toBe(nil)
				expect(Plots.indexOf("1.5")).toBe(nil)
				expect(Plots.indexOf("01")).toBe(nil)
				expect(Plots.indexOf(2)).toBe(nil)
			end,
		},
		{
			"every plot of every territory has its own spot on the island",
			function()
				local spots: { { number } } = {}
				for slot = 1, Plots.Slots do
					for index = 1, Plots.Max do
						local x, z = Plots.place(0, 0, slot, index)
						expect(math.sqrt(x * x + z * z) < 110).toBe(true)
						for _, other in spots do
							local dx, dz = x - other[1], z - other[2]
							expect(math.sqrt(dx * dx + dz * dz) >= 11).toBe(true)
						end
						table.insert(spots, { x, z })
					end
				end
			end,
		},
		{
			"every extra plot has a price and the first is free",
			function()
				expect(Plots.Price[1]).toBe(nil)
				for i = 2, Plots.CoinMax do
					expect(Plots.Price[i] > 0).toBe(true)
				end
			end,
		},
		{
			"new players own one plot; sanitize clamps the count",
			function()
				expect(PlayerData.new().plotCount).toBe(1)
				expect(PlayerData.sanitize({ plotCount = 99 }).plotCount).toBe(Plots.CoinMax)
				expect(PlayerData.sanitize({ plotCount = -5 }).plotCount).toBe(1)
			end,
		},
		{
			"a plant in a plot counts as owning that plot",
			function()
				local d = PlayerData.sanitize({ plots = { ["2"] = Growth.newPlot("seed_sakura", 5) } })
				expect(d.plotCount).toBe(2)
				expect(d.plots["2"] ~= nil).toBe(true)
			end,
		},
		{
			"pass plots never raise the coin plot count",
			function()
				local d = PlayerData.sanitize({ plots = { ["11"] = Growth.newPlot("seed_sakura", 5) } })
				expect(d.plotCount).toBe(1)
				expect(d.plots["11"] ~= nil).toBe(true)
				expect(Plots.isPass(Plots.CoinMax)).toBe(false)
				expect(Plots.isPass(Plots.CoinMax + 1)).toBe(true)
			end,
		},
		{
			"prices rise with every plot and the looks get fancier",
			function()
				for i = 3, Plots.CoinMax do
					expect(Plots.Price[i] > Plots.Price[i - 1]).toBe(true)
				end
				expect(Plots.tier(1)).toBe(1)
				expect(Plots.tier(Plots.Max)).toBe(5)
				for i = 2, Plots.Max do
					expect(Plots.tier(i) >= Plots.tier(i - 1)).toBe(true)
				end
			end,
		},
	}
end
