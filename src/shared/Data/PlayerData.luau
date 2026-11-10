--!strict
-- The player's saved data (one DataStore key per player) and the sanitiser that guards it.
-- `sanitize` rebuilds a clean table from whatever was loaded, so missing or damaged fields never
-- reach the game code. Bump `v` and add a step in `sanitize` when the shape changes.

local Collection = require(script.Parent.Parent.Garden.Collection)
local Growth = require(script.Parent.Parent.Garden.Growth)
local Mutations = require(script.Parent.Parent.Garden.Mutations)
local Park = require(script.Parent.Parent.Garden.Park)
local Plots = require(script.Parent.Parent.Garden.Plots)
local Products = require(script.Parent.Parent.Garden.Products)
local Seeds = require(script.Parent.Parent.Garden.Seeds)
local Spirits = require(script.Parent.Parent.Garden.Spirits)
local Tips = require(script.Parent.Parent.Garden.Tips)
local Tutorial = require(script.Parent.Parent.Garden.Tutorial)

export type Fruit = {
	seedId: string,
	mutation: string?,
	weight: number,
}

export type SpiritInstance = {
	id: string, -- unique per spirit
	kind: string, -- Spirits kind
}

export type Data = {
	v: number,
	coins: number,
	plotCount: number, -- how many coin plots the player has bought (1..Plots.CoinMax)
	plots: { [string]: Growth.Plot }, -- keyed "1", "2", ... (the plants growing in them)
	seeds: { [string]: number }, -- seedId -> count
	fruits: { Fruit },
	eggs: number,
	spirits: { SpiritInstance },
	equippedSpirit: string?, -- id of the equipped spirit
	settings: { latencyMs: number },
	stats: { tends: number, perfects: number, harvests: number, maxCombo: number },
	park: Park.State, -- the amusement park (Garden/Park): goals paid, boxes, items, what stands where
	collection: Collection.Book, -- discovered seed x variant entries (Garden/Collection)
	xp: number, -- garden XP (Garden/Progression)
	mastery: { [string]: number }, -- seedId -> harvests of that seed
	tips: { [string]: boolean }, -- one-time tips already shown (Garden/Tips)
	receipts: { string }, -- recent Robux purchase ids already granted (never grant one twice)
	instantCredits: number, -- paid Instant Grows not used yet
	sprinklerUntil: number, -- unix seconds: the Growth Sprinkler works until then
	restockSlot: number, -- shop slot the personal restock below belongs to
	restockShift: number, -- personal restock (Garden/Shop `shift`); only valid inside restockSlot
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
		plotCount = 1,
		plots = {},
		seeds = { [Seeds.StarterSeedId] = 1 },
		fruits = {},
		eggs = 0,
		spirits = {},
		equippedSpirit = nil,
		settings = { latencyMs = 0 },
		stats = { tends = 0, perfects = 0, harvests = 0, maxCombo = 0 },
		park = Park.newState(),
		collection = {},
		xp = 0,
		mastery = {},
		tips = {},
		receipts = {},
		instantCredits = 0,
		sprinklerUntil = 0,
		restockSlot = 0,
		restockShift = 0,
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
		rolled = raw.rolled == true,
		mutation = if raw.rolled == true
				and type(raw.mutation) == "string"
				and Mutations.isMutation(raw.mutation)
			then raw.mutation
			else nil,
		growMult = if raw.growMult ~= nil then num(raw.growMult, 1, 0.5, 1) else nil,
	}
end

-- Accepts nil / anything. Always returns a valid Data.
function PlayerData.sanitize(raw: any): Data
	local data = PlayerData.new()
	if type(raw) ~= "table" then
		return data
	end

	data.coins = math.floor(num(raw.coins, 0, 0))

	data.plotCount = math.floor(num(raw.plotCount, 1, 1, Plots.CoinMax))
	if type(raw.plots) == "table" then
		data.plots = {}
		for key, plot in raw.plots do
			local index = Plots.indexOf(key)
			local clean = sanitizePlot(plot)
			if clean and index then
				data.plots[key] = clean
				if not Plots.isPass(index) then
					data.plotCount = math.max(data.plotCount, index) -- a plant in a plot means the plot is owned
				end
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

	data.eggs = math.floor(num(raw.eggs, 0, 0, 999))

	if type(raw.spirits) == "table" then
		data.spirits = {}
		local seen: { [string]: boolean } = {}
		for _, spirit in raw.spirits do
			if
				#data.spirits < Spirits.MaxOwned
				and type(spirit) == "table"
				and type(spirit.id) == "string"
				and not seen[spirit.id]
				and type(spirit.kind) == "string"
				and Spirits.get(spirit.kind)
			then
				seen[spirit.id] = true
				table.insert(data.spirits, { id = spirit.id, kind = spirit.kind })
			end
		end
		if type(raw.equippedSpirit) == "string" and seen[raw.equippedSpirit] then
			data.equippedSpirit = raw.equippedSpirit
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
		data.stats.maxCombo = math.floor(num(raw.stats.maxCombo, 0, 0, 100000))
	end

	if type(raw.collection) == "table" then
		for key, value in raw.collection do
			if type(key) == "string" and value == true and Collection.isValidKey(key) then
				data.collection[key] = true
			end
		end
	end

	data.xp = math.floor(num(raw.xp, 0, 0, 1e9))
	if type(raw.mastery) == "table" then
		for seedId, harvests in raw.mastery do
			if type(seedId) == "string" and Seeds.get(seedId) then
				local n = math.floor(num(harvests, 0, 0, 1e6))
				if n > 0 then
					data.mastery[seedId] = n
				end
			end
		end
	end

	if type(raw.tips) == "table" then
		for key, seen in raw.tips do
			if seen == true and Tips.isKey(key) then
				data.tips[key] = true
			end
		end
	end
	if type(raw.receipts) == "table" then
		for _, id in raw.receipts do
			if type(id) == "string" and #id <= 64 and #data.receipts < Products.MaxReceipts then
				table.insert(data.receipts, id)
			end
		end
	end
	data.instantCredits = math.floor(num(raw.instantCredits, 0, 0, 999))
	data.sprinklerUntil = num(raw.sprinklerUntil, 0, 0)
	data.restockSlot = math.floor(num(raw.restockSlot, 0, 0))
	data.restockShift = math.floor(num(raw.restockShift, 0, 0, 1e6))

	data.park = Park.sanitize(raw.park)

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
