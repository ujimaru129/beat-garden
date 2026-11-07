--!strict
-- Client entry point (StarterPlayer/StarterPlayerScripts/Client)
-- HUD, rhythm overlay and input will be required from here.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local RhythmLane3D = require(script.RhythmLane3D)
local RhythmOverlay = require(script.RhythmOverlay)

-- Rhythm prototype (Studio only): 1 = Easy, 2 = Normal, 3 = Hard.
-- Set the attribute "LatencyMs" on the LocalPlayer to try calibration values.
if RunService:IsStudio() then
	local remote = ReplicatedStorage:WaitForChild("RhythmDev") :: RemoteFunction
	local player = game:GetService("Players").LocalPlayer
	local running = false

	local CHART_KEYS = {
		[Enum.KeyCode.One] = "Easy",
		[Enum.KeyCode.Two] = "Normal",
		[Enum.KeyCode.Three] = "Hard",
	}

	UserInputService.InputBegan:Connect(function(input, gameProcessed)
		local chartName = CHART_KEYS[input.KeyCode]
		if gameProcessed or running or not chartName then
			return
		end
		running = true
		local info = remote:InvokeServer("start", chartName)
		local options: RhythmOverlay.Options = {
			latencyMs = tonumber(player:GetAttribute("LatencyMs")) or 0,
			bpm = info.bpm,
			metronome = true,
			onFinished = function(summary)
				local verdict = remote:InvokeServer("submit", summary)
				local c = summary.counts
				print(
					`[RhythmDev] {info.name}: P{c.Perfect} G{c.Great} g{c.Good} M{c.Miss}`
						.. ` combo {summary.maxCombo} perfectStreak {summary.maxPerfectStreak}`
						.. ` acc {string.format("%.1f", summary.accuracy * 100)}%`
						.. ` | server ok={verdict.ok} {verdict.reason or ""}`
				)
				running = false
			end,
		}
		-- 3D lane by default. Set the LocalPlayer attribute "Rhythm2D" to true for the flat overlay.
		if player:GetAttribute("Rhythm2D") == true then
			RhythmOverlay.play(info.segment, options)
		else
			RhythmLane3D.play(info.segment, options)
		end
	end)
	print("[BeatGarden] rhythm prototype ready: press 1 Easy / 2 Normal / 3 Hard")
end

print("[BeatGarden] client started")
