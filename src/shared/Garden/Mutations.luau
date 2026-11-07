--!strict
-- Mutation roll at harvest. A longer Perfect streak while tending raises the chance, and so does a
-- harder difficulty (Difficulty.MutationChanceMultiplier). Values are initial, tune from playtest data.

export type Name = "Film" | "Vapor" | "GoldenHour"

export type Def = {
	id: Name,
	multiplier: number, -- sell price multiplier
	baseChance: number,
	perfectStreakBonus: number, -- added chance per Perfect in the best streak
}

local Mutations = {}

-- Rarest first: the roll tries them in this order and the first success wins.
local defs: { Def } = {
	{ id = "GoldenHour", multiplier = 3, baseChance = 0.04, perfectStreakBonus = 0.001 },
	{ id = "Vapor", multiplier = 2, baseChance = 0.1, perfectStreakBonus = 0.002 },
	{ id = "Film", multiplier = 1.5, baseChance = 0.2, perfectStreakBonus = 0.004 },
}
Mutations.Defs = table.freeze(defs)

Mutations.MaxStreakCounted = 30
Mutations.MaxChance = 0.9

function Mutations.chance(def: Def, perfectStreak: number, chanceMultiplier: number): number
	local streak = math.clamp(perfectStreak, 0, Mutations.MaxStreakCounted)
	return math.clamp((def.baseChance + def.perfectStreakBonus * streak) * chanceMultiplier, 0, Mutations.MaxChance)
end

-- `random` returns a number in [0, 1) (math.random in game, a fake in tests).
function Mutations.roll(perfectStreak: number, chanceMultiplier: number, random: () -> number): Name?
	for _, def in defs do
		if random() < Mutations.chance(def, perfectStreak, chanceMultiplier) then
			return def.id
		end
	end
	return nil
end

function Mutations.multiplier(name: string?): number
	if name == nil then
		return 1
	end
	for _, def in defs do
		if def.id == name then
			return def.multiplier
		end
	end
	return 1
end

-- "GoldenHour" -> "Golden Hour"
function Mutations.displayName(name: string): string
	return (string.gsub(name, "(%l)(%u)", "%1 %2"))
end

return table.freeze(Mutations)
