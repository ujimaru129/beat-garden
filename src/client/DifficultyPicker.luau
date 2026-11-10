--!strict
-- Touch-first difficulty picker: three large buttons at the bottom of the screen.
-- Prototype stand-in for the real "Tend" flow (pick a difficulty, then the run starts).
-- Keyboard shortcuts (1 / 2 / 3) are only a convenience on top of this.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Difficulty = require(ReplicatedStorage.Shared.Difficulty)
local Palette = require(ReplicatedStorage.Shared.Palette)

local DifficultyPicker = {}

export type Picker = {
	setVisible: (visible: boolean) -> (),
}

local COLORS: { [string]: Color3 } = {
	Easy = Palette.Hues.Matcha.Night,
	Normal = Palette.Hues.Sora.Night,
	Hard = Palette.Hues.Sakura.Night,
}

local function make(className: string, props: { [string]: any }, parent: Instance?): any
	local inst = Instance.new(className)
	for k, v in props do
		(inst :: any)[k] = v
	end
	inst.Parent = parent
	return inst
end

-- `onPick` is called with "Easy" / "Normal" / "Hard" when a button is tapped or clicked.
function DifficultyPicker.create(onPick: (name: string) -> ()): Picker
	local gui = make("ScreenGui", {
		Name = "DifficultyPicker",
		ResetOnSpawn = false,
		IgnoreGuiInset = true,
		DisplayOrder = 40,
	}, nil) :: ScreenGui

	local row = make("Frame", {
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.fromScale(0.5, 0.96),
		Size = UDim2.fromScale(0.9, 0.18),
		BackgroundTransparency = 1,
	}, gui)
	make("UISizeConstraint", { MaxSize = Vector2.new(560, 140), MinSize = Vector2.new(0, 72) }, row)
	make("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal,
		Padding = UDim.new(0, 10),
		SortOrder = Enum.SortOrder.LayoutOrder,
	}, row)

	for i, name in Difficulty.Names do
		local button = make("TextButton", {
			LayoutOrder = i,
			Size = UDim2.new(1 / 3, -7, 1, 0),
			BackgroundColor3 = COLORS[name],
			BackgroundTransparency = 0.15,
			AutoButtonColor = true,
			Text = name,
			TextColor3 = Palette.Base.YoruSky,
			TextScaled = true,
			Font = Enum.Font.GothamBlack,
		}, row) :: TextButton
		make("UICorner", { CornerRadius = UDim.new(0, 14) }, button)
		make("UIPadding", {
			PaddingTop = UDim.new(0.25, 0),
			PaddingBottom = UDim.new(0.25, 0),
			PaddingLeft = UDim.new(0.08, 0),
			PaddingRight = UDim.new(0.08, 0),
		}, button)
		-- Activated fires for touch, mouse click and gamepad select.
		button.Activated:Connect(function()
			onPick(name)
		end)
	end

	gui.Parent = (Players.LocalPlayer :: Player):WaitForChild("PlayerGui")

	return {
		setVisible = function(visible: boolean)
			gui.Enabled = visible
		end,
	}
end

return DifficultyPicker
