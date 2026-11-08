--!strict
-- A simple full-screen modal with a title and a scrolling list of big tappable rows.
-- Touch first: rows are at least 56px high. Tapping outside the panel or the X closes it.
-- Prototype look; the final design comes later.

local Players = game:GetService("Players")

local UiTheme = require(script.Parent.UiTheme)

local ListModal = {}

export type Row = {
	text: string,
	color: Color3?,
	onTap: (() -> ())?, -- nil = just text
}

export type Modal = {
	open: () -> (),
	close: () -> (),
	isOpen: () -> boolean,
	setTitle: (title: string) -> (),
	setRows: (rows: { Row }) -> (),
}

local ROW_HEIGHT = 52

local function make(className: string, props: { [string]: any }, parent: Instance?): any
	local inst = Instance.new(className)
	for k, v in props do
		(inst :: any)[k] = v
	end
	inst.Parent = parent
	return inst
end

-- `onClose` runs whenever the modal closes (tap outside, X, or close()).
function ListModal.create(title: string, onClose: (() -> ())?): Modal
	local gui = make("ScreenGui", {
		Name = "ListModal",
		ResetOnSpawn = false,
		IgnoreGuiInset = true,
		DisplayOrder = 55,
		Enabled = false,
	}, nil) :: ScreenGui

	local backdrop = make("TextButton", {
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Color3.new(0, 0, 0),
		BackgroundTransparency = 0.45,
		AutoButtonColor = false,
		Text = "",
	}, gui) :: TextButton

	local panel = make("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		-- Lower than centre: the Roblox menu buttons sit in the top-left corner and cover anything there.
		Position = UDim2.fromScale(0.5, 0.6),
		Size = UDim2.fromScale(0.8, 0.7),
		Active = true, -- swallow taps so they do not reach the backdrop
	}, backdrop) :: Frame
	make("UISizeConstraint", { MaxSize = Vector2.new(560, 440) }, panel)

	local titleLabel = make("TextLabel", {
		Position = UDim2.fromOffset(16, 8),
		Size = UDim2.new(1, -80, 0, 44),
		BackgroundTransparency = 1,
		Text = title,
		TextScaled = true,
		TextXAlignment = Enum.TextXAlignment.Left,
	}, panel) :: TextLabel

	local closeButton = make("TextButton", {
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -10, 0, 8),
		Size = UDim2.fromOffset(48, 48),
		Text = "X",
		TextScaled = true,
	}, panel) :: TextButton
	make("UITextSizeConstraint", { MaxTextSize = 24 }, closeButton)

	-- The look follows the time of day, so it is applied again every time the modal opens.
	local currentTheme = UiTheme.get()
	local function restyle()
		currentTheme = UiTheme.get()
		UiTheme.stylePanel(panel, currentTheme, 18)
		UiTheme.styleText(titleLabel, currentTheme, "head")
		UiTheme.styleButton(closeButton, currentTheme, "Sakura", 24)
	end
	restyle()

	local list = make("ScrollingFrame", {
		Position = UDim2.fromOffset(12, 64),
		Size = UDim2.new(1, -24, 1, -76),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ScrollBarThickness = 6,
		CanvasSize = UDim2.new(),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
	}, panel) :: ScrollingFrame
	make("UIListLayout", { Padding = UDim.new(0, 8), SortOrder = Enum.SortOrder.LayoutOrder }, list)

	local modal: Modal

	local function close()
		if not gui.Enabled then
			return
		end
		gui.Enabled = false
		UiTheme.setBlur("list", false)
		if onClose then
			onClose()
		end
	end

	backdrop.Activated:Connect(close)
	closeButton.Activated:Connect(close)

	modal = {
		open = function()
			restyle()
			gui.Enabled = true
			UiTheme.setBlur("list", true)
		end,
		close = close,
		isOpen = function()
			return gui.Enabled
		end,
		setTitle = function(text: string)
			titleLabel.Text = text
		end,
		setRows = function(rows: { Row })
			currentTheme = UiTheme.get() -- the time of day may have changed since the modal was created
			for _, child in list:GetChildren() do
				if child:IsA("GuiObject") then
					child:Destroy()
				end
			end
			for i, row in rows do
				local tappable = row.onTap ~= nil
				local button = make("TextButton", {
					LayoutOrder = i,
					Size = UDim2.new(1, -8, 0, ROW_HEIGHT),
					AutoButtonColor = tappable,
					Active = tappable,
					Text = row.text,
					TextScaled = true,
					TextXAlignment = Enum.TextXAlignment.Left,
				}, list) :: TextButton
				-- Rows that cannot be tapped are quiet text; tappable ones are neon / candy buttons.
				if tappable then
					UiTheme.styleButton(button, currentTheme, "Sora", 12, false)
				else
					button.BackgroundTransparency = 1
					UiTheme.styleText(button, currentTheme, "body")
				end
				button.TextXAlignment = Enum.TextXAlignment.Left
				if row.color and currentTheme.night then
					button.TextColor3 = row.color
				end
				make("UIPadding", {
					PaddingTop = UDim.new(0.22, 0),
					PaddingBottom = UDim.new(0.22, 0),
					PaddingLeft = UDim.new(0, 14),
					PaddingRight = UDim.new(0, 14),
				}, button)
				local onTap = row.onTap
				if onTap then
					button.Activated:Connect(onTap)
				end
			end
		end,
	}

	gui.Parent = (Players.LocalPlayer :: Player):WaitForChild("PlayerGui")
	return modal
end

return ListModal
