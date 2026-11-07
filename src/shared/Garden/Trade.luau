--!strict
-- Player-to-player trading rules: what an offer is, whether a player really owns it, its estimated
-- value, and the atomic swap. Pure functions on PlayerData, tested in Lune. The server is the only
-- place that calls `swap`; the client only builds offers to show and send.

local Economy = require(script.Parent.Economy)
local PlayerData = require(script.Parent.Parent.Data.PlayerData)
local Seeds = require(script.Parent.Seeds)
local Spirits = require(script.Parent.Spirits)

export type Offer = {
	fruits: { number }, -- indices into the owner's data.fruits
	seeds: { [string]: number }, -- seedId -> count
	spirits: { string }, -- spirit ids
}

local Trade = {}

Trade.MaxItems = 30 -- per kind, per offer

function Trade.emptyOffer(): Offer
	return { fruits = {}, seeds = {}, spirits = {} }
end

local function posInt(v: any): number?
	if type(v) ~= "number" or v ~= v or v < 1 or v > 1e6 then
		return nil
	end
	return math.floor(v)
end

-- Rebuilds a clean offer from whatever the client sent (never trust its shape).
function Trade.sanitizeOffer(raw: any): Offer
	local offer = Trade.emptyOffer()
	if type(raw) ~= "table" then
		return offer
	end
	if type(raw.fruits) == "table" then
		local seen: { [number]: boolean } = {}
		for _, index in raw.fruits do
			local i = posInt(index)
			if i and not seen[i] and #offer.fruits < Trade.MaxItems then
				seen[i] = true
				table.insert(offer.fruits, i)
			end
		end
	end
	if type(raw.seeds) == "table" then
		local total = 0
		for seedId, count in raw.seeds do
			local n = posInt(count)
			if type(seedId) == "string" and n and total < Trade.MaxItems then
				n = math.min(n, Trade.MaxItems - total)
				offer.seeds[seedId] = n
				total += n
			end
		end
	end
	if type(raw.spirits) == "table" then
		local seen: { [string]: boolean } = {}
		for _, id in raw.spirits do
			if type(id) == "string" and not seen[id] and #offer.spirits < Trade.MaxItems then
				seen[id] = true
				table.insert(offer.spirits, id)
			end
		end
	end
	return offer
end

function Trade.isEmpty(offer: Offer): boolean
	return #offer.fruits == 0 and next(offer.seeds) == nil and #offer.spirits == 0
end

local function findSpirit(data: PlayerData.Data, id: string): PlayerData.SpiritInstance?
	for _, spirit in data.spirits do
		if spirit.id == id then
			return spirit
		end
	end
	return nil
end

-- Does `data` really own everything in `offer`?
function Trade.check(data: PlayerData.Data, offer: Offer): (boolean, string?)
	for _, index in offer.fruits do
		if data.fruits[index] == nil then
			return false, "you no longer have that fruit"
		end
	end
	for seedId, count in offer.seeds do
		if Seeds.get(seedId) == nil or (data.seeds[seedId] or 0) < count then
			return false, "you no longer have those seeds"
		end
	end
	for _, id in offer.spirits do
		if findSpirit(data, id) == nil then
			return false, "you no longer have that spirit"
		end
	end
	return true, nil
end

-- Estimated value in coins, shown on the trade screen to help against scams.
function Trade.value(data: PlayerData.Data, offer: Offer): number
	local total = 0
	for _, index in offer.fruits do
		local fruit = data.fruits[index]
		if fruit then
			total += Economy.fruitValue(fruit.seedId, fruit.mutation, fruit.weight)
		end
	end
	for seedId, count in offer.seeds do
		local seed = Seeds.get(seedId)
		if seed then
			total += seed.price * count
		end
	end
	for _, id in offer.spirits do
		local spirit = findSpirit(data, id)
		local def = spirit and Spirits.get(spirit.kind)
		if def then
			total += def.estimatedValue
		end
	end
	return total
end

-- Takes the offered items out of `from` and returns them (does not touch the receiver yet).
local function take(from: PlayerData.Data, offer: Offer)
	local fruits: { PlayerData.Fruit } = {}
	local drop: { [number]: boolean } = {}
	for _, index in offer.fruits do
		table.insert(fruits, from.fruits[index])
		drop[index] = true
	end
	local kept: { PlayerData.Fruit } = {}
	for i, fruit in from.fruits do
		if not drop[i] then
			table.insert(kept, fruit)
		end
	end
	from.fruits = kept

	local seeds: { [string]: number } = {}
	for seedId, count in offer.seeds do
		seeds[seedId] = count
		local left = (from.seeds[seedId] or 0) - count
		if left > 0 then
			from.seeds[seedId] = left
		else
			from.seeds[seedId] = nil
		end
	end

	local spirits: { PlayerData.SpiritInstance } = {}
	local giveIds: { [string]: boolean } = {}
	for _, id in offer.spirits do
		giveIds[id] = true
		local spirit = findSpirit(from, id)
		if spirit then
			table.insert(spirits, spirit)
		end
	end
	local keptSpirits: { PlayerData.SpiritInstance } = {}
	for _, spirit in from.spirits do
		if not giveIds[spirit.id] then
			table.insert(keptSpirits, spirit)
		end
	end
	from.spirits = keptSpirits
	if from.equippedSpirit and giveIds[from.equippedSpirit] then
		from.equippedSpirit = nil -- a traded-away spirit is no longer equipped
	end
	return { fruits = fruits, seeds = seeds, spirits = spirits }
end

local function give(to: PlayerData.Data, items: any)
	for _, fruit in items.fruits do
		table.insert(to.fruits, fruit)
	end
	for seedId, count in items.seeds do
		to.seeds[seedId] = (to.seeds[seedId] or 0) + count
	end
	for _, spirit in items.spirits do
		table.insert(to.spirits, spirit)
	end
end

-- Can `data` hold what it would receive after giving away its own offer? (counts are enough for the caps)
local function fits(data: PlayerData.Data, giving: Offer, receiving: Offer): boolean
	local fruitsAfter = #data.fruits - #giving.fruits + #receiving.fruits
	local spiritsAfter = #data.spirits - #giving.spirits + #receiving.spirits
	return fruitsAfter <= PlayerData.MaxFruits and spiritsAfter <= Spirits.MaxOwned
end

-- Swaps the two offers between the two players, all or nothing.
function Trade.swap(a: PlayerData.Data, b: PlayerData.Data, offerA: Offer, offerB: Offer): (boolean, string?)
	if Trade.isEmpty(offerA) and Trade.isEmpty(offerB) then
		return false, "nothing to trade"
	end
	local okA, reasonA = Trade.check(a, offerA)
	if not okA then
		return false, reasonA
	end
	local okB, reasonB = Trade.check(b, offerB)
	if not okB then
		return false, reasonB
	end
	if not fits(a, offerA, offerB) or not fits(b, offerB, offerA) then
		return false, "someone's bag is full"
	end
	local fromA = take(a, offerA)
	local fromB = take(b, offerB)
	give(b, fromA)
	give(a, fromB)
	return true, nil
end

return table.freeze(Trade)
