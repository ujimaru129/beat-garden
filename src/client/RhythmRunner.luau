--!strict
-- Starts one rhythm run on the 3D lane (or the flat overlay when the LocalPlayer attribute
-- "Rhythm2D" is true) and makes sure only one run is going at a time.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Difficulty = require(ReplicatedStorage.Shared.Difficulty)
local RhythmEngine = require(ReplicatedStorage.Shared.RhythmEngine)
local RhythmLane3D = require(script.Parent.RhythmLane3D)
local RhythmOverlay = require(script.Parent.RhythmOverlay)
local SongClock = require(script.Parent.SongClock)

local RhythmRunner = {}

export type Run = {
	segment: RhythmEngine.Segment,
	bpm: number,
	beatsMs: { number }?, -- real beat times; the metronome ticks on these instead of a fixed bpm
	audioAssetId: string?, -- uploaded audio; when set it plays and drives the clock
	audioEndMs: number?, -- the song is cut here: the audio stops (softly) and the run may end
	offsetMs: number?, -- shifts the chart against the audio
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
	local clock: SongClock.Clock? = nil
	player:SetAttribute("InRhythm", true)
	local options: RhythmOverlay.Options = {
		latencyMs = tonumber(player:GetAttribute("LatencyMs")) or 0,
		chartOffsetMs = run.offsetMs,
		bpm = run.bpm,
		beatTimesMs = run.beatsMs,
		scrollMs = Difficulty.ScrollMs[run.difficulty],
		metronome = true,
		onFinished = function(summary)
			running = false
			player:SetAttribute("InRhythm", nil)
			if clock then
				clock.stop()
			end
			onFinished(summary)
		end,
	}
	local function start()
		if player:GetAttribute("Rhythm2D") == true then
			RhythmOverlay.play(run.segment, options)
		else
			RhythmLane3D.play(run.segment, options)
		end
	end
	local assetId = run.audioAssetId
	if assetId and #run.segment.notes > 0 then
		-- Real audio: load it, then use its position as the clock. Without it, the metronome plays.
		task.spawn(function()
			local leadIn = 2000
			clock = SongClock.create(assetId, run.segment.notes[1][2], leadIn, run.audioEndMs)
			if clock then
				options.getSongTimeMs = clock.getTimeMs
				options.isAudioDone = clock.isDone
				options.leadInMs = leadIn
			end
			start()
		end)
	else
		start()
	end
	return true
end

return RhythmRunner
