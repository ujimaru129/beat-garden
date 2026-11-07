--!strict
-- Client entry point (StarterPlayer/StarterPlayerScripts/Client)
-- HUD, rhythm overlay and input will be required from here.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Calibrator = require(script.Calibrator)
local Difficulty = require(ReplicatedStorage.Shared.Difficulty)
local Palette = require(ReplicatedStorage.Shared.Palette)
local RhythmRunner = require(script.RhythmRunner)
local TendFlow = require(script.TendFlow)

local player = Players.LocalPlayer :: Player

-- Tend: walk up to your plant and tap its prompt (E on keyboard) to pick a difficulty and play.
TendFlow.start()

-- Calibration: a button at the top left opens the tap-along screen.
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
	if not RhythmRunner.isRunning() and not calibrator.isOpen() then
		calibrator.open()
	end
end)

-- Studio-only shortcut for trying charts without a plant: keys 1 / 2 / 3 = Easy / Normal / Hard.
-- (Results are only checked, not applied to any plant.)
if RunService:IsStudio() then
	local remote = ReplicatedStorage:WaitForChild("RhythmDev") :: RemoteFunction
	local CHART_KEYS: { [Enum.KeyCode]: Difficulty.Name } = {
		[Enum.KeyCode.One] = "Easy",
		[Enum.KeyCode.Two] = "Normal",
		[Enum.KeyCode.Three] = "Hard",
	}
	UserInputService.InputBegan:Connect(function(input, gameProcessed)
		local chartName = CHART_KEYS[input.KeyCode]
		if gameProcessed or not chartName or RhythmRunner.isRunning() or calibrator.isOpen() then
			return
		end
		local info = remote:InvokeServer("start", chartName)
		local run = ({ segment = info.segment, bpm = info.bpm, difficulty = chartName } :: any) :: RhythmRunner.Run
		RhythmRunner.play(run, function(summary)
			local verdict = remote:InvokeServer("submit", summary)
			local c = summary.counts
			print(
				`[RhythmDev] {info.name}: P{c.Perfect} G{c.Great} g{c.Good} M{c.Miss}`
					.. ` combo {summary.maxCombo} perfectStreak {summary.maxPerfectStreak}`
					.. ` acc {string.format("%.1f", summary.accuracy * 100)}%`
					.. ` | server ok={verdict.ok} {verdict.reason or ""}`
			)
		end)
	end)
	print("[BeatGarden] dev shortcuts: press 1 / 2 / 3 to try a chart")
end

print("[BeatGarden] client started")
