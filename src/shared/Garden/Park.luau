--!strict
-- Beat Park: the player's amusement park, which grows with the garden. Every territory has a few lots (some on the
-- ground behind the plots, some in the sky above). Goals (harvests, plays, combos, the book ...) give Gift Boxes;
-- a box holds an attraction in one of a few colour palettes, unknown until it is opened. The player chooses which
-- one stands on which lot, so every park looks different and the others can see it.
-- Never sold for Robux: boxes come only from goals. Initial values; tune from playtest data.
--
-- This module is pure: the data is passed in (and the random source), so the tests can run it.

local Park = {}

export type Kind = "ground" | "sky"

export type Attraction = {
	id: string,
	name: { en: string, ja: string },
	kind: Kind,
	weight: number, -- how often a box holds it (relative)
}

export type Lot = {
	id: string,
	kind: Kind,
	level: number, -- garden level that opens the lot
}

export type Goal = {
	id: string,
	stat: string, -- one of the keys of `Stats`
	target: number,
	name: string, -- English text (translated on the client)
}

-- What the goals measure (the caller works these out from the player's data).
export type Stats = {
	harvests: number,
	runs: number, -- rhythm runs finished
	maxCombo: number,
	book: number, -- book entries found
	spirits: number, -- spirits owned
	level: number, -- garden level
	pats: number, -- times a spirit was petted
	bond: number, -- the highest bond level of any spirit (0 = none)
}

export type State = {
	items: { [string]: boolean }, -- "attractionId|palette" -> owned
	boxes: number, -- gift boxes not opened yet
	claimed: { [string]: boolean }, -- goals already paid
	placed: { [string]: string }, -- lot id -> item key
}

Park.Palettes = table.freeze({ "Sakura", "Sora", "Yuzu", "Matcha", "Rainbow" })
-- The first four are common; Rainbow (colours that shift) is rare.
Park.PaletteWeights =
	table.freeze({ Sakura = 24, Sora = 24, Yuzu = 24, Matcha = 24, Rainbow = 4 } :: { [string]: number })
Park.MaxBoxes = 99

local attractions: { Attraction } = {
	{ id = "fountain", name = { en = "Fountain", ja = "噴水" }, kind = "ground", weight = 10 },
	{ id = "carousel", name = { en = "Carousel", ja = "メリーゴーラウンド" }, kind = "ground", weight = 10 },
	{ id = "teacups", name = { en = "Tea Cups", ja = "コーヒーカップ" }, kind = "ground", weight = 10 },
	{ id = "ferris", name = { en = "Ferris Wheel", ja = "観覧車" }, kind = "ground", weight = 7 },
	{ id = "stage", name = { en = "Beat Stage", ja = "ビートステージ" }, kind = "ground", weight = 7 },
	{ id = "fireworks", name = { en = "Fireworks Tower", ja = "花火台" }, kind = "ground", weight = 7 },
	{ id = "swing", name = { en = "Sky Swing", ja = "空中ブランコ" }, kind = "sky", weight = 10 },
	{
		id = "coaster",
		name = { en = "Sky Coaster", ja = "空中ジェットコースター" },
		kind = "sky",
		weight = 7,
	},
	{ id = "balloons", name = { en = "Balloon Bunch", ja = "風船の束" }, kind = "sky", weight = 10 },
	{ id = "lanterns", name = { en = "Lantern Garland", ja = "提灯のつなぎ" }, kind = "sky", weight = 10 },
}
Park.Attractions = table.freeze(attractions)

local byId: { [string]: Attraction } = {}
for _, a in attractions do
	byId[a.id] = a
end

function Park.attraction(id: string): Attraction?
	return byId[id]
end

-- Three ground lots and three sky lots, opened by the garden level.
Park.Lots = table.freeze({
	{ id = "G1", kind = "ground", level = 3 },
	{ id = "S1", kind = "sky", level = 6 },
	{ id = "G2", kind = "ground", level = 8 },
	{ id = "S2", kind = "sky", level = 11 },
	{ id = "G3", kind = "ground", level = 14 },
	{ id = "S3", kind = "sky", level = 17 },
} :: { Lot })

local lotById: { [string]: Lot } = {}
for _, lot in Park.Lots do
	lotById[lot.id] = lot
end

function Park.lot(id: string): Lot?
	return lotById[id]
end

function Park.lotOpen(lotId: string, level: number): boolean
	local lot = lotById[lotId]
	return lot ~= nil and level >= lot.level
end

-- Each goal pays one box, once.
local goals: { Goal } = {
	{ id = "harvest_1", stat = "harvests", target = 1, name = "Harvest your first fruit" },
	{ id = "harvest_5", stat = "harvests", target = 5, name = "Harvest 5 fruits" },
	{ id = "harvest_20", stat = "harvests", target = 20, name = "Harvest 20 fruits" },
	{ id = "harvest_50", stat = "harvests", target = 50, name = "Harvest 50 fruits" },
	{ id = "harvest_100", stat = "harvests", target = 100, name = "Harvest 100 fruits" },
	{ id = "harvest_200", stat = "harvests", target = 200, name = "Harvest 200 fruits" },
	{ id = "runs_3", stat = "runs", target = 3, name = "Play the rhythm 3 times" },
	{ id = "runs_10", stat = "runs", target = 10, name = "Play the rhythm 10 times" },
	{ id = "runs_25", stat = "runs", target = 25, name = "Play the rhythm 25 times" },
	{ id = "runs_50", stat = "runs", target = 50, name = "Play the rhythm 50 times" },
	{ id = "combo_30", stat = "maxCombo", target = 30, name = "Reach a 30 combo" },
	{ id = "combo_60", stat = "maxCombo", target = 60, name = "Reach a 60 combo" },
	{ id = "combo_100", stat = "maxCombo", target = 100, name = "Reach a 100 combo" },
	{ id = "book_5", stat = "book", target = 5, name = "Find 5 book entries" },
	{ id = "book_15", stat = "book", target = 15, name = "Find 15 book entries" },
	{ id = "book_30", stat = "book", target = 30, name = "Find 30 book entries" },
	{ id = "spirits_1", stat = "spirits", target = 1, name = "Hatch your first spirit" },
	{ id = "spirits_3", stat = "spirits", target = 3, name = "Have 3 spirits" },
	{ id = "spirits_5", stat = "spirits", target = 5, name = "Have 5 spirits" },
	{ id = "pats_10", stat = "pats", target = 10, name = "Pet your spirits 10 times" },
	{ id = "pats_50", stat = "pats", target = 50, name = "Pet your spirits 50 times" },
	{ id = "pats_200", stat = "pats", target = 200, name = "Pet your spirits 200 times" },
	{ id = "bond_3", stat = "bond", target = 3, name = "Become close friends with a spirit" },
	{ id = "bond_5", stat = "bond", target = 5, name = "Become best friends with a spirit" },
	{ id = "level_5", stat = "level", target = 5, name = "Reach garden level 5" },
	{ id = "level_10", stat = "level", target = 10, name = "Reach garden level 10" },
	{ id = "level_15", stat = "level", target = 15, name = "Reach garden level 15" },
	{ id = "level_20", stat = "level", target = 20, name = "Reach garden level 20" },
}
Park.Goals = table.freeze(goals)

local goalIds: { [string]: boolean } = {}
for _, g in goals do
	goalIds[g.id] = true
end

function Park.isGoal(id: string): boolean
	return goalIds[id] == true
end

function Park.progressOf(goal: Goal, stats: Stats): number
	return (stats :: any)[goal.stat] or 0
end

-- Item keys: "attractionId|palette".
function Park.keyOf(attractionId: string, palette: string): string
	return `{attractionId}|{palette}`
end

function Park.parseKey(key: unknown): (Attraction?, string?)
	if type(key) ~= "string" then
		return nil, nil
	end
	local id, palette = string.match(key, "^([%w_]+)|(%w+)$")
	if not id or not palette or Park.PaletteWeights[palette] == nil then
		return nil, nil
	end
	local attraction = byId[id]
	if not attraction then
		return nil, nil
	end
	return attraction, palette
end

function Park.newState(): State
	return { items = {}, boxes = 0, claimed = {}, placed = {} }
end

-- Pays the box of every goal that is reached and not yet paid. Returns how many boxes were added.
function Park.claimGoals(state: State, stats: Stats): number
	local added = 0
	for _, goal in goals do
		if not state.claimed[goal.id] and Park.progressOf(goal, stats) >= goal.target then
			state.claimed[goal.id] = true
			if state.boxes < Park.MaxBoxes then
				state.boxes += 1
				added += 1
			end
		end
	end
	return added
end

-- The number of items that can still be found.
function Park.itemCount(): number
	return #attractions * #Park.Palettes
end

local function ownedCount(state: State): number
	local n = 0
	for _ in state.items do
		n += 1
	end
	return n
end

-- Opens one box: a random attraction in a random palette that the player does not own yet. Returns the item key,
-- or nil when there is no box or everything is owned.
function Park.openBox(state: State, rng: Random): string?
	if state.boxes <= 0 or ownedCount(state) >= Park.itemCount() then
		return nil
	end
	local candidates: { { key: string, weight: number } } = {}
	local total = 0
	for _, a in attractions do
		for _, palette in Park.Palettes do
			local key = Park.keyOf(a.id, palette)
			if not state.items[key] then
				local weight = a.weight * Park.PaletteWeights[palette]
				total += weight
				table.insert(candidates, { key = key, weight = weight })
			end
		end
	end
	local roll = rng:NextNumber() * total
	local chosen = candidates[#candidates].key
	for _, c in candidates do
		roll -= c.weight
		if roll <= 0 then
			chosen = c.key
			break
		end
	end
	state.boxes -= 1
	state.items[chosen] = true
	return chosen
end

-- Puts the item on the lot (nil clears the lot). One item stands in one place: moving it empties its old lot.
-- Returns ok, reason.
function Park.place(state: State, lotId: unknown, key: unknown, level: number): (boolean, string?)
	if type(lotId) ~= "string" then
		return false, "bad request"
	end
	local lot = lotById[lotId]
	if not lot then
		return false, "unknown lot"
	end
	if level < lot.level then
		return false, "that lot is not open yet"
	end
	if key == nil then
		state.placed[lotId] = nil
		return true, nil
	end
	local attraction = Park.parseKey(key)
	if not attraction or not state.items[key :: string] then
		return false, "you do not have that"
	end
	if attraction.kind ~= lot.kind then
		return false, "that does not fit this lot"
	end
	for otherId, otherKey in state.placed do
		if otherKey == key then
			state.placed[otherId] = nil
		end
	end
	state.placed[lotId] = key :: string
	return true, nil
end

-- A clean State from whatever was loaded.
function Park.sanitize(raw: any): State
	local state = Park.newState()
	if type(raw) ~= "table" then
		return state
	end
	if type(raw.boxes) == "number" and raw.boxes == raw.boxes then
		state.boxes = math.clamp(math.floor(raw.boxes), 0, Park.MaxBoxes)
	end
	if type(raw.items) == "table" then
		for key, owned in raw.items do
			if owned == true and Park.parseKey(key) then
				state.items[key] = true
			end
		end
	end
	if type(raw.claimed) == "table" then
		for id, paid in raw.claimed do
			if paid == true and type(id) == "string" and goalIds[id] then
				state.claimed[id] = true
			end
		end
	end
	if type(raw.placed) == "table" then
		local used: { [string]: boolean } = {}
		for lotId, key in raw.placed do
			local lot = type(lotId) == "string" and lotById[lotId] or nil
			local attraction = Park.parseKey(key)
			if lot and attraction and attraction.kind == lot.kind and state.items[key] and not used[key] then
				used[key] = true
				state.placed[lotId] = key
			end
		end
	end
	return state
end

return Park
