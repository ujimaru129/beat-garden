--!strict
-- Touch-first difficulty picker: three large buttons at the bottom of the screen.
-- Prototype stand-in for the real "Tend" flow (pick a difficulty, then the run starts).
-- Keyboard shortcuts (1 / 2 / 3) are only a convenience on top of this.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Difficulty = require(ReplicatedStorage.Shared.Difficulty)
local UiTheme = require(script.Parent.UiTheme)

local DifficultyPicker = {}

export type Picker = {
	setVisible: (visible: boolean) -> (),
	setTitle: (text: string, subtitle: string?) -> (), -- the chosen song and a small line under it
}

local HUES: { [string]: string } = { Easy = "Matcha", Normal = "Sora", Hard = "Sakura" }

local function make(className: string, props: { [string]: any }, parent: Instance?): any
	local inst = Instance.new(className)
	for k, v in props do
		(inst :: any)[k] = v
	end
	inst.Parent = parent
	return inst
end

-- `onPick` is called with "Easy" / "Normal" / "Hard" when a button is tapped or clicked.
-- With `onCancel`, a small Cancel button is shown above the row.
function DifficultyPicker.create(onPick: (name: string) -> (), onCancel: (() -> ())?): Picker
	local gui = make("ScreenGui", {
		Name = "DifficultyPicker",
		ResetOnSpawn = false,
		IgnoreGuiInset = true,
		DisplayOrder = 40,
	}, nil) :: ScreenGui

	local row = make("Frame", {
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -18),
		Size = UDim2.new(0.6, 0, 0, 76),
		BackgroundTransparency = 1,
	}, gui)
	make("UISizeConstraint", { MaxSize = Vector2.new(440, 76), MinSize = Vector2.new(300, 76) }, row)
	make("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal,
		Padding = UDim.new(0, 16),
		SortOrder = Enum.SortOrder.LayoutOrder,
	}, row)

	local buttons: { [string]: TextButton } = {}
	for i, name in Difficulty.Names do
		local button = make("TextButton", {
			LayoutOrder = i,
			Size = UDim2.new(1 / 3, -11, 1, 0),
			AutoButtonColor = true,
			Text = name,
			TextScaled = true,
		}, row) :: TextButton
		make("UITextSizeConstraint", { MaxTextSize = 24 }, button)
		buttons[name] = button
		-- Activated fires for touch, mouse click and gamepad select.
		button.Activated:Connect(function()
			onPick(name)
		end)
	end

	local cancelButton: TextButton? = nil
	if onCancel then
		local cancel = make("TextButton", {
			AnchorPoint = Vector2.new(0.5, 1),
			Position = UDim2.new(0.5, 0, 1, -106),
			Size = UDim2.fromOffset(110, 40),
			Text = "Cancel",
			TextScaled = true,
		}, gui) :: TextButton
		make("UITextSizeConstraint", { MaxTextSize = 24 }, cancel)
		cancelButton = cancel
		cancel.Activated:Connect(onCancel)
	end

	-- The chosen song: a glass card above the buttons with the name big and a small line under it.
	local titlePanel = make("Frame", {
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -158),
		Size = UDim2.new(0.6, 0, 0, 64),
	}, gui) :: Frame
	make("UISizeConstraint", { MaxSize = Vector2.new(440, 64), MinSize = Vector2.new(300, 64) }, titlePanel)
	local titleLabel = make("TextLabel", {
		Position = UDim2.fromOffset(16, 7),
		Size = UDim2.new(1, -32, 0, 30),
		BackgroundTransparency = 1,
		Text = "",
		TextScaled = true,
	}, titlePanel) :: TextLabel
	local subLabel = make("TextLabel", {
		Position = UDim2.fromOffset(16, 39),
		Size = UDim2.new(1, -32, 0, 16),
		BackgroundTransparency = 1,
		Text = "",
		TextScaled = true,
	}, titlePanel) :: TextLabel

	-- The look follows the time of day, so it is applied again every time the picker is shown.
	local function restyle()
		local theme = UiTheme.get()
		for name, button in buttons do
			UiTheme.styleButton(button, theme, HUES[name])
		end
		if cancelButton then
			UiTheme.styleButton(cancelButton, theme, "Fuji", 12)
		end
		UiTheme.stylePanel(titlePanel, theme, 18)
		UiTheme.styleText(titleLabel, theme, "head")
		UiTheme.styleText(subLabel, theme, "body")
		subLabel.TextTransparency = 0.25
	end
	restyle()

	gui.Parent = (Players.LocalPlayer :: Player):WaitForChild("PlayerGui")

	return {
		setTitle = function(text: string, subtitle: string?)
			titleLabel.Text = `♪  {text}`
			subLabel.Text = subtitle or ""
		end,
		setVisible = function(visible: boolean)
			if visible then
				restyle()
			end
			gui.Enabled = visible
			UiTheme.setBlur("difficulty", visible)
		end,
	}
end

return DifficultyPicker
