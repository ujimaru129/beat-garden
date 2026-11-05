--!strict
-- Studio-only endpoint for the rhythm prototype. Hands out a test chart, times the run on the
-- server, and validates the client's summary the same way the real Tend flow will.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local RhythmEngine = require(ReplicatedStorage.Shared.RhythmEngine)
local TestCharts = require(ReplicatedStorage.Shared.Dev.TestCharts)

local RhythmDev = {}

type Pending = { segment: RhythmEngine.Segment, startedAt: number }

function RhythmDev.start()
	if not RunService:IsStudio() then
		return
	end

	local remote = Instance.new("RemoteFunction")
	remote.Name = "RhythmDev"
	remote.Parent = ReplicatedStorage

	local pending: { [Player]: Pending } = {}

	remote.OnServerInvoke = function(player: Player, action: unknown, payload: unknown): any
		if action == "start" then
			local name = if type(payload) == "string" and (TestCharts :: any)[payload] then payload else "Normal"
			local segment = (TestCharts :: any)[name] :: RhythmEngine.Segment
			pending[player] = { segment = segment, startedAt = os.clock() }
			return { segment = segment, bpm = TestCharts.Bpm[name], name = name }
		elseif action == "submit" then
			local p = pending[player]
			pending[player] = nil
			if not p then
				return { ok = false, reason = "no run in progress" }
			end
			local elapsedMs = (os.clock() - p.startedAt) * 1000
			local result = RhythmEngine.Validator.validate(p.segment, payload, { elapsedMs = elapsedMs })
			print(`[RhythmDev] {player.Name}: ok={result.ok} reason={result.reason} elapsed={math.floor(elapsedMs)}ms`)
			return {
				ok = result.ok,
				reason = result.reason,
				counts = result.tally and result.tally.counts,
				maxCombo = result.tally and result.tally.maxCombo,
				maxPerfectStreak = result.tally and result.tally.maxPerfectStreak,
				accuracy = result.tally and result.tally.accuracy,
			}
		end
		return nil
	end

	game:GetService("Players").PlayerRemoving:Connect(function(player)
		pending[player] = nil
	end)
end

return RhythmDev
