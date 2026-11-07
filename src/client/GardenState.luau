--!strict
-- The client's copy of the player's garden data. The server pushes a snapshot after every change
-- (GardenUpdate event); this module keeps the latest one and lets screens react to it.
-- It never changes anything itself: actions go to the server through `call`.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GardenState = {}

export type FruitInfo = { seedId: string, mutation: string?, weight: number, value: number }

export type Snapshot = {
	coins: number,
	seeds: { [string]: number },
	fruits: { FruitInfo },
	plot: { seedId: string, fraction: number, stage: string }?,
	settings: { latencyMs: number },
	persistent: boolean,
}

local current: Snapshot? = nil
local listeners: { [number]: (Snapshot) -> () } = {}
local nextId = 0
local gardenRemote: RemoteFunction? = nil
local adoptedLatency = false

local function apply(snapshot: Snapshot)
	current = snapshot

	-- Use the saved latency once, unless the player already calibrated in this session.
	if not adoptedLatency then
		adoptedLatency = true
		local player = Players.LocalPlayer :: Player
		if player:GetAttribute("LatencyMs") == nil and snapshot.settings.latencyMs ~= 0 then
			player:SetAttribute("LatencyMs", snapshot.settings.latencyMs)
		end
	end

	for _, listener in listeners do
		task.spawn(listener, snapshot)
	end
end

function GardenState.start()
	local update = ReplicatedStorage:WaitForChild("GardenUpdate", 10) :: RemoteEvent?
	gardenRemote = ReplicatedStorage:WaitForChild("Garden", 10) :: RemoteFunction?
	if not (update and gardenRemote) then
		warn("[GardenState] garden remotes not found")
		return
	end
	update.OnClientEvent:Connect(apply)
	task.spawn(function()
		local result = GardenState.call("state")
		if result.ok and current == nil then
			apply(result.state)
		end
	end)
end

function GardenState.get(): Snapshot?
	return current
end

-- Calls `listener` with every new snapshot. Returns a function that stops listening.
function GardenState.onChanged(listener: (Snapshot) -> ()): () -> ()
	nextId += 1
	local id = nextId
	listeners[id] = listener
	return function()
		listeners[id] = nil
	end
end

-- Asks the server to do something. Always returns a table with `ok`.
function GardenState.call(action: string, payload: any?): any
	local remote = gardenRemote
	if not remote then
		return { ok = false, reason = "offline" }
	end
	local ok, result = pcall(function()
		return remote:InvokeServer(action, payload)
	end)
	if not ok or type(result) ~= "table" then
		return { ok = false, reason = "no answer" }
	end
	return result
end

return GardenState
