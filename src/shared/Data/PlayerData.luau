--!strict
-- The player's saved data (one DataStore key per player) and the sanitiser that guards it.
-- `sanitize` rebuilds a clean table from whatever was loaded, so missing or damaged fields never
-- reach the game code. Bump `v` and add a step in `sanitize` when the shape changes.

local Growth = require(script.Parent.Parent.Garden.Growth)
local Seeds = require(script.Parent.Parent.Garden.Seeds)
local Tutorial = require(script.Parent.Parent.Garden.Tutorial)

export type Fruit = {
	seedId: string,
	mutation: string?,
	weight: number,
}

export type Data = {
	v: number,
	coins: number,
	plots: { [string]: Growth.Plot }, -- keyed "1", "2", ... (one plot for now)
	seeds: { [string]: number }, -- seedId -> count
	fruits: { Fruit },
	settings: { latencyMs: number },
	stats: { tends: number, perfects: number, harvests: number },
	tutorialStep: number, -- 1..5 = in the tutorial, Tutorial.Done = finished or skipped
}

local PlayerData = {}

PlayerData.Version = 1
PlayerData.MaxFruits = 500
PlayerData.LatencyRange = table.freeze({ min = -100, max = 300 }) -- same as Calibration.ClampMs

local function num(v: any, default: number, lo: number?, hi: number?): number
	if type(v) ~= "number" or v ~= v then
		return default
	end
	return math.clamp(v, lo or -math.huge, hi or math.huge)
end

function PlayerData.new(): Data
	return {
		v = PlayerData.Version,
		coins = 0,
		plots = {},
		seeds = { [Seeds.StarterSeedId] = 1 },
		fruits = {},
		settings = { latencyMs = 0 },
		stats = { tends = 0, perfects = 0, harvests = 0 },
		tutorialStep = 1,
	}
end

local function sanitizePlot(raw: any): Growth.Plot?
	if type(raw) ~= "table" or type(raw.seedId) ~= "string" or Seeds.get(raw.seedId) == nil then
		return nil
	end
	return {
		seedId = raw.seedId,
		plantedAt = num(raw.plantedAt, 0, 0),
		careGauge = num(raw.careGauge, 0, 0),
		lastTendAt = num(raw.lastTendAt, 0, 0),
		bestPerfectStreak = num(raw.bestPerfectStreak, 0, 0),
		mutationMult = num(raw.mutationMult, 1, 1),
	}
end

-- Accepts nil / anything. Always returns a valid Data.
function PlayerData.sanitize(raw: any): Data
	local data = PlayerData.new()
	if type(raw) ~= "table" then
		return data
	end

	data.coins = math.floor(num(raw.coins, 0, 0))

	if type(raw.plots) == "table" then
		data.plots = {}
		for key, plot in raw.plots do
			local clean = sanitizePlot(plot)
			if clean and type(key) == "string" then
				data.plots[key] = clean
			end
		end
	end

	if type(raw.seeds) == "table" then
		data.seeds = {}
		for seedId, count in raw.seeds do
			if type(seedId) == "string" and Seeds.get(seedId) then
				local n = math.floor(num(count, 0, 0))
				if n > 0 then
					data.seeds[seedId] = n
				end
			end
		end
	end

	if type(raw.fruits) == "table" then
		data.fruits = {}
		for _, fruit in raw.fruits do
			if #data.fruits >= PlayerData.MaxFruits then
				break
			end
			if type(fruit) == "table" and type(fruit.seedId) == "string" and Seeds.get(fruit.seedId) then
				table.insert(data.fruits, {
					seedId = fruit.seedId,
					mutation = if type(fruit.mutation) == "string" then fruit.mutation else nil,
					weight = num(fruit.weight, 1, 0.1, 10),
				})
			end
		end
	end

	if type(raw.settings) == "table" then
		data.settings.latencyMs =
			math.round(num(raw.settings.latencyMs, 0, PlayerData.LatencyRange.min, PlayerData.LatencyRange.max))
	end

	if type(raw.stats) == "table" then
		data.stats.tends = math.floor(num(raw.stats.tends, 0, 0))
		data.stats.perfects = math.floor(num(raw.stats.perfects, 0, 0))
		data.stats.harvests = math.floor(num(raw.stats.harvests, 0, 0))
	end

	-- Data saved before the tutorial existed: anyone who already has progress skips it.
	local hasProgress = next(data.plots) ~= nil or data.coins > 0 or data.stats.harvests > 0
	if type(raw.tutorialStep) == "number" then
		data.tutorialStep = math.floor(num(raw.tutorialStep, 1, 1, Tutorial.Done))
	elseif hasProgress then
		data.tutorialStep = Tutorial.Done
	end

	return data
end

return table.freeze(PlayerData)
