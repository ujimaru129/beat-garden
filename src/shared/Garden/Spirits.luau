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

-- Growth. The equipped spirit earns growth points (xp) from every tend. Levels make it bigger; at some levels it
-- also grows a random trait: a look (glow, sparkles, ribbon, wings, rainbow, bigger) or a ride (cloud, balloon, skate).
-- Which traits a spirit gets is luck, so two spirits of the same kind turn out different. Growth is for show: it does
-- not change what a spirit does for the garden.
Spirits.LevelSteps = table.freeze({ 0, 10, 30, 60, 100, 160, 240, 350, 500, 700 }) -- xp needed for level 1..10
Spirits.MaxLevel = #Spirits.LevelSteps
Spirits.MaxXp = 1000000
Spirits.TraitLevels = table.freeze({ 3, 6, 10 }) -- reaching one of these levels rolls a new trait

export type TraitKind = "Look" | "Ride"
export type Trait = {
	id: string, -- stored and sent in attributes: letters and digits only
	name: { en: string, ja: string },
	kind: TraitKind,
	weight: number,
}

local traitList: { Trait } = {
	{ id = "Glow", name = { en = "Glow", ja = "ひかる" }, kind = "Look", weight = 30 },
	{ id = "Sparkle", name = { en = "Sparkle", ja = "きらきら" }, kind = "Look", weight = 24 },
	{ id = "Big", name = { en = "Big", ja = "おおきい" }, kind = "Look", weight = 24 },
	{ id = "Ribbon", name = { en = "Ribbon", ja = "リボン" }, kind = "Look", weight = 18 },
	{ id = "Wings", name = { en = "Wings", ja = "はね" }, kind = "Look", weight = 14 },
	{ id = "Rainbow", name = { en = "Rainbow", ja = "にじいろ" }, kind = "Look", weight = 5 },
	{ id = "Cloud", name = { en = "Cloud Ride", ja = "くものりもの" }, kind = "Ride", weight = 9 },
	{ id = "Balloon", name = { en = "Balloon Ride", ja = "ふうせん" }, kind = "Ride", weight = 8 },
	{ id = "Skate", name = { en = "Skateboard", ja = "スケボー" }, kind = "Ride", weight = 8 },
}
Spirits.Traits = table.freeze(traitList)

local traitById: { [string]: Trait } = {}
for _, trait in traitList do
	traitById[trait.id] = trait
end

function Spirits.trait(id: string): Trait?
	return traitById[id]
end

-- 1..MaxLevel for an xp value.
function Spirits.levelOf(xp: number): number
	local level = 1
	for i, need in Spirits.LevelSteps do
		if xp >= need then
			level = i
		end
	end
	return level
end

local DIFFICULTY_XP = { Easy = 1, Normal = 1.2, Hard = 1.5, Expert = 1.8 } :: { [string]: number }

-- The xp a tend gives: more for a better run and for a harder chart (about 2 to 9).
function Spirits.xpForTend(accuracy: number, difficulty: string): number
	return math.max(1, math.round((2 + 4 * math.clamp(accuracy, 0, 1)) * (DIFFICULTY_XP[difficulty] or 1)))
end

-- The size of a spirit as a factor of the normal one.
function Spirits.sizeFactor(level: number, traits: { string }): number
	local size = 1 + 0.045 * (math.clamp(level, 1, Spirits.MaxLevel) - 1)
	if table.find(traits, "Big") then
		size += 0.18
	end
	return size
end

-- Picks a trait the spirit does not have yet (one ride at most), by weight. nil when nothing is left to give.
-- `random` returns a number in [0, 1).
function Spirits.rollTrait(owned: { string }, random: () -> number): string?
	local hasRide = false
	for _, id in owned do
		local trait = traitById[id]
		if trait and trait.kind == "Ride" then
			hasRide = true
		end
	end
	local pool: { Trait } = {}
	local total = 0
	for _, trait in traitList do
		if not table.find(owned, trait.id) and not (hasRide and trait.kind == "Ride") then
			table.insert(pool, trait)
			total += trait.weight
		end
	end
	if total <= 0 then
		return nil
	end
	local roll = random() * total
	for _, trait in pool do
		roll -= trait.weight
		if roll < 0 then
			return trait.id
		end
	end
	return pool[#pool].id
end

-- Adds xp to a spirit (anything with xp and traits). Returns the new level, whether it went up and the traits it
-- grew on the way (a big gain can pass several trait levels).
function Spirits.addXp(
	spirit: { xp: number, traits: { string } },
	gained: number,
	random: () -> number
): (number, boolean, { string })
	local before = Spirits.levelOf(spirit.xp)
	spirit.xp = math.min(Spirits.MaxXp, spirit.xp + math.max(0, gained))
	local after = Spirits.levelOf(spirit.xp)
	local grown: { string } = {}
	for _, at in Spirits.TraitLevels do
		if before < at and after >= at then
			local id = Spirits.rollTrait(spirit.traits, random)
			if id then
				table.insert(spirit.traits, id)
				table.insert(grown, id)
			end
		end
	end
	return after, after > before, grown
end

-- A spirit as one text entry for the player attributes the clients draw from:
-- "id:kind:bond:nick:level:Trait+Trait" (older values stop after the nick).
function Spirits.encode(
	spirit: { id: string, kind: string, bond: number, nick: number?, xp: number?, traits: { string }? }
): string
	return `{spirit.id}:{spirit.kind}:{spirit.bond}:{spirit.nick or 0}:{Spirits.levelOf(spirit.xp or 0)}:{table.concat(
		spirit.traits or {},
		"+"
	)}`
end

export type Entry = { id: string, kind: string, bond: number, nick: number, level: number, traits: { string } }

function Spirits.decode(text: string): Entry?
	local id, kind, bond, nick, level, traitText = string.match(text, "^([^:]+):([^:]+):(%d+):(%d*):(%d*):([%w+]*)$")
	if not id then
		id, kind, bond, nick = string.match(text, "^([^:]+):([^:]+):(%d+):?(%d*)$")
		level, traitText = "1", ""
	end
	if not id or not kind or not Spirits.get(kind) then
		return nil
	end
	local traits: { string } = {}
	for name in string.gmatch(traitText or "", "[^+]+") do
		if traitById[name] and not table.find(traits, name) then
			table.insert(traits, name)
		end
	end
	return {
		id = id,
		kind = kind,
		bond = tonumber(bond) or 0,
		nick = tonumber(nick) or 0,
		level = math.clamp(tonumber(level) or 1, 1, Spirits.MaxLevel),
		traits = traits,
	}
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
