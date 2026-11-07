--!strict
-- Saves and loads PlayerData in a DataStore, one key per player, with a simple session lock so the
-- same player cannot be edited by two servers at once (the pattern ProfileStore uses, kept small).
--
-- The lock is a { jobId, at } pair stored next to the data. A server may take over a lock that has
-- not been refreshed for SessionLock.ExpireSeconds (its server probably crashed). Autosave refreshes it.
--
-- If DataStores are unavailable (Studio without "Enable Studio Access to API Services", or an
-- unpublished place) the session still works with fresh data but is marked `persistent = false`
-- and nothing is saved.

local DataStoreService = game:GetService("DataStoreService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local PlayerData = require(ReplicatedStorage.Shared.Data.PlayerData)
local SessionLock = require(ReplicatedStorage.Shared.Data.SessionLock)

local PlayerStore = {}

local STORE_NAME = "Players_v1"
local LOAD_ATTEMPTS = 4
local RETRY_SECONDS = 4

export type Session = {
	key: string,
	data: PlayerData.Data,
	persistent: boolean,
	released: boolean,
}

local store: DataStore? = nil
local storeFailed = false

local function getStore(): DataStore?
	if store or storeFailed then
		return store
	end
	local ok, result = pcall(function()
		return DataStoreService:GetDataStore(STORE_NAME)
	end)
	if ok then
		store = result
	else
		storeFailed = true
		warn("[PlayerStore] DataStore unavailable:", result)
	end
	return store
end

local function lockedByOther(stored: any): boolean
	return SessionLock.heldByOther(stored, game.JobId, os.time())
end

-- Plain copy of the data plus the lock, ready for the DataStore.
local function pack(data: PlayerData.Data, locked: boolean): any
	local out: any = table.clone(data)
	out.lock = if locked then SessionLock.make(game.JobId, os.time()) else nil
	return out
end

-- Returns a session. `kick` is called with a message if the data is locked by another server for
-- too long (the caller removes the player from the game).
function PlayerStore.load(player: Player, kick: (message: string) -> ()): Session
	local key = `player_{player.UserId}`
	local session: Session = { key = key, data = PlayerData.new(), persistent = false, released = false }

	local ds = getStore()
	if not ds then
		return session
	end

	for attempt = 1, LOAD_ATTEMPTS do
		local locked = false
		local ok, stored = pcall(function()
			return ds:UpdateAsync(key, function(old: any)
				if lockedByOther(old) then
					locked = true
					return nil -- cancel: do not touch someone else's session
				end
				return pack(PlayerData.sanitize(old), true)
			end)
		end)
		if ok and not locked and stored ~= nil then
			session.data = PlayerData.sanitize(stored)
			session.persistent = true
			return session
		elseif ok and locked then
			if attempt == LOAD_ATTEMPTS then
				kick("Your data is being used on another server. Please rejoin in a minute.")
				session.released = true -- never save over the other server's data
				return session
			end
			task.wait(RETRY_SECONDS)
		else
			-- DataStore error (offline, throttled, API access off). Treat as unavailable for this session.
			warn("[PlayerStore] load failed:", stored)
			return session
		end
	end
	return session
end

-- Writes the session. `release` also removes the lock (player is leaving).
function PlayerStore.save(session: Session, release: boolean): boolean
	if not session.persistent or session.released then
		return false
	end
	local ds = getStore()
	if not ds then
		return false
	end
	local lost = false
	local ok, err = pcall(function()
		ds:UpdateAsync(session.key, function(old: any)
			if lockedByOther(old) then
				lost = true
				return nil
			end
			return pack(session.data, not release)
		end)
	end)
	if not ok then
		warn("[PlayerStore] save failed:", err)
		return false
	end
	if lost then
		warn("[PlayerStore] lost the session lock for", session.key)
		session.released = true
		return false
	end
	if release then
		session.released = true
	end
	return true
end

-- Trade history for investigating scams (spec: Trades_Log, keyed by trade id). Failure to write is
-- only a warning: a log problem must never block or undo a trade.
function PlayerStore.logTrade(tradeId: string, entry: any)
	local ok, err = pcall(function()
		DataStoreService:GetDataStore("Trades_Log"):SetAsync(tradeId, entry)
	end)
	if not ok then
		warn("[PlayerStore] trade log failed:", err)
	end
end

return PlayerStore
