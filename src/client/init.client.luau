--!strict
-- Client entry point (StarterPlayer/StarterPlayerScripts/Client)
-- HUD, rhythm overlay and input will be required from here.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Atmosphere = require(script.Atmosphere)
local Calibrator = require(script.Calibrator)
local Lang = require(script.Lang)
local CollectionUI = require(script.CollectionUI)
local GardenState = require(script.GardenState)
local LeaderboardUI = require(script.LeaderboardUI)
local MarketUI = require(script.MarketUI)
local ParkFx = require(script.ParkFx)
local ParkUI = require(script.ParkUI)
local PlotVisuals = require(script.PlotVisuals)
local PromptText = require(script.PromptText)
local PromptFilter = require(script.PromptFilter)
local RushBanner = require(script.RushBanner)
local SpiritUI = require(script.SpiritUI)
local TradeUI = require(script.TradeUI)
local Difficulty = require(ReplicatedStorage.Shared.Difficulty)
local RhythmRunner = require(script.RhythmRunner)
local TendFlow = require(script.TendFlow)
local TutorialUI = require(script.TutorialUI)
local UiTheme = require(script.UiTheme)
local WorldFx = require(script.WorldFx)

local player = Players.LocalPlayer :: Player

-- The whole interface is made for a landscape phone: ask for landscape (it follows the sensor, so it can still flip
-- between the two landscape sides). Pcall: the property is missing on some platforms.
pcall(function()
	(player:WaitForChild("PlayerGui") :: any).ScreenOrientation = Enum.ScreenOrientation.LandscapeSensor
end)

-- Garden data from the server, then the screens that use it.
GardenState.start()
Atmosphere.start()
PlotVisuals.start()
task.spawn(WorldFx.start) -- waits for the island to arrive
PromptFilter.start()
PromptText.start()
ParkFx.start()
MarketUI.start()
SpiritUI.start()
CollectionUI.start()
ParkUI.start()
LeaderboardUI.start()
TradeUI.start()
TutorialUI.start()
RushBanner.start()

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
calButton.AnchorPoint = Vector2.new(1, 0)
calButton.Position = UDim2.new(1, -12, 0, 10)
calButton.Size = UDim2.fromOffset(104, 36)
calButton.TextScaled = true
calButton.Text = Lang.t("Calibrate")
local calLimit = Instance.new("UITextSizeConstraint")
calLimit.MaxTextSize = 18
calLimit.Parent = calButton
calButton.Parent = calGui
UiTheme.watch(function()
	UiTheme.styleButton(calButton, UiTheme.get(), "Fuji", 12)
end)
UiTheme.hideDuringRun(calGui)
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
