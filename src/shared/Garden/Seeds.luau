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
	favoriteGenre: string, -- Shared.Garden.Genres: a song of this genre gives a tend bonus
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
		growSeconds = 480,
		baseSellPrice = 30,
		favoriteGenre = "Pop",
	},
	{
		seedId = "seed_yuzu",
		name = { en = "Yuzu Punch", ja = "ゆずパンチ" },
		rarity = "Common",
		price = 40,
		growSeconds = 600,
		baseSellPrice = 62,
		favoriteGenre = "Rock",
	},
	{
		seedId = "seed_ramune",
		name = { en = "Ramune Fizz", ja = "ラムネフィズ" },
		rarity = "Common",
		price = 55,
		growSeconds = 600,
		baseSellPrice = 85,
		favoriteGenre = "Dance",
	},
	{
		seedId = "seed_matcha",
		name = { en = "Matcha Beat", ja = "まっちゃビート" },
		rarity = "Uncommon",
		price = 80,
		growSeconds = 720,
		baseSellPrice = 110,
		favoriteGenre = "Japan",
	},
	{
		seedId = "seed_momo",
		name = { en = "Momo Melody", ja = "ももメロディ" },
		rarity = "Uncommon",
		price = 130,
		growSeconds = 840,
		baseSellPrice = 190,
		favoriteGenre = "Pop",
	},
	{
		seedId = "seed_sora",
		name = { en = "Sora Wave", ja = "そらウェーブ" },
		rarity = "Rare",
		price = 240,
		growSeconds = 1200,
		baseSellPrice = 350,
		favoriteGenre = "Dance",
	},
	{
		seedId = "seed_fuji",
		name = { en = "Fuji Storm", ja = "ふじストーム" },
		rarity = "Rare",
		price = 360,
		growSeconds = 1320,
		baseSellPrice = 540,
		favoriteGenre = "Rock",
	},
	{
		seedId = "seed_hanabi",
		name = { en = "Hanabi Burst", ja = "はなびバースト" },
		rarity = "Epic",
		price = 900,
		growSeconds = 1680,
		baseSellPrice = 1700,
		favoriteGenre = "Japan",
	},
	{
		seedId = "seed_ichigo",
		name = { en = "Ichigo Jam", ja = "いちごジャム" },
		rarity = "Common",
		price = 30,
		growSeconds = 540,
		baseSellPrice = 47,
		favoriteGenre = "Pop",
	},
	{
		seedId = "seed_budo",
		name = { en = "Budo Bass", ja = "ぶどうベース" },
		rarity = "Uncommon",
		price = 100,
		growSeconds = 780,
		baseSellPrice = 150,
		favoriteGenre = "Rock",
	},
	{
		seedId = "seed_kiwi",
		name = { en = "Kiwi Kick", ja = "キウイキック" },
		rarity = "Uncommon",
		price = 150,
		growSeconds = 900,
		baseSellPrice = 225,
		favoriteGenre = "Dance",
	},
	{
		seedId = "seed_sumire",
		name = { en = "Sumire Soul", ja = "すみれソウル" },
		rarity = "Rare",
		price = 300,
		growSeconds = 1260,
		baseSellPrice = 440,
		favoriteGenre = "Japan",
	},
	{
		seedId = "seed_taiyo",
		name = { en = "Taiyo Drive", ja = "たいようドライブ" },
		rarity = "Epic",
		price = 1200,
		growSeconds = 1800,
		baseSellPrice = 2300,
		favoriteGenre = "Rock",
	},
	{
		seedId = "seed_niji",
		name = { en = "Niji Anthem", ja = "にじアンセム" },
		rarity = "Legendary",
		price = 3000,
		growSeconds = 2400,
		baseSellPrice = 6000,
		favoriteGenre = "Pop",
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
