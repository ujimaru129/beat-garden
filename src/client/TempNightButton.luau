--!strict
-- TEMPORARY: a Day/Night button on the HUD for recording videos. Remove this file and its two lines in init.client.luau
-- (the require and the start call, both marked TEMP) when the recording is done.

local Players = game:GetService("Players")

local Atmosphere = require(script.Parent.Atmosphere)
local MarketUI = require(script.Parent.MarketUI)

local TempNightButton = {}

function TempNightButton.start()
	local player = Players.LocalPlayer :: Player
	local gui = Instance.new("ScreenGui")
	gui.Name = "TempNightButton"
	gui.ResetOnSpawn = false
	gui.DisplayOrder = 30
	local button = MarketUI.makeHudButton(gui, "Day / Night", 174)
	-- the right edge is full of HUD buttons: top centre
	button.AnchorPoint = Vector2.new(0.5, 0)
	button.Position = UDim2.new(0.5, 0, 0, 10)
	gui.Parent = player:WaitForChild("PlayerGui")
	button.Activated:Connect(function()
		player:SetAttribute("ForceTimeOfDay", if Atmosphere.timeOfDay() == "Day" then "Night" else "Day")
	end)
end

return TempNightButton
