--!strict
-- The session lock stored next to a player's data: { jobId, at }. Pure functions so the rules can be
-- tested without a DataStore.

local SessionLock = {}

-- A lock that has not been refreshed for this long is treated as abandoned (its server probably crashed).
SessionLock.ExpireSeconds = 120

-- Is `stored` (the raw value read from the DataStore) locked by a different, still-alive server?
function SessionLock.heldByOther(stored: any, myJobId: string, now: number): boolean
	local lock = type(stored) == "table" and stored.lock
	if type(lock) ~= "table" then
		return false
	end
	if type(lock.jobId) ~= "string" or type(lock.at) ~= "number" then
		return false -- damaged lock: do not let it block the player forever
	end
	return lock.jobId ~= myJobId and now - lock.at < SessionLock.ExpireSeconds
end

function SessionLock.make(jobId: string, now: number): { jobId: string, at: number }
	return { jobId = jobId, at = now }
end

return table.freeze(SessionLock)
