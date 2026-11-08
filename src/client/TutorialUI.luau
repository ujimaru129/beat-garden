--!strict
-- The tutorial guide: a one-line banner at the top of the screen that always says what to do next,
-- with a Skip button. The server owns the step (it moves only when the player really does the
-- thing); this module only shows it.

local LocalizationService = game:GetService("LocalizationService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GardenState = require(script.Parent.GardenState)
local Palette = require(ReplicatedStorage.Shared.Palette)
local Strings = require(ReplicatedStorage.Shared.Strings)
local Toast = require(script.Parent.Toast)
local UiTheme = require(script.Parent.UiTheme)
local Tutorial = require(ReplicatedStorage.Shared.Garden.Tutorial)

local TutorialUI = {}

local STEP_KEYS: { [number]: string } = {
	[Tutorial.Steps.Plant] = "tutorial_plant",
	[Tutorial.Steps.Tend] = "tutorial_tend",
	[Tutorial.Steps.Harvest] = "tutorial_harvest",
	[Tutorial.Steps.Sell] = "tutorial_sell",
	[Tutorial.Steps.Buy] = "tutorial_buy",
}

function TutorialUI.start()
	local lang = Strings.langFromLocale(LocalizationService.RobloxLocaleId)

	local gui = Instance.new("ScreenGui")
	gui.Name = "TutorialBanner"
	gui.ResetOnSpawn = false
	gui.DisplayOrder = 32

	-- Top centre, narrower than the screen so it stays clear of the Roblox menu buttons at the left.
	local banner = Instance.new("Frame")
	banner.AnchorPoint = Vector2.new(0.5, 0)
	banner.Position = UDim2.new(0.5, 0, 0, 8)
	banner.Size = UDim2.new(0.5, 0, 0, 48)
	banner.BackgroundColor3 = Palette.Base.YoruSky
	banner.BackgroundTransparency = 0.15
	banner.Visible = false
	banner.Parent = gui
	local limit = Instance.new("UISizeConstraint")
	limit.MaxSize = Vector2.new(620, 56)
	limit.MinSize = Vector2.new(260, 44)
	limit.Parent = banner
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 12)
	corner.Parent = banner
	local stroke = Instance.new("UIStroke")
	stroke.Color = Palette.Hues.Yuzu.Night
	stroke.Thickness = 2
	stroke.Parent = banner

	local label = Instance.new("TextLabel")
	label.Size = UDim2.new(1, -90, 1, 0)
	label.Position = UDim2.fromOffset(10, 0)
	label.BackgroundTransparency = 1
	label.TextColor3 = Palette.Base.Washi
	label.TextScaled = true
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.Font = Enum.Font.GothamBold
	label.Parent = banner
	local labelPadding = Instance.new("UIPadding")
	labelPadding.PaddingTop = UDim.new(0.16, 0)
	labelPadding.PaddingBottom = UDim.new(0.16, 0)
	labelPadding.Parent = label

	local skip = Instance.new("TextButton")
	skip.AnchorPoint = Vector2.new(1, 0.5)
	skip.Position = UDim2.new(1, -8, 0.5, 0)
	skip.Size = UDim2.fromOffset(72, 34)
	skip.BackgroundColor3 = Palette.Base.Sumi
	skip.TextColor3 = Palette.Base.Washi
	skip.TextScaled = true
	skip.Font = Enum.Font.Gotham
	skip.Text = Strings.get("tutorial_skip", lang)
	skip.Parent = banner
	local skipCorner = Instance.new("UICorner")
	skipCorner.CornerRadius = UDim.new(0, 8)
	skipCorner.Parent = skip
	local skipPadding = Instance.new("UIPadding")
	skipPadding.PaddingTop = UDim.new(0.2, 0)
	skipPadding.PaddingBottom = UDim.new(0.2, 0)
	skipPadding.Parent = skip

	UiTheme.hideDuringRun(gui) -- the banner would cover the judgement text during a run
	gui.Parent = (Players.LocalPlayer :: Player):WaitForChild("PlayerGui")

	skip.Activated:Connect(function()
		GardenState.call("skipTutorial")
	end)

	local previous: number? = nil
	local function render(snapshot: GardenState.Snapshot)
		local step = snapshot.tutorialStep
		banner.Visible = Tutorial.isActive(step)
		if banner.Visible then
			label.Text = Strings.get(STEP_KEYS[step], lang)
		end
		-- Finished by doing the last step (not by skipping).
		if previous == Tutorial.Steps.Buy and step == Tutorial.Done then
			Toast.show(Strings.get("tutorial_done", lang))
		end
		previous = step
	end

	GardenState.onChanged(render)
	local first = GardenState.get()
	if first then
		render(first)
	end
end

return TutorialUI
