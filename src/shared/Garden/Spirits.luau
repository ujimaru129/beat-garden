--!strict
-- Beat Spirits (pets): hatched from eggs, one can be equipped. An equipped spirit tends the plant on
-- its own while the player is away from it (low accuracy: small points, on a timer) and may add a
-- passive effect. Ten kinds. Values are initial, tune from playtest data.

export type Kind = "Mochi" | "Kitsune" | "Pon" | "Koke" | "Ame" | "Haru" | "Poko" | "Mimi" | "Hoshi" | "Yoru"

export type Def = {
	kind: Kind,
	name: { en: string, ja: string },
	weight: number, -- hatch odds weight (shown to the player as a percentage)
	autoCareSeconds: number, -- how often it tends the plant
	autoCarePoints: number, -- growth seconds it adds each time
	mutationMult: number, -- multiplies the mutation chance at harvest
	sellMult: number, -- multiplies what the Market pays
	freshMult: number, -- multiplies how long a ripe fruit stays fresh
	tendMult: number, -- multiplies the growth of the player's own tends
	discoveryMult: number, -- multiplies the coins for a first-time book entry
	estimatedValue: number, -- coins, for the trade screen's "estimated value"
}

local Spirits = {}

local list: { Def } = {
	{
		kind = "Mochi",
		name = { en = "Mochi", ja = "もち" },
		weight = 24,
		autoCareSeconds = 45,
		autoCarePoints = 8,
		mutationMult = 1,
		sellMult = 1,
		freshMult = 1,
		tendMult = 1,
		discoveryMult = 1,
		estimatedValue = 120,
	},
	{
		kind = "Kitsune",
		name = { en = "Kitsune", ja = "きつね" },
		weight = 14,
		autoCareSeconds = 60,
		autoCarePoints = 6,
		mutationMult = 1.3,
		sellMult = 1,
		freshMult = 1,
		tendMult = 1,
		discoveryMult = 1,
		estimatedValue = 300,
	},
	{
		kind = "Pon",
		name = { en = "Pon", ja = "ぽん" },
		weight = 12,
		autoCareSeconds = 60,
		autoCarePoints = 6,
		mutationMult = 1,
		sellMult = 1.1,
		freshMult = 1,
		tendMult = 1,
		discoveryMult = 1,
		estimatedValue = 250,
	},
	{
		kind = "Koke",
		name = { en = "Koke", ja = "こけ" },
		weight = 12,
		autoCareSeconds = 60,
		autoCarePoints = 6,
		mutationMult = 1,
		sellMult = 1,
		freshMult = 2,
		tendMult = 1,
		discoveryMult = 1,
		estimatedValue = 250,
	},
	{
		kind = "Ame",
		name = { en = "Ame", ja = "あめ" },
		weight = 9,
		autoCareSeconds = 45,
		autoCarePoints = 14,
		mutationMult = 1,
		sellMult = 1,
		freshMult = 1,
		tendMult = 1,
		discoveryMult = 1,
		estimatedValue = 400,
	},
	{
		kind = "Haru",
		name = { en = "Haru", ja = "はる" },
		weight = 10,
		autoCareSeconds = 60,
		autoCarePoints = 6,
		mutationMult = 1,
		sellMult = 1,
		freshMult = 1,
		tendMult = 1.2,
		discoveryMult = 1,
		estimatedValue = 350,
	},
	{
		kind = "Poko",
		name = { en = "Poko", ja = "ぽこ" },
		weight = 8,
		autoCareSeconds = 60,
		autoCarePoints = 6,
		mutationMult = 1,
		sellMult = 1,
		freshMult = 1,
		tendMult = 1,
		discoveryMult = 2,
		estimatedValue = 450,
	},
	{
		kind = "Mimi",
		name = { en = "Mimi", ja = "みみ" },
		weight = 6,
		autoCareSeconds = 30,
		autoCarePoints = 5,
		mutationMult = 1,
		sellMult = 1,
		freshMult = 1,
		tendMult = 1,
		discoveryMult = 1,
		estimatedValue = 500,
	},
	{
		kind = "Hoshi",
		name = { en = "Hoshi", ja = "ほし" },
		weight = 3,
		autoCareSeconds = 45,
		autoCarePoints = 8,
		mutationMult = 1.15,
		sellMult = 1.05,
		freshMult = 1.5,
		tendMult = 1,
		discoveryMult = 1,
		estimatedValue = 900,
	},
	{
		kind = "Yoru",
		name = { en = "Yoru", ja = "よる" },
		weight = 2,
		autoCareSeconds = 60,
		autoCarePoints = 6,
		mutationMult = 1.5,
		sellMult = 1,
		freshMult = 1,
		tendMult = 1,
		discoveryMult = 1,
		estimatedValue = 1200,
	},
}
Spirits.List = table.freeze(list)

Spirits.EggPrice = 150 -- coins
Spirits.MaxOwned = 100

-- Pets: petting a spirit raises its bond. Five bond levels (hearts); the bond is only for show and for goals,
-- it does not change what the spirit does.
Spirits.BondSteps = table.freeze({ 0, 8, 25, 60, 120 }) -- bond points needed for level 1..5
Spirits.MaxBondLevel = #Spirits.BondSteps
Spirits.MaxBond = 100000
Spirits.PatCooldown = 1.2 -- seconds between pats of the same spirit that count
Spirits.MaxPets = 8 -- pets that roam a territory at once

-- Names a player can give a spirit (a fixed list: no free text, so nothing can be offensive). A spirit stores the
-- number of the name.
Spirits.Nicknames = table.freeze({
	{ en = "Momo", ja = "モモ" },
	{ en = "Kuro", ja = "クロ" },
	{ en = "Shiro", ja = "シロ" },
	{ en = "Pochi", ja = "ポチ" },
	{ en = "Mame", ja = "マメ" },
	{ en = "Hana", ja = "ハナ" },
	{ en = "Sora", ja = "ソラ" },
	{ en = "Riku", ja = "リク" },
	{ en = "Yuki", ja = "ユキ" },
	{ en = "Tama", ja = "タマ" },
	{ en = "Koro", ja = "コロ" },
	{ en = "Nana", ja = "ナナ" },
	{ en = "Lulu", ja = "ルル" },
	{ en = "Beat", ja = "ビート" },
	{ en = "Echo", ja = "エコー" },
	{ en = "Mint", ja = "ミント" },
	{ en = "Coco", ja = "ココ" },
	{ en = "Pico", ja = "ピコ" },
	{ en = "Dot", ja = "ドット" },
	{ en = "Bell", ja = "ベル" },
} :: { { en: string, ja: string } })

-- The name for a nickname number in "en" or "ja", or nil for none / not valid.
function Spirits.nickname(nick: any, lang: string): string?
	if type(nick) ~= "number" then
		return nil
	end
	local entry = Spirits.Nicknames[nick]
	if not entry then
		return nil
	end
	return if lang == "ja" then entry.ja else entry.en
end

-- 1..MaxBondLevel for a bond value.
function Spirits.bondLevel(bond: number): number
	local level = 1
	for i, need in Spirits.BondSteps do
		if bond >= need then
			level = i
		end
	end
	return level
end

local byKind: { [string]: Def } = {}
for _, def in list do
	byKind[def.kind] = def
end

function Spirits.get(kind: string): Def?
	return byKind[kind]
end

-- `random` returns a number in [0, 1).
function Spirits.hatch(random: () -> number): Kind
	local total = 0
	for _, def in list do
		total += def.weight
	end
	local roll = random() * total
	for _, def in list do
		roll -= def.weight
		if roll < 0 then
			return def.kind
		end
	end
	return list[#list].kind
end

-- Hatch odds in percent, for the egg's description (paid random items must show their odds).
function Spirits.odds(): { { kind: Kind, percent: number } }
	local total = 0
	for _, def in list do
		total += def.weight
	end
	local out = {}
	for _, def in list do
		table.insert(out, { kind = def.kind, percent = math.round(def.weight / total * 1000) / 10 })
	end
	return out
end

return table.freeze(Spirits)
