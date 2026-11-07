--!strict
-- A simple full-screen modal with a title and a scrolling list of big tappable rows.
-- Touch first: rows are at least 56px high. Tapping outside the panel or the X closes it.
-- Prototype look; the final design comes later.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Palette = require(ReplicatedStorage.Shared.Palette)

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
		BackgroundColor3 = Palette.Base.YoruSky,
		Active = true, -- swallow taps so they do not reach the backdrop
	}, backdrop) :: Frame
	make("UISizeConstraint", { MaxSize = Vector2.new(560, 440) }, panel)
	make("UICorner", { CornerRadius = UDim.new(0, 16) }, panel)

	local titleLabel = make("TextLabel", {
		Position = UDim2.fromOffset(16, 8),
		Size = UDim2.new(1, -80, 0, 44),
		BackgroundTransparency = 1,
		Text = title,
		TextColor3 = Palette.Base.Washi,
		TextScaled = true,
		TextXAlignment = Enum.TextXAlignment.Left,
		Font = Enum.Font.GothamBlack,
	}, panel) :: TextLabel

	local closeButton = make("TextButton", {
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -10, 0, 8),
		Size = UDim2.fromOffset(48, 48),
		BackgroundColor3 = Palette.Base.Sumi,
		Text = "X",
		TextColor3 = Palette.Base.Washi,
		TextScaled = true,
		Font = Enum.Font.GothamBlack,
	}, panel) :: TextButton
	make("UICorner", { CornerRadius = UDim.new(1, 0) }, closeButton)
	make("UIPadding", { PaddingTop = UDim.new(0.25, 0), PaddingBottom = UDim.new(0.25, 0) }, closeButton)

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
		if onClose then
			onClose()
		end
	end

	backdrop.Activated:Connect(close)
	closeButton.Activated:Connect(close)

	modal = {
		open = function()
			gui.Enabled = true
		end,
		close = close,
		isOpen = function()
			return gui.Enabled
		end,
		setTitle = function(text: string)
			titleLabel.Text = text
		end,
		setRows = function(rows: { Row })
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
					BackgroundColor3 = row.color
						or (if tappable then Palette.Hues.Sora.Night else Palette.Base.YoruGround),
					BackgroundTransparency = if tappable then 0.2 else 0.3,
					AutoButtonColor = tappable,
					Active = tappable,
					Text = row.text,
					TextColor3 = if tappable then Palette.Base.YoruSky else Palette.Base.Washi,
					TextScaled = true,
					Font = if tappable then Enum.Font.GothamBold else Enum.Font.Gotham,
					TextXAlignment = Enum.TextXAlignment.Left,
				}, list) :: TextButton
				make("UICorner", { CornerRadius = UDim.new(0, 12) }, button)
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
