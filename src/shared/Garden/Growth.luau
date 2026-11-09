--!strict
-- Plant growth rules, shared by server and client and free of Roblox Instances so Lune can test them.
--
-- A plot grows from two sources: time passing (also while the player is away) and "care":
-- points earned by tending to the beat. Both are measured in seconds of growth, so a plant with
-- growSeconds = 600 is fully grown after 600 seconds of time + care combined.

local Difficulty = require(script.Parent.Parent.Difficulty)
local Rank = require(script.Parent.Parent.Rank)

export type Stage = "Seed" | "Sprout" | "Sapling" | "Bloom" | "Fruit"

export type Plot = {
	seedId: string,
	plantedAt: number, -- unix seconds
	careGauge: number, -- growth seconds earned from tending
	lastTendAt: number, -- unix seconds, 0 = never tended
	bestPerfectStreak: number, -- longest Perfect streak over all tends (feeds the mutation roll)
	mutationMult: number, -- best Difficulty.MutationChanceMultiplier used while tending
	mutation: string?, -- the mutation rolled when the fruit ripened (Garden/Mutations); nil = a plain fruit
	rolled: boolean?, -- the roll has been made
	growMult: number?, -- share of growSeconds this plant needs (seed mastery, fixed when planted); nil = 1
}

local Growth = {}

-- Share of growSeconds at which each stage starts (initial values).
local stages: { { name: Stage, from: number } } = {
	{ name = "Seed", from = 0 },
	{ name = "Sprout", from = 0.2 },
	{ name = "Sapling", from = 0.5 },
	{ name = "Bloom", from = 0.8 },
	{ name = "Fruit", from = 1 },
}
Growth.Stages = table.freeze(stages)

-- A ripe fruit stays fresh for FreshSeconds; after that it shrivels: its weight (and so its value) falls in a
-- straight line to MinFreshness over RotSeconds, then stays there (spec: harvest again soon).
Growth.FreshSeconds = 600
Growth.RotSeconds = 1200
Growth.MinFreshness = 0.5

-- Growth seconds a perfect Easy tend is worth. Other difficulties scale it (Difficulty.GrowthMultiplier),
-- and an S / A rank adds a bonus (Rank.GrowthBonus). A run lasts about 90 s, so this is worth more than
-- the time it takes; the cooldown below keeps tending from being the only way to grow.
Growth.MaxTendPoints = 150

-- The same plant cannot be tended again for this long.
Growth.TendCooldownSeconds = 30

function Growth.newPlot(seedId: string, now: number, growMult: number?): Plot
	return {
		seedId = seedId,
		plantedAt = now,
		careGauge = 0,
		lastTendAt = 0,
		bestPerfectStreak = 0,
		mutationMult = 1,
		growMult = growMult,
	}
end

-- Applies one validated tend to the plot.
function Growth.applyTend(plot: Plot, points: number, perfectStreak: number, mutationMult: number, now: number)
	plot.careGauge += points
	plot.lastTendAt = now
	plot.bestPerfectStreak = math.max(plot.bestPerfectStreak, perfectStreak)
	plot.mutationMult = math.max(plot.mutationMult, mutationMult)
end

-- Growth seconds so far (time + care), capped at growSeconds.
function Growth.progressSeconds(plot: Plot, growSeconds: number, now: number): number
	local elapsed = math.max(0, now - plot.plantedAt)
	return math.min(growSeconds, elapsed + plot.careGauge)
end

-- Unix time the plant became ripe. Progress is time + care, so it is ripe once `elapsed >= growSeconds - care`.
function Growth.readyAt(plot: Plot, growSeconds: number): number
	return plot.plantedAt + math.max(0, growSeconds - plot.careGauge)
end

-- 1 while fresh, down to MinFreshness when overripe. `growSeconds` is the seed's (mastery-adjusted) grow time.
-- `holdMult` stretches the fresh time (a spirit's passive).
function Growth.freshness(plot: Plot, growSeconds: number, now: number, holdMult: number?): number
	local late = now - (Growth.readyAt(plot, growSeconds) + Growth.FreshSeconds * (holdMult or 1))
	if late <= 0 then
		return 1
	end
	return 1 - (1 - Growth.MinFreshness) * math.min(1, late / Growth.RotSeconds)
end

-- 0..1
function Growth.fraction(plot: Plot, growSeconds: number, now: number): number
	return math.clamp(Growth.progressSeconds(plot, growSeconds, now) / growSeconds, 0, 1)
end

function Growth.stageFor(fraction: number): Stage
	local result: Stage = "Seed"
	for _, s in stages do
		if fraction >= s.from then
			result = s.name
		end
	end
	return result
end

-- Growth seconds earned by one tend. `accuracy` is the server-verified 0..1 value from the tally.
function Growth.tendPoints(accuracy: number, difficulty: Difficulty.Name): number
	local multiplier = Difficulty.GrowthMultiplier[difficulty]
	local bonus = Rank.GrowthBonus[Rank.forAccuracy(accuracy)]
	return math.round(Growth.MaxTendPoints * math.clamp(accuracy, 0, 1) * multiplier * bonus)
end

-- Seconds until the plot can be tended again (0 = ready now).
function Growth.cooldownLeft(plot: Plot, now: number, cooldownSeconds: number?): number
	local cooldown = cooldownSeconds or Growth.TendCooldownSeconds
	if plot.lastTendAt <= 0 then
		return 0
	end
	return math.max(0, plot.lastTendAt + cooldown - now)
end

return table.freeze(Growth)
