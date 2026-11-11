--!strict
-- A simple full-screen modal with a title and a scrolling list of big tappable rows.
-- Touch first: rows are at least 56px high. Tapping outside the panel or the X closes it.
-- Prototype look; the final design comes later.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TextService = game:GetService("TextService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local ScrollThumb = require(script.Parent.ScrollThumb)
local SpiritModel = require(script.Parent.SpiritModel)
local Lang = require(script.Parent.Lang)
local UiTheme = require(script.Parent.UiTheme)

local ListModal = {}

export type Row = {
	text: string,
	color: Color3?,
	-- nil = just text. May return true (it worked: the row flashes green) or false (it did not: red).
	onTap: (() -> boolean?)?,
	spiritKind: string?, -- draws this spirit (3D) at the left of the row
	selected: boolean?, -- the chosen one (the equipped spirit ...): drawn lit up with a white frame and a check
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
local ICON_ROW_HEIGHT = 66 -- a row with a spirit at its left
local ICON_SPACE = 62 -- width the picture takes at the left of the text
local NOTE_MIN_HEIGHT = 34
local MAX_TEXT = 26
local MIN_TEXT = 18 -- smaller than this is hard to read on a phone: longer rows wrap instead
local NOTE_TEXT = 17

local function make(className: string, props: { [string]: any }, parent: Instance?): any
	local inst = Instance.new(className)
	for k, v in props do
		(inst :: any)[k] = v
	end
	inst.Parent = parent
	return inst
end

-- A small 3D picture of a spirit for the left of a row. A ViewportFrame is the costly kind of picture, so the list
-- only shows the ones that are on screen (see showVisibleIcons).
local function makeSpiritIcon(kind: string, lit: boolean): ViewportFrame
	local viewport = Instance.new("ViewportFrame")
	viewport.Name = "SpiritIcon"
	viewport.AnchorPoint = Vector2.new(0, 0.5)
	-- The row's padding pushes children in: this puts the picture at the row's left edge, centred.
	viewport.Position = UDim2.new(0, -(14 + ICON_SPACE) + 8, 0.5, 0)
	viewport.Size = UDim2.fromOffset(ICON_SPACE - 8, ICON_SPACE - 8)
	viewport.BackgroundTransparency = if lit then 0.55 else 0.8
	viewport.BackgroundColor3 = Color3.new(1, 1, 1)
	viewport.Ambient = Color3.fromRGB(190, 190, 205)
	viewport.LightColor = Color3.new(1, 1, 1)
	viewport.LightDirection = Vector3.new(-0.4, -1, -0.6)
	viewport.ZIndex = 6
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0.5, 0)
	corner.Parent = viewport
	local model = SpiritModel.create(kind)
	model.Parent = viewport
	local camera = Instance.new("Camera")
	camera.FieldOfView = 30
	camera.CFrame = CFrame.lookAt(Vector3.new(0, 1.9, -7.2), Vector3.new(0, 1.65, 0))
	camera.Parent = viewport
	viewport.CurrentCamera = camera
	return viewport
end

-- A coloured flash over a row (the result of tapping it), and a quick squash when it is pressed.
local function flash(button: TextButton, color: Color3)
	if not button.Parent then
		return
	end
	local overlay = Instance.new("Frame")
	overlay.Name = "Flash"
	overlay.Size = UDim2.fromScale(1, 1)
	overlay.BackgroundColor3 = color
	overlay.BackgroundTransparency = 0.1
	overlay.BorderSizePixel = 0
	overlay.ZIndex = 20
	overlay.Active = false
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 12)
	corner.Parent = overlay
	-- The glass frame behind the text covers the whole row (the button itself has padding).
	overlay.Parent = button:FindFirstChild("ThemeBg") or button
	TweenService:Create(overlay, TweenInfo.new(0.7, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		BackgroundTransparency = 1,
	}):Play()
	task.delay(0.75, function()
		overlay:Destroy()
	end)
end

local function squash(button: TextButton)
	local scale = button:FindFirstChildOfClass("UIScale")
	if not scale then
		scale = Instance.new("UIScale")
		scale.Parent = button
	end
	local uiScale = scale :: UIScale
	uiScale.Scale = 0.94
	TweenService:Create(uiScale, TweenInfo.new(0.25, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 })
		:Play()
end

local FLASH_OK = Color3.fromRGB(110, 255, 170)
local FLASH_FAIL = Color3.fromRGB(255, 110, 110)

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
		Text = Lang.t(title),
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

	-- All rows share one text size: the biggest size at which the longest row still fits on one line, but never
	-- smaller than MIN_TEXT. A row that is still too long wraps onto a second line and its row grows to fit.
	-- (TextScaled would give every row its own size, so a short name would look bigger than a long one.)
	local rowButtons: { { button: TextButton, text: string, note: boolean, icon: ViewportFrame? } } = {}
	-- The server answers a tap and also pushes the new state, which rebuilds the list: the flash must land on the
	-- row that is there after the rebuild, whichever of the two comes first.
	local pendingFlash: { index: number, color: Color3, expires: number }? = nil
	local function applyTextSize()
		local width = (if list.AbsoluteSize.X > 40 then list.AbsoluteSize.X else 480) - 8 - 28 - 12
		local best = MAX_TEXT
		for _, row in rowButtons do
			if row.note then
				continue
			end
			local size = best
			local rowWidth = width - (if row.icon then ICON_SPACE else 0)
			while size > MIN_TEXT do
				local bounds =
					TextService:GetTextSize(row.text, size, row.button.Font, Vector2.new(rowWidth, math.huge))
				if bounds.Y <= size * 1.4 then
					break
				end
				size -= 1
			end
			best = math.min(best, size)
		end
		for _, row in rowButtons do
			local size = if row.note then NOTE_TEXT else best
			row.button.TextScaled = false
			row.button.TextWrapped = true
			row.button.TextSize = size
			-- The text area is the row minus the padding above and below (22% each).
			local rowWidth = width - (if row.icon then ICON_SPACE else 0)
			local bounds = TextService:GetTextSize(row.text, size, row.button.Font, Vector2.new(rowWidth, math.huge))
			local height = math.ceil(bounds.Y / 0.56)
			local minimum = if row.note then NOTE_MIN_HEIGHT elseif row.icon then ICON_ROW_HEIGHT else ROW_HEIGHT
			row.button.Size = UDim2.new(1, -8, 0, math.max(minimum, height))
		end
	end

	-- Only the pictures of rows that are on screen are drawn.
	local function showVisibleIcons()
		local top = list.AbsolutePosition.Y - 60
		local bottom = list.AbsolutePosition.Y + list.AbsoluteSize.Y + 60
		for _, row in rowButtons do
			local icon = row.icon
			if icon then
				local y = row.button.AbsolutePosition.Y
				icon.Visible = y + row.button.AbsoluteSize.Y >= top and y <= bottom
			end
		end
	end
	list:GetPropertyChangedSignal("CanvasPosition"):Connect(showVisibleIcons)

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
			task.defer(function()
				applyTextSize()
				showVisibleIcons()
			end) -- the list has its real size once it is shown
		end,
		close = close,
		isOpen = function()
			return gui.Enabled
		end,
		setTitle = function(text: string)
			titleLabel.Text = Lang.t(text)
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
					Text = Lang.t(row.text),
					TextScaled = true,
					TextXAlignment = Enum.TextXAlignment.Left,
				}, list) :: TextButton
				-- The padding comes first: the glass frame behind the text is stretched to make up for it.
				make("UIPadding", {
					PaddingTop = UDim.new(0.22, 0),
					PaddingBottom = UDim.new(0.22, 0),
					PaddingLeft = UDim.new(0, if row.spiritKind then 14 + ICON_SPACE else 14),
					PaddingRight = UDim.new(0, 14),
				}, button)
				-- Rows that cannot be tapped are quiet text; tappable ones are neon / candy buttons.
				if tappable then
					UiTheme.styleButton(button, currentTheme, if row.selected then "Matcha" else "Sora", 12, false)
				else
					button.BackgroundTransparency = 1
					UiTheme.styleText(button, currentTheme, "body")
				end
				button.TextXAlignment = Enum.TextXAlignment.Left
				if row.color and currentTheme.night then
					button.TextColor3 = row.color
				end
				-- A frame in the row's colour (green = you can buy it, grey = you cannot ...), day and night.
				if tappable and (row.color or row.selected) then
					make("UIStroke", {
						Name = "RowAccent",
						Color = if row.selected then Color3.new(1, 1, 1) else row.color,
						Thickness = if row.selected then 4 else 2.5,
						ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
					}, button)
				end
				button.InputBegan:Connect(beginDrag)
				local icon: ViewportFrame? = nil
				if row.spiritKind then
					icon = makeSpiritIcon(row.spiritKind, row.selected == true)
					icon.Parent = button
				end
				table.insert(
					rowButtons,
					{ button = button, text = Lang.t(row.text), note = row.note == true, icon = icon }
				)
				local onTap = row.onTap
				if onTap then
					button.Activated:Connect(function()
						if moved < 10 then -- a drag is a scroll, not a tap
							squash(button)
							local ok = onTap()
							-- the list may have been rebuilt meanwhile: flash the row that is there now
							if ok ~= nil then
								local color = if ok then FLASH_OK else FLASH_FAIL
								pendingFlash = { index = i, color = color, expires = os.clock() + 1.2 }
								local current = rowButtons[i]
								if current then
									flash(current.button, color)
								end
							end
						end
					end)
				end
			end
			applyTextSize()
			task.defer(showVisibleIcons)
			local pending = pendingFlash
			if pending and os.clock() < pending.expires then
				local target = rowButtons[pending.index]
				if target then
					pendingFlash = nil
					flash(target.button, pending.color)
				end
			end
		end,
	}

	gui.Parent = (Players.LocalPlayer :: Player):WaitForChild("PlayerGui")
	return modal
end

return ListModal
