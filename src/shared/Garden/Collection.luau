--!strict
-- The collection book: one entry for every seed x variant (a plain fruit or one of the mutations).
-- The first time a fruit of an entry is harvested the entry is discovered and pays a coin reward;
-- completing all the variants of a seed pays a Spirit Egg. Values are initial, tune from playtest data.

local Mutations = require(script.Parent.Mutations)
local Seeds = require(script.Parent.Seeds)

local Collection = {}

export type Book = { [string]: boolean } -- "seedId|variant" -> true

Collection.Plain = "Normal"

-- Coins for discovering a variant for the first time.
Collection.Reward = table.freeze({
	Normal = 10,
	Film = 25,
	Vapor = 50,
	GoldenHour = 120,
}) :: { [string]: number }

Collection.CompletionEggs = 1

-- Variants of every seed, plain first, then the mutations from the most common to the rarest.
local variants: { string } = { Collection.Plain }
for i = #Mutations.Defs, 1, -1 do
	table.insert(variants, Mutations.Defs[i].id)
end
Collection.Variants = table.freeze(variants)

function Collection.key(seedId: string, mutation: string?): string
	return `{seedId}|{mutation or Collection.Plain}`
end

function Collection.isValidKey(key: string): boolean
	local seedId, variant = string.match(key, "^([^|]+)|([^|]+)$")
	return seedId ~= nil and Seeds.get(seedId) ~= nil and table.find(Collection.Variants :: any, variant) ~= nil
end

function Collection.has(book: Book, seedId: string, mutation: string?): boolean
	return book[Collection.key(seedId, mutation)] == true
end

-- (discovered, total) for one seed.
function Collection.seedProgress(book: Book, seedId: string): (number, number)
	local found = 0
	for _, variant in Collection.Variants do
		if book[`{seedId}|{variant}`] then
			found += 1
		end
	end
	return found, #Collection.Variants
end

-- (discovered, total) over the whole book.
function Collection.progress(book: Book): (number, number)
	local found, total = 0, 0
	for _, seed in Seeds.List do
		local f, t = Collection.seedProgress(book, seed.seedId)
		found += f
		total += t
	end
	return found, total
end

export type Discovery = { isNew: boolean, coins: number, completedSeed: boolean }

-- Records a harvested fruit in the book. Returns what it paid (nothing when it was already known).
function Collection.discover(book: Book, seedId: string, mutation: string?): Discovery
	local key = Collection.key(seedId, mutation)
	if book[key] then
		return { isNew = false, coins = 0, completedSeed = false }
	end
	book[key] = true
	local found, total = Collection.seedProgress(book, seedId)
	return {
		isNew = true,
		coins = Collection.Reward[mutation or Collection.Plain] or 0,
		completedSeed = found == total,
	}
end

return table.freeze(Collection)
