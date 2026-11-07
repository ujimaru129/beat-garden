--!strict
-- Starts one rhythm run on the 3D lane (or the flat overlay when the LocalPlayer attribute
-- "Rhythm2D" is true) and makes sure only one run is going at a time.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Difficulty = require(ReplicatedStorage.Shared.Difficulty)
local RhythmEngine = require(ReplicatedStorage.Shared.RhythmEngine)
local RhythmLane3D = require(script.Parent.RhythmLane3D)
local RhythmOverlay = require(script.Parent.RhythmOverlay)

local RhythmRunner = {}

export type Run = {
	segment: RhythmEngine.Segment,
	bpm: number,
	difficulty: Difficulty.Name,
}

local running = false

function RhythmRunner.isRunning(): boolean
	return running
end

-- Returns false (and does nothing) when a run is already going.
function RhythmRunner.play(run: Run, onFinished: (summary: RhythmEngine.Summary) -> ()): boolean
	if running then
		return false
	end
	running = true
	local player = Players.LocalPlayer :: Player
	local options: RhythmOverlay.Options = {
		latencyMs = tonumber(player:GetAttribute("LatencyMs")) or 0,
		bpm = run.bpm,
		scrollMs = Difficulty.ScrollMs[run.difficulty],
		metronome = true,
		onFinished = function(summary)
			running = false
			onFinished(summary)
		end,
	}
	if player:GetAttribute("Rhythm2D") == true then
		RhythmOverlay.play(run.segment, options)
	else
		RhythmLane3D.play(run.segment, options)
	end
	return true
end

return RhythmRunner
