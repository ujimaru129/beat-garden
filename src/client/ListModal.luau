--!strict
-- A full-screen modal with a title and a scrolling list of big tappable rows, drawn as the ranking-style board
-- (BoardCells). A row is either one line of text or a table row (`cells` under `columns`, with an optional head row).
-- The board's colours follow the time of day (BoardCells.refresh): they are worked out again on open and on every
-- redraw of the rows.
-- Touch first: rows are at least 52px high. Tapping outside the panel or the X closes it.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TextService = game:GetService("TextService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local ScrollThumb = require(script.Parent.ScrollThumb)
local BoardCells = require(script.Parent.BoardCells)
local RowIcon = require(script.Parent.RowIcon)
local Lang = require(script.Parent.Lang)
local UiTheme = require(script.Parent.UiTheme)

local ListModal = {}

export type Row = {
	text: string,
	color: Color3?,
	-- nil = just text. May return true (it worked: the row flashes green) or false (it did not: red).
	onTap: (() -> boolean?)?,
	-- A small 3D picture at the left of the row: a spirit (id = its kind) or a plant's fruit (id = the seed, with
	-- the mutation if there is one).
	icon: RowIcon.Icon?,
	-- A table row instead of one line of text: these cells under these columns (BoardCells). With `head`, the
	-- cells are the column names (a dark thin row).
	cells: { BoardCells.Cell }?,
	columns: { BoardCells.Column }?,
	head: boolean?,
	selected: boolean?, -- the chosen one (the equipped spirit ...): drawn lit up with a white frame and a check
	note: boolean?, -- a long explanation: scaled on its own, and it does not set the common text size
}

export type Modal = {
	open: () -> (),
	close: () -> (),
	isOpen: () -> boolean,
	setTitle: (title: string) -> (),
	setRows: (rows: { Row }) -> (),
	-- A fixed area under the title that does not scroll (the Park's lots). Fill `header`, then give it its height
	-- (0 = none): the list moves down to make room.
	header: Frame,
	setHeaderHeight: (height: number) -> (),
	-- Thinner rows and smaller text, for a long list that is scrolled a lot (the Park's items).
	setCompact: (on: boolean) -> (),
}

local ROW_HEIGHT = 52
local ICON_ROW_HEIGHT = 66 -- a row with a spirit at its left
local ICON_SPACE = 62 -- width the picture takes at the left of the text
local NOTE_MIN_HEIGHT = 34
local MAX_TEXT = 26
local MIN_TEXT = 18 -- smaller than this is hard to read on a phone: longer rows wrap instead
local NOTE_TEXT = 17
local COMPACT_TABLE_ROW = 42 -- a table row in a compact list (the Park's items)

local function make(className: string, props: { [string]: any }, parent: Instance?): any
	local inst = Instance.new(className)
	for k, v in props do
		(inst :: any)[k] = v
	end
	inst.Parent = parent
	return inst
end

-- A small 3D picture at the left of a text row (RowIcon). Only the pictures on screen are drawn (showVisibleIcons).
local function makeIcon(icon: RowIcon.Icon, lit: boolean): ViewportFrame
	local viewport = BoardCells.icon(icon, lit, ICON_SPACE - 8)
	viewport.AnchorPoint = Vector2.new(0, 0.5)
	-- The row's padding pushes children in: this puts the picture at the row's left edge, centred.
	viewport.Position = UDim2.new(0, -(14 + ICON_SPACE) + 8, 0.5, 0)
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
		Position = UDim2.fromScale(0.5, 0.57),
		Size = UDim2.fromScale(0.92, 0.8),
		Active = true, -- swallow taps so they do not reach the backdrop
	}, backdrop) :: Frame
	make("UISizeConstraint", { MaxSize = Vector2.new(780, 470) }, panel)

	local titleLabel = make("TextLabel", {
		Position = UDim2.fromOffset(16, 10),
		Size = UDim2.new(1, -80, 0, 38),
		BackgroundTransparency = 1,
		Text = Lang.t(title),
		TextScaled = true,
		TextXAlignment = Enum.TextXAlignment.Left,
	}, panel) :: TextLabel

	local closeButton = BoardCells.closeButton(panel)
	closeButton.Position = UDim2.new(1, -10, 0, 10)

	-- The look follows the time of day, so it is applied again every time the modal opens or redraws its rows.
	local currentTheme = UiTheme.get()
	local function restyle()
		currentTheme = BoardCells.refresh()
		BoardCells.styleBoard(panel)
		BoardCells.styleClose(closeButton)
		titleLabel.Font = currentTheme.head
		titleLabel.TextColor3 = BoardCells.Text
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
	make("UIListLayout", { Padding = UDim.new(0, BoardCells.Gap), SortOrder = Enum.SortOrder.LayoutOrder }, list)
	ScrollThumb.attach(list, panel, UDim2.new(1, -6, 0, 68), UDim2.new(0, 5, 1, -84))

	local header = make("Frame", {
		Name = "Header",
		Position = UDim2.fromOffset(12, 60),
		Size = UDim2.new(1, -24, 0, 0),
		BackgroundTransparency = 1,
		Visible = false,
	}, panel) :: Frame
	local function setHeaderHeight(height: number)
		header.Size = UDim2.new(1, -24, 0, height)
		header.Visible = height > 0
		local gap = if height > 0 then height + 6 else 0
		list.Position = UDim2.fromOffset(12, 64 + gap)
		list.Size = UDim2.new(1, -24, 1, -76 - gap)
		local track = panel:FindFirstChild("ScrollTrack")
		if track and track:IsA("GuiObject") then
			track.Position = UDim2.new(1, -6, 0, 68 + gap)
			track.Size = UDim2.new(0, 5, 1, -84 - gap)
		end
	end

	-- Flick / drag scrolling done by hand: the rows are buttons and swallow the touch, so the built-in
	-- scrolling does not start when the finger lands on a row. A drag past a few pixels also cancels the tap.
	list.ScrollingEnabled = false
	local dragging: InputObject? = nil
	local lastY = 0
	local moved = 0
	local velocity = 0
	local lastDragEnd = 0
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
			lastDragEnd = os.clock()
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

	local rowHeight, maxText, minText, noteText, noteMin = ROW_HEIGHT, MAX_TEXT, MIN_TEXT, NOTE_TEXT, NOTE_MIN_HEIGHT
	local compact = false
	local layout = list:FindFirstChildOfClass("UIListLayout")
	local function setCompact(on: boolean)
		compact = on
		rowHeight = if on then 36 else ROW_HEIGHT
		maxText = if on then 20 else MAX_TEXT
		minText = if on then 14 else MIN_TEXT
		noteText = if on then 14 else NOTE_TEXT
		noteMin = if on then 24 else NOTE_MIN_HEIGHT
		if layout then
			layout.Padding = UDim.new(0, if on then 3 else BoardCells.Gap)
		end
	end

	-- All rows share one text size: the biggest size at which the longest row still fits on one line, but never
	-- smaller than MIN_TEXT. A row that is still too long wraps onto a second line and its row grows to fit.
	-- (TextScaled would give every row its own size, so a short name would look bigger than a long one.)
	-- `fixed` rows (table rows) keep their own height and text sizes.
	local rowButtons: {
		{
			button: TextButton,
			text: string,
			note: boolean,
			icon: ViewportFrame?,
			icons: { ViewportFrame },
			fixed: boolean,
		}
	} =
		{}
	-- The server answers a tap and also pushes the new state, which rebuilds the list: the flash must land on the
	-- row that is there after the rebuild, whichever of the two comes first.
	local pendingFlash: { index: number, color: Color3, expires: number }? = nil
	local function applyTextSize()
		local width = (if list.AbsoluteSize.X > 40 then list.AbsoluteSize.X else 480) - 8 - 28 - 12
		local best = maxText
		for _, row in rowButtons do
			if row.note or row.fixed then
				continue
			end
			local size = best
			local rowWidth = width - (if row.icon then ICON_SPACE else 0)
			while size > minText do
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
			if row.fixed then
				continue
			end
			local size = if row.note then noteText else best
			row.button.TextScaled = false
			row.button.TextWrapped = true
			row.button.TextSize = size
			-- The text area is the row minus the padding above and below (22% each).
			local rowWidth = width - (if row.icon then ICON_SPACE else 0)
			local bounds = TextService:GetTextSize(row.text, size, row.button.Font, Vector2.new(rowWidth, math.huge))
			local height = math.ceil(bounds.Y / 0.56)
			local minimum = if row.note then noteMin elseif row.icon then ICON_ROW_HEIGHT else rowHeight
			row.button.Size = UDim2.new(1, -8, 0, math.max(minimum, height))
		end
	end

	-- Only the pictures of rows that are on screen are drawn.
	local function showVisibleIcons()
		local top = list.AbsolutePosition.Y - 60
		local bottom = list.AbsolutePosition.Y + list.AbsoluteSize.Y + 60
		for _, row in rowButtons do
			local y = row.button.AbsolutePosition.Y
			local onScreen = y + row.button.AbsoluteSize.Y >= top and y <= bottom
			for _, icon in row.icons do
				icon.Visible = onScreen
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

	-- A scroll must never close the list: ignore the backdrop while a press is dragging, or just after one
	-- (a finger that slides off the panel and lifts over the dim area is not a tap outside).
	backdrop.Activated:Connect(function()
		if dragging ~= nil or os.clock() - lastDragEnd < 0.5 then
			return
		end
		close()
	end)
	closeButton.Activated:Connect(close)

	modal = {
		open = function()
			restyle()
			list.CanvasPosition = Vector2.zero -- always from the top: the first rows say what is equipped / placed
			gui.Enabled = true
			UiTheme.setBlur("list", true)
			task.defer(function()
				applyTextSize()
				showVisibleIcons()
			end) -- the list has its real size once it is shown
		end,
		close = close,
		header = header,
		setHeaderHeight = setHeaderHeight,
		setCompact = setCompact,
		isOpen = function()
			return gui.Enabled
		end,
		setTitle = function(text: string)
			local translated = Lang.t(text)
			-- Another view starts at its top. A title that only changes its numbers (the Shop's coins and
			-- countdown tick every second) is the same view: the scroll position stays.
			if string.match(titleLabel.Text, "^[^%d%s]*") ~= string.match(translated, "^[^%d%s]*") then
				list.CanvasPosition = Vector2.zero
			end
			titleLabel.Text = translated
		end,
		setRows = function(rows: { Row })
			restyle() -- the time of day may have changed since the modal was created
			for _, child in list:GetChildren() do
				if child:IsA("GuiObject") then
					child:Destroy()
				end
			end
			table.clear(rowButtons)
			local stripe = 0 -- table rows alternate their colour, like the ranking
			for i, row in rows do
				local tappable = row.onTap ~= nil
				local cells, columns = row.cells, row.columns
				local button = make("TextButton", {
					LayoutOrder = i,
					Size = UDim2.new(1, -8, 0, rowHeight),
					AutoButtonColor = tappable,
					Active = tappable,
					Text = if cells then "" else Lang.t(row.text),
					TextScaled = true,
					TextXAlignment = Enum.TextXAlignment.Left,
					BorderSizePixel = 0,
					Font = currentTheme.head,
					TextColor3 = BoardCells.Text,
				}, list) :: TextButton
				local icons: { ViewportFrame } = {}
				if cells and columns then
					-- a table row: fixed height, the cells drawn by BoardCells
					local head = row.head == true
					stripe = if head then 0 else stripe + 1
					button.Size = UDim2.new(
						1,
						-8,
						0,
						if head then 26 elseif compact then COMPACT_TABLE_ROW else BoardCells.RowHeight
					)
					button.BackgroundColor3 = if head
						then BoardCells.HeadRow
						elseif row.selected then BoardCells.RowLit
						elseif stripe % 2 == 0 then BoardCells.RowAlt
						else BoardCells.Row
					BoardCells.corner(button, if head then 6 else 8)
					if row.selected and not head then
						make("UIStroke", {
							Name = "RowAccent",
							Color = BoardCells.Gold,
							Thickness = 2,
							ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
						}, button)
					end
					local frames = BoardCells.columnFrames(button, columns)
					for c, column in columns do
						local cell = cells[c]
						if not cell then
							continue
						end
						if head then
							BoardCells.headLabel(frames[c], Lang.t(cell.text or ""), column)
						else
							BoardCells.drawCell(frames[c], cell, column, row.selected == true)
							local picture = frames[c]:FindFirstChildOfClass("ViewportFrame")
							if picture then
								table.insert(icons, picture)
							end
						end
					end
				else
					-- The padding comes first: the frame behind the text is stretched to make up for it.
					make("UIPadding", {
						PaddingTop = UDim.new(0.22, 0),
						PaddingBottom = UDim.new(0.22, 0),
						PaddingLeft = UDim.new(0, if row.icon then 14 + ICON_SPACE else 14),
						PaddingRight = UDim.new(0, 14),
					}, button)
					if tappable then
						-- a tappable row: a board row with a coloured rim (green = you can buy it, grey = you
						-- cannot ...); the chosen one is lit with a gold rim
						button.BackgroundColor3 = if row.selected then BoardCells.RowLit else BoardCells.Row
						BoardCells.corner(button, 8)
						if row.color or row.selected then
							make("UIStroke", {
								Name = "RowAccent",
								Color = if row.selected then BoardCells.Gold else BoardCells.rim(row.color :: Color3),
								Thickness = if row.selected then 3 else 2,
								ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
							}, button)
						end
					else
						-- quiet text: a note or a line of information
						button.BackgroundTransparency = 1
						button.Font = currentTheme.body
						-- a row's own colour is a hue: neon at night, made darker by day so it reads on the board
						button.TextColor3 = if row.note
							then BoardCells.SubText
							elseif row.color then BoardCells.ink(row.color)
							else BoardCells.Text
					end
					button.TextXAlignment = Enum.TextXAlignment.Left
				end
				button.InputBegan:Connect(beginDrag)
				local icon: ViewportFrame? = nil
				if row.icon and not cells then
					icon = makeIcon(row.icon, row.selected == true)
					icon.Parent = button
					table.insert(icons, icon :: ViewportFrame)
				end
				table.insert(rowButtons, {
					button = button,
					text = Lang.t(row.text),
					note = row.note == true,
					icon = icon,
					icons = icons,
					fixed = cells ~= nil,
				})
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
