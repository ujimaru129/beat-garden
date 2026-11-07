--!strict
-- Client entry point (StarterPlayer/StarterPlayerScripts/Client)
-- HUD, rhythm overlay and input will be required from here.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Difficulty = require(ReplicatedStorage.Shared.Difficulty)
local Calibrator = require(script.Calibrator)
local DifficultyPicker = require(script.DifficultyPicker)
local Palette = require(ReplicatedStorage.Shared.Palette)
local RhythmLane3D = require(script.RhythmLane3D)
local RhythmOverlay = require(script.RhythmOverlay)

-- Rhythm prototype (Studio only). Touch-first: tap Easy / Normal / Hard on screen.
-- Keyboard 1 / 2 / 3 do the same, as a shortcut.
-- Set the attribute "LatencyMs" on the LocalPlayer to try calibration values.
if RunService:IsStudio() then
	local remote = ReplicatedStorage:WaitForChild("RhythmDev") :: RemoteFunction
	local player = game:GetService("Players").LocalPlayer
	local running = false
	local picker: DifficultyPicker.Picker

	local function startRun(chartName: string)
		if running then
			return
		end
		running = true
		picker.setVisible(false)
		local info = remote:InvokeServer("start", chartName)
		local options: RhythmOverlay.Options = {
			latencyMs = tonumber(player:GetAttribute("LatencyMs")) or 0,
			bpm = info.bpm,
			scrollMs = (Difficulty.ScrollMs :: any)[chartName],
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
				picker.setVisible(true)
			end,
		}
		-- 3D lane by default. Set the LocalPlayer attribute "Rhythm2D" to true for the flat overlay.
		if player:GetAttribute("Rhythm2D") == true then
			RhythmOverlay.play(info.segment, options)
		else
			RhythmLane3D.play(info.segment, options)
		end
	end

	picker = DifficultyPicker.create(startRun)

	-- Calibration: a gear-style button at the top left opens the tap-along screen.
	local calibrator = Calibrator.create(function(latencyMs)
		print(`[BeatGarden] latency calibrated: {latencyMs} ms`)
	end)
	local calGui = Instance.new("ScreenGui")
	calGui.Name = "CalibrateButton"
	calGui.ResetOnSpawn = false
	calGui.DisplayOrder = 30
	local calButton = Instance.new("TextButton")
	calButton.Position = UDim2.fromOffset(16, 16)
	calButton.Size = UDim2.fromOffset(120, 48)
	calButton.BackgroundColor3 = Palette.Base.Sumi
	calButton.TextColor3 = Palette.Base.Washi
	calButton.Font = Enum.Font.GothamBold
	calButton.TextScaled = true
	calButton.Text = "Calibrate"
	local calPadding = Instance.new("UIPadding")
	calPadding.PaddingTop = UDim.new(0.2, 0)
	calPadding.PaddingBottom = UDim.new(0.2, 0)
	calPadding.Parent = calButton
	local calCorner = Instance.new("UICorner")
	calCorner.CornerRadius = UDim.new(0, 12)
	calCorner.Parent = calButton
	calButton.Parent = calGui
	calGui.Parent = player:WaitForChild("PlayerGui")
	calButton.Activated:Connect(function()
		if not running and not calibrator.isOpen() then
			calibrator.open()
		end
	end)

	local CHART_KEYS = {
		[Enum.KeyCode.One] = "Easy",
		[Enum.KeyCode.Two] = "Normal",
		[Enum.KeyCode.Three] = "Hard",
	}
	UserInputService.InputBegan:Connect(function(input, gameProcessed)
		local chartName = CHART_KEYS[input.KeyCode]
		if gameProcessed or not chartName then
			return
		end
		startRun(chartName)
	end)
	print("[BeatGarden] rhythm prototype ready: tap Easy / Normal / Hard (or press 1 / 2 / 3)")
end

print("[BeatGarden] client started")
