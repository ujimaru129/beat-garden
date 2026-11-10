--!strict
-- Prototype endpoint for the rhythm game. Hands out a test chart for the chosen song, times
-- the run on the server, and validates the client's summary the same way the real Tend flow
-- will. Gives no rewards. Switched by Shared.Dev.Flags.RhythmPrototype.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Flags = require(ReplicatedStorage.Shared.Dev.Flags)
local RhythmEngine = require(ReplicatedStorage.Shared.RhythmEngine)
local Songs = require(ReplicatedStorage.Shared.Songs)
local TestCharts = require(ReplicatedStorage.Shared.Dev.TestCharts)

local RhythmDev = {}

type Pending = { segment: RhythmEngine.Segment, startedAt: number }

function RhythmDev.start()
	if not Flags.RhythmPrototype then
		return
	end

	local remote = Instance.new("RemoteFunction")
	remote.Name = "RhythmDev"
	remote.Parent = ReplicatedStorage

	local pending: { [Player]: Pending } = {}

	remote.OnServerInvoke = function(player: Player, action: unknown, payload: unknown): any
		if action == "start" then
			-- payload: { songId: string, difficulty: string }. Anything invalid falls back to a default.
			local request: any = if type(payload) == "table" then payload else {}
			local song = (if type(request.songId) == "string" then Songs.byId(request.songId) else nil)
				or Songs.List[1]
			local difficulty = if type(request.difficulty) == "string" and TestCharts.has(request.difficulty)
				then request.difficulty
				else "Normal"
			local segment = TestCharts.build(song.bpm, difficulty) :: RhythmEngine.Segment
			pending[player] = { segment = segment, startedAt = os.clock() }
			return { segment = segment, songId = song.id, difficulty = difficulty }
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
