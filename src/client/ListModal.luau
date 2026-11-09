--!strict
-- A simple full-screen modal with a title and a scrolling list of big tappable rows.
-- Touch first: rows are at least 56px high. Tapping outside the panel or the X closes it.
-- Prototype look; the final design comes later.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TextService = game:GetService("TextService")
local UserInputService = game:GetService("UserInputService")

local ScrollThumb = require(script.Parent.ScrollThumb)
local UiTheme = require(script.Parent.UiTheme)

local ListModal = {}

export type Row = {
	text: string,
	color: Color3?,
	onTap: (() -> ())?, -- nil = just text
	note: boolean?, -- a long explanation: scaled on its own, and it does not set the common text size
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
	ScrollThumb.attach(list, panel, UDim2.new(1, -6, 0, 68), UDim2.new(0, 5, 1, -84))

	-- Flick / drag scrolling done by hand: the rows are buttons and swallow the touch, so the built-in
	-- scrolling does not start when the finger lands on a row. A drag past a few pixels also cancels the tap.
	list.ScrollingEnabled = false
	local dragging: InputObject? = nil
	local lastY = 0
	local moved = 0
	local velocity = 0
	local function maxScroll(): number
		return math.max(0, list.AbsoluteCanvasSize.Y - list.AbsoluteSize.Y)
	end
	local function scrollBy(dy: number)
		list.CanvasPosition = Vector2.new(0, math.clamp(list.CanvasPosition.Y + dy, 0, maxScroll()))
	end
	-- A drag starts when a press lands on the list or on one of its rows (their own InputBegan events, so no
	-- screen coordinates are compared: the GUI inset would shift those).
	local function beginDrag(input: InputObject)
		local kind = input.UserInputType
		if not gui.Enabled or not (kind == Enum.UserInputType.Touch or kind == Enum.UserInputType.MouseButton1) then
			return
		end
		dragging = input
		lastY = input.Position.Y
		moved = 0
		velocity = 0
	end
	list.InputBegan:Connect(beginDrag)

	UserInputService.InputChanged:Connect(function(input: InputObject)
		if not gui.Enabled then
			return
		end
		if input.UserInputType == Enum.UserInputType.MouseWheel then
			-- mouse wheel and a Mac trackpad's two-finger scroll; the list is the only thing that scrolls here
			scrollBy(-input.Position.Z * 48)
			return
		end
		local active = dragging
		if not active then
			return
		end
		local kind = input.UserInputType
		local isMove = input == active or kind == Enum.UserInputType.MouseMovement or kind == Enum.UserInputType.Touch
		if not isMove then
			return
		end
		local y = (if input == active then active.Position.Y else input.Position.Y)
		local dy = lastY - y
		lastY = y
		moved += math.abs(dy)
		velocity = dy
		scrollBy(dy)
	end)
	UserInputService.InputEnded:Connect(function(input: InputObject)
		local kind = input.UserInputType
		if
			dragging
			and (input == dragging or kind == Enum.UserInputType.MouseButton1 or kind == Enum.UserInputType.Touch)
		then
			dragging = nil
		end
	end)
	-- a flick keeps rolling and slows down
	RunService.Heartbeat:Connect(function()
		if dragging == nil and math.abs(velocity) > 0.4 then
			scrollBy(velocity)
			velocity *= 0.93
		end
	end)

	local modal: Modal

	-- All rows share one text size: the biggest size at which the longest row still fits on one line.
	-- (TextScaled would give every row its own size, so a short name would look bigger than a long one.)
	local rowButtons: { { button: TextButton, text: string, note: boolean } } = {}
	local function applyTextSize()
		local width = (if list.AbsoluteSize.X > 40 then list.AbsoluteSize.X else 480) - 8 - 28 - 12
		local best = 26
		for _, row in rowButtons do
			if row.note then
				continue
			end
			local size = best
			while size > 12 do
				local bounds = TextService:GetTextSize(row.text, size, row.button.Font, Vector2.new(width, math.huge))
				if bounds.Y <= size * 1.4 then
					break
				end
				size -= 1
			end
			best = math.min(best, size)
		end
		for _, row in rowButtons do
			if row.note then
				row.button.TextScaled = true
			else
				row.button.TextScaled = false
				row.button.TextSize = best
			end
		end
	end

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
			task.defer(applyTextSize) -- the list has its real size once it is shown
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
			table.clear(rowButtons)
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
				-- The padding comes first: the glass frame behind the text is stretched to make up for it.
				make("UIPadding", {
					PaddingTop = UDim.new(0.22, 0),
					PaddingBottom = UDim.new(0.22, 0),
					PaddingLeft = UDim.new(0, 14),
					PaddingRight = UDim.new(0, 14),
				}, button)
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
				button.InputBegan:Connect(beginDrag)
				table.insert(rowButtons, { button = button, text = row.text, note = row.note == true })
				local onTap = row.onTap
				if onTap then
					button.Activated:Connect(function()
						if moved < 10 then -- a drag is a scroll, not a tap
							onTap()
						end
					end)
				end
			end
			applyTextSize()
		end,
	}

	gui.Parent = (Players.LocalPlayer :: Player):WaitForChild("PlayerGui")
	return modal
end

return ListModal
