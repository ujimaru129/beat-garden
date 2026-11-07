--!strict
-- Prices: what a fruit sells for. Seed prices are on the seed data (Seeds.price).

local Mutations = require(script.Parent.Mutations)
local Seeds = require(script.Parent.Seeds)

local Economy = {}

Economy.WeightRange = table.freeze({ min = 0.8, max = 1.2 })

-- `random` returns a number in [0, 1).
function Economy.rollWeight(random: () -> number): number
	local w = Economy.WeightRange.min + (Economy.WeightRange.max - Economy.WeightRange.min) * random()
	return math.round(w * 100) / 100
end

-- Sell price = base price x mutation multiplier x weight, at least 1 coin.
function Economy.fruitValue(seedId: string, mutation: string?, weight: number): number
	local seed = Seeds.get(seedId)
	if not seed then
		return 0
	end
	return math.max(1, math.round(seed.baseSellPrice * Mutations.multiplier(mutation) * weight))
end

return table.freeze(Economy)
