--!strict
-- Global rankings, kept in OrderedDataStores (one per board). The garden server calls `submit` with each player's
-- numbers (rarely: a value is written only when it changed, and at most once a minute), and a background loop
-- reads the top of every board every couple of minutes into a cache that the clients are served from, so a
-- screen full of players never costs a DataStore request each.
--
-- Everything here is wrapped in pcall: unpublished places and Studio without API access simply have no ranking.

local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Leaderboard = require(ReplicatedStorage.Shared.Garden.Leaderboard)

local Leaderboards = {}

local REFRESH_SECONDS = 120
local MIN_SUBMIT_SECONDS = 60

export type Entry = { userId: number, name: string, value: number }

local stores: { [string]: OrderedDataStore } = {}
local cache: { [string]: { Entry } } = {}
local names: { [number]: string } = {}
local lastSent: { [string]: { value: number, at: number } } = {}

for _, board in Leaderboard.Boards do
	cache[board] = {}
	local ok, store = pcall(function()
		return DataStoreService:GetOrderedDataStore(`Leaderboard_{board}_v1`)
	end)
	if ok then
		stores[board] = store
	end
end

local function nameOf(userId: number): string
	local known = names[userId]
	if known then
		return known
	end
	local ok, name = pcall(function()
		return Players:GetNameFromUserIdAsync(userId)
	end)
	local result = if ok and type(name) == "string" then name else `Player {userId}`
	names[userId] = result
	return result
end

-- Writes the player's value for `board`, if it changed and a minute has passed since the last write.
function Leaderboards.submit(userId: number, board: string, value: number)
	local store = stores[board]
	if not store or value <= 0 then
		return
	end
	local key = `{board}:{userId}`
	local last = lastSent[key]
	local now = os.clock()
	if last and (last.value == value or now - last.at < MIN_SUBMIT_SECONDS) then
		return
	end
	lastSent[key] = { value = value, at = now }
	task.spawn(function()
		local ok, err = pcall(function()
			store:SetAsync(tostring(userId), value)
		end)
		if not ok then
			lastSent[key] = nil -- try again next time
			warn(`[Leaderboards] could not save {board} for {userId}: {err}`)
		end
	end)
end

local function refreshBoard(board: string)
	local store = stores[board]
	if not store then
		return
	end
	local ok, pages = pcall(function()
		return store:GetSortedAsync(false, Leaderboard.TopCount)
	end)
	if not ok then
		return
	end
	local okPage, page = pcall(function()
		return pages:GetCurrentPage()
	end)
	if not okPage then
		return
	end
	local entries: { Entry } = {}
	for _, item in page do
		local userId = tonumber(item.key)
		if userId and type(item.value) == "number" then
			table.insert(entries, { userId = userId, name = nameOf(userId), value = item.value })
		end
	end
	cache[board] = entries
end

-- The cached top of every board (what is sent to the clients).
function Leaderboards.snapshot(): { [string]: { Entry } }
	return cache
end

function Leaderboards.start()
	task.spawn(function()
		while true do
			for _, board in Leaderboard.Boards do
				refreshBoard(board)
			end
			task.wait(REFRESH_SECONDS)
		end
	end)
end

return Leaderboards
