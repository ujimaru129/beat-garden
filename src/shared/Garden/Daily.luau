--!strict
-- Daily login bonus and daily missions: a reason to come back every day.
--   * The day changes at midnight Japan time (UTC+9). The first visit of a new day pays a login bonus (coins, more
--     on a longer streak; every 7th day also a Gift Box) and gives three new missions.
--   * A mission counts from where the player's stats were when the day began, and pays coins the moment it is done.
--     All three done pay a Gift Box on top.
-- Pure functions: the data is passed in, so the tests can run them. Initial values; tune from playtest data.

local Daily = {}

export type Mission = {
	id: string,
	stat: string, -- harvests | runs | perfects | pats
	target: number,
	name: string, -- English text (translated on the client)
	needsSpirit: boolean?, -- only given to a player who has a spirit
}

export type Stats = { harvests: number, runs: number, perfects: number, pats: number, level: number, spirits: number }

export type State = {
	day: number, -- the day number the missions belong to (0 = never)
	streak: number, -- days in a row
	base: { [string]: number }, -- the stats when the day began
	missions: { string }, -- mission ids of today
	claimed: { [string]: boolean }, -- paid missions
	bonus: boolean, -- the Gift Box for all three is paid
}

export type Update = {
	newDay: boolean,
	streak: number,
	coins: number, -- to add to the player's coins
	boxes: number, -- Gift Boxes to add
	loginCoins: number,
	loginBox: boolean,
	missionsDone: number, -- missions paid in this update
}

Daily.MissionsPerDay = 3
Daily.StreakBoxEvery = 7
Daily.BaseTimeOffset = 9 * 3600 -- Japan time

local pool: { Mission } = {
	{ id = "harvest_3", stat = "harvests", target = 3, name = "Harvest 3 fruits" },
	{ id = "harvest_6", stat = "harvests", target = 6, name = "Harvest 6 fruits" },
	{ id = "runs_2", stat = "runs", target = 2, name = "Play the rhythm 2 times" },
	{ id = "runs_4", stat = "runs", target = 4, name = "Play the rhythm 4 times" },
	{ id = "perfects_40", stat = "perfects", target = 40, name = "Get 40 Perfects" },
	{ id = "perfects_100", stat = "perfects", target = 100, name = "Get 100 Perfects" },
	{ id = "pats_10", stat = "pats", target = 10, name = "Pet your spirits 10 times", needsSpirit = true },
	{ id = "pats_25", stat = "pats", target = 25, name = "Pet your spirits 25 times", needsSpirit = true },
}
Daily.Pool = table.freeze(pool)

local byId: { [string]: Mission } = {}
for _, m in pool do
	byId[m.id] = m
end

function Daily.mission(id: string): Mission?
	return byId[id]
end

-- The day number for a unix time (changes at midnight Japan time).
function Daily.dayOf(now: number): number
	return math.floor((now + Daily.BaseTimeOffset) / 86400)
end

-- Seconds until the day changes.
function Daily.secondsLeft(now: number): number
	return 86400 - ((now + Daily.BaseTimeOffset) % 86400)
end

function Daily.loginCoins(streak: number, level: number): number
	local base = 100 + level * 30
	return math.floor(base * (0.85 + 0.15 * math.min(streak, 7)))
end

function Daily.missionCoins(level: number): number
	return 60 + level * 15
end

function Daily.newState(): State
	return { day = 0, streak = 0, base = {}, missions = {}, claimed = {}, bonus = false }
end

-- Three missions with three different stats, the same for everyone on a given day (a small seeded shuffle).
function Daily.pick(day: number, hasSpirit: boolean): { string }
	local seed = day * 2654435761 % 4294967296
	local function nextNumber(): number
		seed = (seed * 1103515245 + 12345) % 2147483648
		return seed
	end
	local candidates: { Mission } = {}
	for _, m in pool do
		if hasSpirit or not m.needsSpirit then
			table.insert(candidates, m)
		end
	end
	for i = #candidates, 2, -1 do
		local j = nextNumber() % i + 1
		candidates[i], candidates[j] = candidates[j], candidates[i]
	end
	local picked: { string } = {}
	local used: { [string]: boolean } = {}
	for _, m in candidates do
		if not used[m.stat] and #picked < Daily.MissionsPerDay then
			used[m.stat] = true
			table.insert(picked, m.id)
		end
	end
	return picked
end

function Daily.progressOf(state: State, mission: Mission, stats: Stats): number
	local now = (stats :: any)[mission.stat] or 0
	return math.max(0, now - (state.base[mission.stat] or 0))
end

local function snapshotBase(stats: Stats): { [string]: number }
	return { harvests = stats.harvests, runs = stats.runs, perfects = stats.perfects, pats = stats.pats }
end

-- Moves the state on to today and pays what is due. The caller adds `coins` and `boxes` to the player.
function Daily.update(state: State, stats: Stats, now: number): Update
	local update: Update = {
		newDay = false,
		streak = state.streak,
		coins = 0,
		boxes = 0,
		loginCoins = 0,
		loginBox = false,
		missionsDone = 0,
	}
	local today = Daily.dayOf(now)
	if state.day ~= today then
		update.newDay = true
		state.streak = if state.day == today - 1 then state.streak + 1 else 1
		state.day = today
		state.base = snapshotBase(stats)
		state.missions = Daily.pick(today, stats.spirits > 0)
		state.claimed = {}
		state.bonus = false
		update.loginCoins = Daily.loginCoins(state.streak, stats.level)
		update.loginBox = state.streak % Daily.StreakBoxEvery == 0
		update.coins += update.loginCoins
		if update.loginBox then
			update.boxes += 1
		end
	end
	update.streak = state.streak
	local done = 0
	for _, id in state.missions do
		local mission = byId[id]
		if mission then
			if not state.claimed[id] and Daily.progressOf(state, mission, stats) >= mission.target then
				state.claimed[id] = true
				update.coins += Daily.missionCoins(stats.level)
				update.missionsDone += 1
			end
			if state.claimed[id] then
				done += 1
			end
		end
	end
	if done >= #state.missions and #state.missions > 0 and not state.bonus then
		state.bonus = true
		update.boxes += 1
	end
	return update
end

-- A clean State from whatever was loaded.
function Daily.sanitize(raw: any): State
	local state = Daily.newState()
	if type(raw) ~= "table" then
		return state
	end
	if type(raw.day) == "number" and raw.day == raw.day then
		state.day = math.clamp(math.floor(raw.day), 0, 1e7)
	end
	if type(raw.streak) == "number" and raw.streak == raw.streak then
		state.streak = math.clamp(math.floor(raw.streak), 0, 100000)
	end
	if type(raw.base) == "table" then
		for _, stat in { "harvests", "runs", "perfects", "pats" } do
			local value = raw.base[stat]
			if type(value) == "number" and value == value then
				state.base[stat] = math.clamp(math.floor(value), 0, 1e9)
			end
		end
	end
	if type(raw.missions) == "table" then
		for _, id in raw.missions do
			if type(id) == "string" and byId[id] and #state.missions < Daily.MissionsPerDay then
				table.insert(state.missions, id)
			end
		end
	end
	if type(raw.claimed) == "table" then
		for id, paid in raw.claimed do
			if paid == true and type(id) == "string" and byId[id] then
				state.claimed[id] = true
			end
		end
	end
	state.bonus = raw.bonus == true
	return state
end

return Daily
