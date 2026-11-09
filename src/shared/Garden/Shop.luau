--!strict
-- The seed shop's stock. It changes every StockSeconds and is a pure function of the time slot, so the
-- server and every client agree on it without storing anything. The starter seed is always in stock (the
-- tutorial needs it); the other slots are drawn by rarity.

local Progression = require(script.Parent.Progression)
local Seeds = require(script.Parent.Seeds)

local Shop = {}

Shop.StockSeconds = 300 -- spec: the stock changes every 5 minutes
Shop.RotatingSlots = 3 -- seeds drawn each time, on top of the starter seed

-- Draw weight by rarity (initial values).
local RARITY_WEIGHT: { [string]: number } = {
	Common = 60,
	Uncommon = 25,
	Rare = 12,
	Epic = 3,
	Legendary = 1,
}

function Shop.slotOf(now: number): number
	return math.floor(now / Shop.StockSeconds)
end

function Shop.secondsLeft(now: number): number
	return Shop.StockSeconds - (now % Shop.StockSeconds)
end

-- A small deterministic random generator (the same numbers on every machine; Lune has no Random).
local function generator(seed: number): () -> number
	local state = (seed * 2654435761) % 4294967296
	return function(): number
		state = (state * 1664525 + 1013904223) % 4294967296
		return state / 4294967296
	end
end

-- Seed ids in stock during `slot`, the starter seed first. Only seeds the garden level has opened are drawn
-- (`level` nil = every seed).
function Shop.stock(slot: number, level: number?, shift: number?): { string }
	local random = generator(slot + (shift or 0) * 100003) -- `shift`: a personal restock
	random() -- the first value of a fresh generator is weak; skip it
	local result: { string } = { Seeds.StarterSeedId }
	local pool: { Seeds.Seed } = {}
	for _, seed in Seeds.List do
		if seed.seedId ~= Seeds.StarterSeedId and (level == nil or Progression.unlockLevelOf(seed.seedId) <= level) then
			table.insert(pool, seed)
		end
	end
	for _ = 1, math.min(Shop.RotatingSlots, #pool) do
		local total = 0
		for _, seed in pool do
			total += RARITY_WEIGHT[seed.rarity] or 1
		end
		local pick = random() * total
		local chosen = #pool
		for i, seed in pool do
			pick -= RARITY_WEIGHT[seed.rarity] or 1
			if pick < 0 then
				chosen = i
				break
			end
		end
		table.insert(result, pool[chosen].seedId)
		table.remove(pool, chosen)
	end
	return result
end

function Shop.inStock(seedId: string, now: number, level: number?, shift: number?): boolean
	return table.find(Shop.stock(Shop.slotOf(now), level, shift), seedId) ~= nil
end

return table.freeze(Shop)
