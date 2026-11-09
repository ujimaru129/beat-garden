--!strict
-- One short message near the top of the screen (a new message replaces the old one).

local Players = game:GetService("Players")

local UiTheme = require(script.Parent.UiTheme)

local Toast = {}

-- Shown for a short time: 2 s plus a little for longer messages, at most 3.5 s.
local MIN_SECONDS = 2
local MAX_SECONDS = 3.5

-- Full-screen panels that sit over the usual toast spot: the toast moves above them while one is open.
local PANELS = { "ListModal", "SongSelect", "DifficultyPicker" }
local TOP_Y = 0.12
local NORMAL_Y = 0.28

local label: TextLabel? = nil
local token = 0

local function ensure(): TextLabel
	if label then
		return label
	end
	local gui = Instance.new("ScreenGui")
	gui.Name = "Toast"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.DisplayOrder = 90

	local l = Instance.new("TextLabel")
	l.AnchorPoint = Vector2.new(0.5, 0.5)
	-- Below the tutorial banner (top centre) and clear of the Roblox menu buttons at the top left.
	l.Position = UDim2.fromScale(0.5, NORMAL_Y)
	l.Size = UDim2.fromScale(0.5, 0.16)
	l.TextScaled = true
	l.Visible = false
	l.Parent = gui
	local size = Instance.new("UISizeConstraint")
	size.MaxSize = Vector2.new(640, 90)
	size.MinSize = Vector2.new(0, 50)
	size.Parent = l
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 12)
	corner.Parent = l
	local padding = Instance.new("UIPadding")
	padding.PaddingTop = UDim.new(0.15, 0)
	padding.PaddingBottom = UDim.new(0.15, 0)
	padding.PaddingLeft = UDim.new(0.04, 0)
	padding.PaddingRight = UDim.new(0.04, 0)
	padding.Parent = l
	gui.Parent = (Players.LocalPlayer :: Player):WaitForChild("PlayerGui")
	label = l
	return l
end

local function panelOpen(): boolean
	local playerGui = (Players.LocalPlayer :: Player):FindFirstChildOfClass("PlayerGui")
	if not playerGui then
		return false
	end
	for _, child in playerGui:GetChildren() do
		if child:IsA("ScreenGui") and child.Enabled and table.find(PANELS, child.Name) then
			return true
		end
	end
	return false
end

function Toast.show(text: string)
	local l = ensure()
	l.Position = UDim2.fromScale(0.5, if panelOpen() then TOP_Y else NORMAL_Y)
	token += 1
	local mine = token
	local theme = UiTheme.get()
	UiTheme.stylePanel(l, theme, 12, false)
	UiTheme.styleText(l, theme, "body")
	l.Text = text
	l.Visible = true
	task.delay(math.min(MAX_SECONDS, MIN_SECONDS + #text * 0.03), function()
		if token == mine then
			l.Visible = false
		end
	end)
end

return Toast
