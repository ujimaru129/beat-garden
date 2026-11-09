--!strict
-- Long-term progress, shared by server and client and free of Roblox Instances so Lune can test it.
--
--   Garden level: XP from tending, harvesting and discovering new fruit. Levels open new seeds in the shop.
--   Mastery:      every harvest of a seed adds to that seed's mastery. Stars make it grow faster and mutate more.
--
-- Values are initial, tune from playtest data.

local Seeds = require(script.Parent.Seeds)

local Progression = {}

-- Garden level ------------------------------------------------------------------------------------

Progression.MaxLevel = 20

-- Total XP needed to be at `level` (level 1 = 0).
function Progression.xpToReach(level: number): number
	if level <= 1 then
		return 0
	end
	return math.round(60 * (level - 1) ^ 1.8)
end

export type LevelInfo = {
	level: number,
	into: number, -- XP gained inside this level
	need: number, -- XP this level takes (0 at the max level)
}

function Progression.levelFor(xp: number): LevelInfo
	local level = 1
	while level < Progression.MaxLevel and xp >= Progression.xpToReach(level + 1) do
		level += 1
	end
	if level >= Progression.MaxLevel then
		return { level = level, into = 0, need = 0 }
	end
	local base = Progression.xpToReach(level)
	return { level = level, into = xp - base, need = Progression.xpToReach(level + 1) - base }
end

-- Garden level at which each seed starts to appear in the shop. Seeds not listed are open from level 1.
local unlockLevel: { [string]: number } = {
	seed_sakura = 1,
	seed_yuzu = 1,
	seed_ramune = 2,
	seed_matcha = 3,
	seed_momo = 5,
	seed_sora = 7,
	seed_fuji = 10,
	seed_hanabi = 13,
	seed_ichigo = 2,
	seed_budo = 4,
	seed_kiwi = 6,
	seed_sumire = 8,
	seed_taiyo = 15,
	seed_niji = 18,
}
Progression.UnlockLevel = table.freeze(unlockLevel)

function Progression.unlockLevelOf(seedId: string): number
	return unlockLevel[seedId] or 1
end

-- Seeds that open exactly at `level`.
function Progression.seedsUnlockedAt(level: number): { string }
	local out: { string } = {}
	for _, seed in Seeds.List do
		if Progression.unlockLevelOf(seed.seedId) == level then
			table.insert(out, seed.seedId)
		end
	end
	return out
end

-- XP rewards -----------------------------------------------------------------------------------------

local HARVEST_XP: { [string]: number } = {
	Common = 10,
	Uncommon = 18,
	Rare = 35,
	Epic = 70,
	Legendary = 140,
}
local MUTATION_XP: { [string]: number } = { Film = 5, Vapor = 15, GoldenHour = 40 }

Progression.DiscoveryXp = 20

-- A finished tend: a little for taking part, more for accuracy (0..1).
function Progression.tendXp(accuracy: number): number
	return 2 + math.round(8 * math.clamp(accuracy, 0, 1))
end

function Progression.harvestXp(seedId: string, mutation: string?): number
	local seed = Seeds.get(seedId)
	local base = if seed then HARVEST_XP[seed.rarity] or 10 else 10
	return base + (if mutation then MUTATION_XP[mutation] or 0 else 0)
end

-- Mastery ----------------------------------------------------------------------------------------------

-- Harvests of one seed needed for each star.
local starThresholds = { 1, 3, 6, 10, 15 }
Progression.StarThresholds = table.freeze(starThresholds)
Progression.MaxStars = #starThresholds

function Progression.starsFor(harvests: number): number
	local stars = 0
	for _, needed in starThresholds do
		if harvests >= needed then
			stars += 1
		end
	end
	return stars
end

-- Harvests until the next star (nil at the max).
function Progression.nextStarAt(harvests: number): number?
	return starThresholds[Progression.starsFor(harvests) + 1]
end

Progression.GrowTimeCutPerStar = 0.04 -- 5 stars: plants of that seed grow in 80% of the time
Progression.MutationBoostPerStar = 0.06 -- 5 stars: +30% mutation chance

function Progression.growTimeMult(stars: number): number
	return 1 - Progression.GrowTimeCutPerStar * math.clamp(stars, 0, Progression.MaxStars)
end

function Progression.mutationMult(stars: number): number
	return 1 + Progression.MutationBoostPerStar * math.clamp(stars, 0, Progression.MaxStars)
end

-- Applying a harvest ----------------------------------------------------------------------------------

export type Progress = {
	xp: number,
	mastery: { [string]: number }, -- seedId -> harvests
}

export type HarvestResult = {
	xpGained: number,
	level: number,
	leveledUp: boolean,
	unlocked: { string }, -- seeds that opened with the new level(s)
	stars: number,
	newStar: boolean,
	harvests: number, -- harvests of this seed so far
}

local function addXp(progress: Progress, amount: number): (boolean, { string }, number)
	local before = Progression.levelFor(progress.xp).level
	progress.xp += amount
	local after = Progression.levelFor(progress.xp).level
	local unlocked: { string } = {}
	for level = before + 1, after do
		for _, seedId in Progression.seedsUnlockedAt(level) do
			table.insert(unlocked, seedId)
		end
	end
	return after > before, unlocked, after
end

-- XP for a finished tend. Returns whether the level went up, the seeds it opened, and the new level.
function Progression.applyTend(progress: Progress, accuracy: number): (boolean, { string }, number)
	return addXp(progress, Progression.tendXp(accuracy))
end

function Progression.applyHarvest(
	progress: Progress,
	seedId: string,
	mutation: string?,
	newDiscovery: boolean
): HarvestResult
	local xp = Progression.harvestXp(seedId, mutation) + (if newDiscovery then Progression.DiscoveryXp else 0)
	local before = progress.mastery[seedId] or 0
	local after = before + 1
	progress.mastery[seedId] = after
	local leveledUp, unlocked, level = addXp(progress, xp)
	local stars = Progression.starsFor(after)
	return {
		xpGained = xp,
		level = level,
		leveledUp = leveledUp,
		unlocked = unlocked,
		stars = stars,
		newStar = stars > Progression.starsFor(before),
		harvests = after,
	}
end

return table.freeze(Progression)
