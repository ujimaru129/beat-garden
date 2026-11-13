--!strict
-- A bobbing sign over the player's own growing plant that says how to reach the rhythm game ("Tap Tend to play!").
-- New players did not realise that growing a plant IS the rhythm game. The sign shows while the tutorial waits for the
-- first Tend, and for a player's first few plays (the plant must be growing: not empty, locked or ready to harvest).

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GardenState = require(script.Parent.GardenState)
local Lang = require(script.Parent.Lang)
local Tutorial = require(ReplicatedStorage.Shared.Garden.Tutorial)

local PlayHint = {}

local SHOW_FOR_RUNS = 3 -- the sign stays until the player has played this many times
local GROWING = { Seed = true, Sprout = true, Sapling = true, Bloom = true }
local TEXT = "\u{266A} Tap Tend to play the rhythm game!"

function PlayHint.start()
	local player = Players.LocalPlayer :: Player
	local signs: { [Instance]: BillboardGui } = {}

	local function wanted(soil: Instance): boolean
		local snapshot = GardenState.get()
		if not snapshot or soil:GetAttribute("OwnerUserId") ~= player.UserId then
			return false
		end
		if not GROWING[soil:GetAttribute("Stage") :: any] then
			return false
		end
		return snapshot.tutorialStep == Tutorial.Steps.Tend or snapshot.park.stats.runs < SHOW_FOR_RUNS
	end

	local function make(soil: Instance): BillboardGui
		local gui = Instance.new("BillboardGui")
		gui.Name = "PlayHint"
		gui.Adornee = soil :: any
		gui.Size = UDim2.fromOffset(250, 46)
		gui.StudsOffsetWorldSpace = Vector3.new(0, 11, 0)
		gui.AlwaysOnTop = true
		gui.MaxDistance = 90
		gui.LightInfluence = 0
		gui.ResetOnSpawn = false
		local label = Instance.new("TextLabel")
		label.Size = UDim2.fromScale(1, 1)
		label.BackgroundColor3 = Color3.fromHex("#FF5FA8")
		label.TextColor3 = Color3.new(1, 1, 1)
		label.Font = Enum.Font.GothamBold
		label.TextScaled = true
		label.Text = Lang.t(TEXT)
		label.Parent = gui
		local corner = Instance.new("UICorner")
		corner.CornerRadius = UDim.new(0, 20)
		corner.Parent = label
		local stroke = Instance.new("UIStroke")
		stroke.Color = Color3.new(1, 1, 1)
		stroke.Thickness = 3
		stroke.Parent = label
		local pad = Instance.new("UIPadding")
		pad.PaddingTop = UDim.new(0.2, 0)
		pad.PaddingBottom = UDim.new(0.2, 0)
		pad.PaddingLeft = UDim.new(0.06, 0)
		pad.PaddingRight = UDim.new(0.06, 0)
		pad.Parent = label
		gui.Parent = soil
		return gui
	end

	local function refresh(soil: Instance)
		local sign = signs[soil]
		if wanted(soil) then
			if not sign then
				signs[soil] = make(soil)
			end
		elseif sign then
			sign:Destroy()
			signs[soil] = nil
		end
	end

	local function track(soil: Instance)
		if soil:GetAttribute("OwnerUserId") == nil then
			soil:GetAttributeChangedSignal("OwnerUserId"):Wait()
		end
		soil:GetAttributeChangedSignal("Stage"):Connect(function()
			refresh(soil)
		end)
		soil.Destroying:Connect(function()
			signs[soil] = nil
		end)
		refresh(soil)
	end

	local container = Workspace:WaitForChild("Garden", 15)
	if not container then
		return
	end
	container.ChildAdded:Connect(function(child)
		task.spawn(track, child)
	end)
	for _, child in container:GetChildren() do
		task.spawn(track, child)
	end
	GardenState.onChanged(function()
		for soil in signs do
			refresh(soil)
		end
		for _, child in container:GetChildren() do
			if not signs[child] then
				refresh(child)
			end
		end
	end)

	RunService.RenderStepped:Connect(function()
		local bob = math.sin(os.clock() * 4) * 0.7
		for _, sign in signs do
			sign.StudsOffsetWorldSpace = Vector3.new(0, 11 + bob, 0)
		end
	end)
end

return PlayHint
