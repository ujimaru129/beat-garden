--!strict
-- The pieces of the ranking-style table menus, shared by BoardUI and ListModal: the colours, table columns and the
-- cells of a row (text, text with a second line, a pill, a 3D picture). Ported from FLOREN WORLD's board look.
--
-- The colours are Beat Garden's own and follow the time of day like the rest of the UI: they are worked out from
-- UiTheme / Palette in `refresh()`, which the menus call every time they open or redraw their rows.
--   Night (neon): a deep violet board, near-black head row, violet rows, white text, sky-blue sub text.
--   Day (pastel): a white-to-pink board, a dark plum head row, white / lilac rows, navy text, violet sub text.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Palette = require(ReplicatedStorage.Shared.Palette)
local RowIcon = require(script.Parent.RowIcon)
local UiTheme = require(script.Parent.UiTheme)

local BoardCells = {}

export type Align = "left" | "center" | "right"

export type Column = {
	title: string, -- English; shown through Lang.t ("" = none)
	width: number?, -- fixed pixels
	flex: number?, -- or a share of what is left
	align: Align?,
}

-- One cell: plain text, text with a small second line, a coloured pill, or a 3D picture (RowIcon).
export type Cell = {
	text: string?,
	sub: string?, -- a small second line under the text
	color: Color3?,
	bold: boolean?,
	pill: Color3?, -- draw the text on a rounded pill of this colour (BoardCells.pill(hue))
	dim: boolean?, -- greyed out (not found yet, cannot buy ...)
	icon: RowIcon.Icon?,
	onTap: (() -> ())?, -- a cell of its own to tap (a grid of choices), instead of the whole row
}

BoardCells.RowHeight = 50
BoardCells.Gap = 4

local WHITE = Color3.new(1, 1, 1)
local BLACK = Color3.new(0, 0, 0)

-- Filled in by refresh() (the values here are the night look, until the first refresh).
BoardCells.Night = true
BoardCells.BoardTop = Color3.fromHex("#2E1E51")
BoardCells.BoardBottom = Color3.fromHex("#0B0820")
BoardCells.Edge = Palette.Hues.Sora.Night
BoardCells.Row = Color3.fromHex("#271A48")
BoardCells.RowAlt = Color3.fromHex("#1E1438")
BoardCells.RowLit = Color3.fromHex("#4A3079")
BoardCells.HeadRow = Color3.fromHex("#060411")
BoardCells.HeadText = Palette.Hues.Sora.Night
BoardCells.Text = WHITE
BoardCells.SubText = Palette.Hues.Sora.Night
BoardCells.Gold = Palette.Hues.Yuzu.Night -- gold fills and frames (lit rows, the chosen one)
BoardCells.GoldText = Palette.Hues.Yuzu.Night -- gold as text on a row
BoardCells.PillText = Color3.fromHex("#0B0820")
BoardCells.IconBack = WHITE

-- Works the colours out again from the theme (the time of day may have changed). Returns the theme.
function BoardCells.refresh(): UiTheme.Theme
	local theme = UiTheme.get()
	local night = theme.night
	BoardCells.Night = night
	BoardCells.Text = theme.text
	BoardCells.SubText = theme.subText
	BoardCells.Edge = theme.panelEdge
	if night then
		BoardCells.Gold = Palette.Hues.Yuzu.Night
		local violet = Palette.Hues.Fuji.Night
		BoardCells.BoardTop = violet:Lerp(theme.panel, 0.78)
		BoardCells.BoardBottom = theme.panel
		BoardCells.Row = violet:Lerp(theme.panel, 0.82)
		BoardCells.RowAlt = violet:Lerp(theme.panel, 0.88)
		BoardCells.RowLit = violet:Lerp(theme.panel, 0.6)
		BoardCells.HeadRow = theme.panel:Lerp(BLACK, 0.45)
		BoardCells.HeadText = theme.subText
		BoardCells.GoldText = Palette.Hues.Yuzu.Night
		BoardCells.PillText = theme.panel
		BoardCells.IconBack = WHITE
	else
		BoardCells.Gold = Color3.fromHex("#EBB000") -- a deeper gold, so the frame shows on the light rows
		BoardCells.BoardTop = WHITE
		BoardCells.BoardBottom = theme.panel
		BoardCells.Row = WHITE
		BoardCells.RowAlt = Palette.Hues.Fuji.Day:Lerp(WHITE, 0.55)
		BoardCells.RowLit = Palette.Hues.Yuzu.Day:Lerp(WHITE, 0.3)
		BoardCells.HeadRow = Palette.Base.Sumi:Lerp(Palette.Hues.Fuji.Night, 0.25)
		BoardCells.HeadText = Palette.Hues.Fuji.Day:Lerp(WHITE, 0.5)
		BoardCells.GoldText = Color3.fromHex("#9A6A00")
		BoardCells.PillText = Palette.Base.Sumi
		BoardCells.IconBack = Palette.Hues.Sora.Day
	end
	return theme
end

-- The fill of a pill in one of the five hues: neon at night, a stronger pastel by day (dark text on both).
function BoardCells.pill(hueName: string): Color3
	local hue = Palette.Hues[hueName]
	if not hue then
		return BoardCells.Row
	end
	return if BoardCells.Night then hue.Night else hue.Day:Lerp(hue.Night, 0.45)
end

-- A colour used as text on a row: as it is at night; by day pulled towards the text colour so it reads on white.
function BoardCells.ink(color: Color3): Color3
	return if BoardCells.Night then color else color:Lerp(BoardCells.Text, 0.5)
end

-- A row's coloured frame: the hue as it is at night, a little deeper by day (neon is faint on a white row).
function BoardCells.rim(color: Color3): Color3
	return if BoardCells.Night then color else color:Lerp(BoardCells.Text, 0.2)
end

-- One of the five hues as text on a row.
function BoardCells.hueText(hueName: string): Color3
	local hue = Palette.Hues[hueName]
	if not hue then
		return BoardCells.Text
	end
	return if BoardCells.Night then hue.Night else hue.Night:Lerp(BoardCells.Text, 0.35)
end

function BoardCells.make(className: string, props: { [string]: any }, parent: Instance?): any
	local inst = Instance.new(className)
	for k, v in props do
		(inst :: any)[k] = v
	end
	inst.Parent = parent
	return inst
end

function BoardCells.corner(parent: Instance, radius: number)
	BoardCells.make("UICorner", { CornerRadius = UDim.new(0, radius) }, parent)
end

function BoardCells.xAlign(align: Align?): Enum.TextXAlignment
	return if align == "center"
		then Enum.TextXAlignment.Center
		elseif align == "right" then Enum.TextXAlignment.Right
		else Enum.TextXAlignment.Left
end

-- A line of text that shrinks to fit, never bigger than `maxSize`.
function BoardCells.label(parent: Instance, props: { [string]: any }, maxSize: number, bold: boolean?): TextLabel
	local theme = UiTheme.get()
	local base: { [string]: any } = {
		BackgroundTransparency = 1,
		TextScaled = true,
		TextColor3 = BoardCells.Text,
		Font = if bold then theme.head else theme.body,
		TextXAlignment = Enum.TextXAlignment.Left,
	}
	for k, v in props do
		base[k] = v
	end
	local result = BoardCells.make("TextLabel", base, parent) :: TextLabel
	BoardCells.make("UITextSizeConstraint", { MaxTextSize = maxSize, MinTextSize = 10 }, result)
	return result
end

-- A small 3D picture for a cell or a row, with the board's backing colour.
function BoardCells.icon(icon: RowIcon.Icon, lit: boolean, size: number): ViewportFrame
	local viewport = RowIcon.create(icon, lit, size)
	viewport.BackgroundColor3 = BoardCells.IconBack
	if not BoardCells.Night then
		viewport.BackgroundTransparency = if lit then 0.2 else 0.45
	end
	return viewport
end

-- The cells of one row: fixed columns keep their width, the rest is shared by the flexible ones.
function BoardCells.columnFrames(row: GuiObject, columns: { Column }): { Frame }
	local fixed, flex = 0, 0
	for _, column in columns do
		fixed += column.width or 0
		flex += column.flex or 0
	end
	local cells: { Frame } = {}
	local fixedBefore, flexBefore = 0, 0
	for _, column in columns do
		local share = flexBefore / math.max(flex, 0.001)
		local x = UDim.new(share, fixedBefore - share * fixed)
		local part = (column.flex or 0) / math.max(flex, 0.001)
		local width = if column.width then UDim.new(0, column.width) else UDim.new(part, -part * fixed)
		table.insert(
			cells,
			BoardCells.make("Frame", {
				Position = UDim2.new(x, UDim.new(0, 0)),
				Size = UDim2.new(width, UDim.new(1, 0)),
				BackgroundTransparency = 1,
				ClipsDescendants = true,
			}, row)
		)
		fixedBefore += column.width or 0
		flexBefore += column.flex or 0
	end
	return cells
end

-- A column name in the dark head row.
function BoardCells.headLabel(frame: Frame, text: string, column: Column): TextLabel
	local head = BoardCells.label(frame, {
		Position = UDim2.fromOffset(if column.align == "right" then 0 else 6, 0),
		Size = UDim2.new(1, if column.align == "right" then -8 else -12, 1, 0),
		Text = text,
		TextColor3 = BoardCells.HeadText,
		TextXAlignment = BoardCells.xAlign(column.align),
	}, 13, true)
	BoardCells.make("UIPadding", { PaddingTop = UDim.new(0.22, 0), PaddingBottom = UDim.new(0.22, 0) }, head)
	return head
end

function BoardCells.drawCell(frame: Frame, cell: Cell, column: Column, lit: boolean)
	local onTap = cell.onTap
	if onTap then
		local hit = BoardCells.make("TextButton", {
			Size = UDim2.fromScale(1, 1),
			BackgroundTransparency = 1,
			Text = "",
			ZIndex = 5,
		}, frame) :: TextButton
		hit.Activated:Connect(onTap)
	end
	if cell.icon then
		BoardCells.icon(cell.icon, lit, BoardCells.RowHeight - 8).Parent = frame
		return
	end
	local text = cell.text or ""
	local transparency = if cell.dim then 0.35 else 0
	if cell.pill then
		local pill = BoardCells.make("Frame", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.new(1, -8, 0, 26),
			BackgroundColor3 = cell.pill,
			BackgroundTransparency = if cell.dim then 0.7 else 0,
		}, frame)
		BoardCells.corner(pill, 13)
		local inside = BoardCells.label(pill, {
			Size = UDim2.fromScale(1, 1),
			Text = text,
			TextColor3 = if cell.dim then BoardCells.SubText else (cell.color or BoardCells.PillText),
			TextTransparency = transparency,
			TextXAlignment = Enum.TextXAlignment.Center,
		}, 14, true)
		BoardCells.make("UIPadding", {
			PaddingTop = UDim.new(0.2, 0),
			PaddingBottom = UDim.new(0.2, 0),
			PaddingLeft = UDim.new(0, 4),
			PaddingRight = UDim.new(0, 4),
		}, inside)
		return
	end
	local color = if cell.dim then BoardCells.SubText else (cell.color or BoardCells.Text)
	local padX = if column.align == "right" then 8 elseif column.align == "center" then 0 else 6
	if cell.sub and cell.sub ~= "" then
		BoardCells.label(frame, {
			Position = UDim2.fromOffset(padX, 6),
			Size = UDim2.new(1, -padX * 2, 0.5, -4),
			Text = text,
			TextColor3 = color,
			TextTransparency = transparency,
			TextXAlignment = BoardCells.xAlign(column.align),
		}, 18, cell.bold)
		BoardCells.label(frame, {
			Position = UDim2.new(0, padX, 0.5, 2),
			Size = UDim2.new(1, -padX * 2, 0.5, -8),
			Text = cell.sub,
			TextColor3 = BoardCells.SubText,
			TextXAlignment = BoardCells.xAlign(column.align),
		}, 13)
		return
	end
	local single = BoardCells.label(frame, {
		Position = UDim2.fromOffset(padX, 0),
		Size = UDim2.new(1, -padX * 2, 1, 0),
		Text = text,
		TextColor3 = color,
		TextTransparency = transparency,
		TextXAlignment = BoardCells.xAlign(column.align),
	}, 18, cell.bold)
	BoardCells.make("UIPadding", { PaddingTop = UDim.new(0.24, 0), PaddingBottom = UDim.new(0.24, 0) }, single)
end

-- The board look on a panel: rounded, with the board gradient and a rim. Can be called again (day / night).
function BoardCells.styleBoard(panel: Frame)
	panel.BackgroundColor3 = WHITE
	panel.BackgroundTransparency = 0
	if not panel:FindFirstChild("BoardCorner") then
		BoardCells.make("UICorner", { Name = "BoardCorner", CornerRadius = UDim.new(0, 16) }, panel)
	end
	local gradient = panel:FindFirstChild("BoardGradient") :: UIGradient?
	if not gradient then
		gradient = BoardCells.make("UIGradient", { Name = "BoardGradient", Rotation = 90 }, panel)
	end
	(gradient :: UIGradient).Color = ColorSequence.new(BoardCells.BoardTop, BoardCells.BoardBottom)
	local stroke = panel:FindFirstChild("BoardStroke") :: UIStroke?
	if not stroke then
		stroke = BoardCells.make("UIStroke", { Name = "BoardStroke", Thickness = 2 }, panel)
	end
	local s = stroke :: UIStroke
	s.Color = BoardCells.Edge
	s.Transparency = if BoardCells.Night then 0.3 else 0
	s.Thickness = if BoardCells.Night then 2 else 3
end

-- The round X at the top right of a board (a Sakura pill, like Beat Garden's close buttons).
function BoardCells.closeButton(parent: Instance): TextButton
	local button = BoardCells.make("TextButton", {
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.fromScale(1, 0),
		Size = UDim2.fromOffset(40, 40),
		Text = "X",
		TextScaled = true,
	}, parent) :: TextButton
	BoardCells.corner(button, 20)
	BoardCells.make("UIPadding", { PaddingTop = UDim.new(0.25, 0), PaddingBottom = UDim.new(0.25, 0) }, button)
	BoardCells.styleClose(button)
	return button
end

function BoardCells.styleClose(button: TextButton)
	button.BackgroundColor3 = BoardCells.pill("Sakura")
	button.TextColor3 = BoardCells.PillText
	button.Font = UiTheme.get().head
end

return BoardCells
