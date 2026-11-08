--!strict
-- Seed master data (prototype). The real data lives in Master_Seeds (Open Cloud); this table has the same
-- fields so the swap is mechanical. The song is chosen by the player before each Tend (Shared.Songs), not by the seed.

export type Rarity = "Common" | "Uncommon" | "Rare" | "Epic" | "Legendary"

export type Seed = {
	seedId: string,
	name: { en: string, ja: string },
	rarity: Rarity,
	price: number, -- coins
	growSeconds: number,
	baseSellPrice: number, -- coins, before mutation and weight
}

local Seeds = {}

-- Short grow times so a whole loop can be tried in a few minutes. Initial values, tune later.
-- A fruit must always sell for more than its own seed costs (even at the lowest weight), or the loop stalls.
local list: { Seed } = {
	{
		seedId = "seed_sakura",
		name = { en = "Sakura Pop", ja = "さくらポップ" },
		rarity = "Common",
		price = 20,
		growSeconds = 120,
		baseSellPrice = 30,
	},
	{
		seedId = "seed_matcha",
		name = { en = "Matcha Beat", ja = "まっちゃビート" },
		rarity = "Uncommon",
		price = 80,
		growSeconds = 180,
		baseSellPrice = 110,
	},
	{
		seedId = "seed_sora",
		name = { en = "Sora Wave", ja = "そらウェーブ" },
		rarity = "Rare",
		price = 240,
		growSeconds = 300,
		baseSellPrice = 350,
	},
}
Seeds.List = table.freeze(list)

-- Every new player starts with one of these (the free tutorial seed).
Seeds.StarterSeedId = "seed_sakura"

local byId: { [string]: Seed } = {}
for _, seed in list do
	byId[seed.seedId] = seed
end

function Seeds.get(seedId: string): Seed?
	return byId[seedId]
end

return table.freeze(Seeds)
