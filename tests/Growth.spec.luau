return function(loader, expect)
	local Growth = loader.require("src/shared/Garden/Growth")

	local function plot(plantedAt: number, care: number, lastTendAt: number?)
		return { seedId = "seed_test", plantedAt = plantedAt, careGauge = care, lastTendAt = lastTendAt or 0 }
	end

	return {
		{
			"stage follows the share of growth",
			function()
				expect(Growth.stageFor(0)).toBe("Seed")
				expect(Growth.stageFor(0.19)).toBe("Seed")
				expect(Growth.stageFor(0.2)).toBe("Sprout")
				expect(Growth.stageFor(0.5)).toBe("Sapling")
				expect(Growth.stageFor(0.8)).toBe("Bloom")
				expect(Growth.stageFor(1)).toBe("Fruit")
			end,
		},
		{
			"progress adds time and care and is capped",
			function()
				expect(Growth.progressSeconds(plot(1000, 0), 600, 1100)).toBe(100)
				expect(Growth.progressSeconds(plot(1000, 50), 600, 1100)).toBe(150)
				expect(Growth.progressSeconds(plot(1000, 500), 600, 2000)).toBe(600)
				expect(Growth.fraction(plot(1000, 150), 600, 1150)).toBeNear(0.5, 0.0001)
			end,
		},
		{
			"time before planting does not count",
			function()
				expect(Growth.progressSeconds(plot(1000, 0), 600, 900)).toBe(0)
			end,
		},
		{
			"harder difficulty pays more for the same accuracy",
			function()
				local easy = Growth.tendPoints(0.8, "Easy")
				local normal = Growth.tendPoints(0.8, "Normal")
				local hard = Growth.tendPoints(0.8, "Hard")
				expect(easy).toBe(120)
				expect(normal).toBe(150)
				expect(hard).toBe(180)
			end,
		},
		{
			"easy still grows the plant and accuracy is clamped",
			function()
				expect(Growth.tendPoints(0.1, "Easy") > 0).toBeTruthy()
				expect(Growth.tendPoints(0, "Hard")).toBe(0)
				expect(Growth.tendPoints(5, "Easy")).toBe(math.round(Growth.MaxTendPoints * 1.2)) -- S rank bonus
			end,
		},
		{
			"cooldown counts down from the last tend",
			function()
				expect(Growth.cooldownLeft(plot(0, 0, 0), 500)).toBe(0)
				expect(Growth.cooldownLeft(plot(0, 0, 1000), 1020)).toBe(10)
				expect(Growth.cooldownLeft(plot(0, 0, 1000), 1030)).toBe(0)
				expect(Growth.cooldownLeft(plot(0, 0, 1000), 1004, 10)).toBe(6)
			end,
		},
		{
			"a ripe fruit stays fresh, then shrivels to the floor and stays there",
			function()
				-- planted at 0, no care, 1000 s to grow: ripe at 1000
				local p = plot(0, 0, 0)
				expect(Growth.readyAt(p, 1000)).toBe(1000)
				expect(Growth.freshness(p, 1000, 1000 + Growth.FreshSeconds)).toBe(1)
				local half = 1000 + Growth.FreshSeconds + Growth.RotSeconds / 2
				expect(Growth.freshness(p, 1000, half)).toBeNear((1 + Growth.MinFreshness) / 2, 1e-6)
				expect(Growth.freshness(p, 1000, 1e9)).toBe(Growth.MinFreshness)
			end,
		},
		{
			"care brings the ripe time forward",
			function()
				local p = plot(0, 0, 0)
				p.careGauge = 400
				expect(Growth.readyAt(p, 1000)).toBe(600)
				p.careGauge = 5000
				expect(Growth.readyAt(p, 1000)).toBe(0)
			end,
		},
	}
end
