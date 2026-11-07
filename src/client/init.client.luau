--!strict
-- Client entry point (StarterPlayer/StarterPlayerScripts/Client)
-- HUD, rhythm overlay and input will be required from here.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Atmosphere = require(script.Atmosphere)
local Calibrator = require(script.Calibrator)
local GardenState = require(script.GardenState)
local MarketUI = require(script.MarketUI)
local PlotVisuals = require(script.PlotVisuals)
local PromptFilter = require(script.PromptFilter)
local SpiritUI = require(script.SpiritUI)
local TradeUI = require(script.TradeUI)
local Difficulty = require(ReplicatedStorage.Shared.Difficulty)
local Palette = require(ReplicatedStorage.Shared.Palette)
local RhythmRunner = require(script.RhythmRunner)
local TendFlow = require(script.TendFlow)
local TutorialUI = require(script.TutorialUI)

local player = Players.LocalPlayer :: Player

-- Garden data from the server, then the screens that use it.
GardenState.start()
Atmosphere.start()
PlotVisuals.start()
PromptFilter.start()
MarketUI.start()
SpiritUI.start()
TradeUI.start()
TutorialUI.start()

-- The plant prompt (tap, or E on keyboard): plant a seed, Tend it, or harvest it.
TendFlow.start()

-- Calibration: a button at the top left opens the tap-along screen.
local calibrator = Calibrator.create(function(latencyMs)
	print(`[BeatGarden] latency calibrated: {latencyMs} ms`)
	GardenState.call("setLatency", latencyMs) -- saved with the player data
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
		-- 0 = wipe this player's data and replay the tutorial
		if not gameProcessed and input.KeyCode == Enum.KeyCode.Zero then
			print("[BeatGarden] reset:", GardenState.call("devReset").ok)
			return
		end
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
	print("[BeatGarden] dev shortcuts: 1 / 2 / 3 try a chart, 0 resets your data, N flips day / night")
end

print("[BeatGarden] client started")
