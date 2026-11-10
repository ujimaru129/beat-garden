--!strict
-- Client entry point (StarterPlayer/StarterPlayerScripts/Client)
-- HUD, rhythm overlay and input will be required from here.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local Difficulty = require(ReplicatedStorage.Shared.Difficulty)
local Flags = require(ReplicatedStorage.Shared.Dev.Flags)
local RhythmLane3D = require(script.RhythmLane3D)
local RhythmOverlay = require(script.RhythmOverlay)
local SongPlayer = require(script.SongPlayer)
local SongSelect = require(script.SongSelect)
local Songs = require(ReplicatedStorage.Shared.Songs)

-- Rhythm prototype. Touch-first: tap a song (its preview plays), then Easy / Normal / Hard.
-- Keyboard: Up / Down change the song, 1 / 2 / 3 start a run.
-- Set the attribute "LatencyMs" on the LocalPlayer to try calibration values.
if Flags.RhythmPrototype then
	local remote = ReplicatedStorage:WaitForChild("RhythmDev") :: RemoteFunction
	local player = game:GetService("Players").LocalPlayer
	local running = false
	local screen: SongSelect.Screen

	local function startRun(song: Songs.Song, difficulty: string)
		if running then
			return
		end
		running = true
		screen.setVisible(false) -- also stops the preview
		local info = remote:InvokeServer("start", { songId = song.id, difficulty = difficulty })
		local segment = info.segment

		-- Start the music a little before the first note (from the top when the chart starts early).
		local firstNoteMs = segment.notes[1][2]
		local playback = SongPlayer.play(song, {
			startMs = if firstNoteMs <= 5000 then 0 else firstNoteMs - 3000,
		})

		local options: RhythmOverlay.Options = {
			latencyMs = tonumber(player:GetAttribute("LatencyMs")) or 0,
			chartOffsetMs = song.offsetMs,
			getSongTimeMs = playback.getTimeMs,
			bpm = song.bpm,
			scrollMs = (Difficulty.ScrollMs :: any)[difficulty],
			onFinished = function(summary)
				playback.stop(0.6)
				local verdict = remote:InvokeServer("submit", summary)
				local c = summary.counts
				print(
					`[RhythmDev] {song.title} {difficulty}: P{c.Perfect} G{c.Great} g{c.Good} M{c.Miss}`
						.. ` combo {summary.maxCombo} perfectStreak {summary.maxPerfectStreak}`
						.. ` acc {string.format("%.1f", summary.accuracy * 100)}%`
						.. ` | server ok={verdict.ok} {verdict.reason or ""}`
				)
				running = false
				screen.setVisible(true)
			end,
		}
		-- 3D lane by default. Set the LocalPlayer attribute "Rhythm2D" to true for the flat overlay.
		if player:GetAttribute("Rhythm2D") == true then
			RhythmOverlay.play(segment, options)
		else
			RhythmLane3D.play(segment, options)
		end
	end

	screen = SongSelect.create(startRun)

	local DIFFICULTY_KEYS = {
		[Enum.KeyCode.One] = "Easy",
		[Enum.KeyCode.Two] = "Normal",
		[Enum.KeyCode.Three] = "Hard",
	}
	UserInputService.InputBegan:Connect(function(input, gameProcessed)
		if gameProcessed or running then
			return
		end
		local difficulty = DIFFICULTY_KEYS[input.KeyCode]
		if difficulty then
			startRun(screen.getSelected(), difficulty)
		elseif input.KeyCode == Enum.KeyCode.Up then
			screen.step(-1)
		elseif input.KeyCode == Enum.KeyCode.Down then
			screen.step(1)
		end
	end)
	print("[BeatGarden] rhythm prototype ready: pick a song, then tap Easy / Normal / Hard (or press 1 / 2 / 3)")
end

print("[BeatGarden] client started")
