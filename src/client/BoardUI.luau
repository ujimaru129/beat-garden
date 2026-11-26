--!strict
-- A window drawn like a ranking board (ported from FLOREN WORLD): the board, a title with the close button, a bar
-- with a note and buttons, a head row with the column names, then the rows of a table. The Book and the Spirits
-- screens use it. The colours follow the time of day (BoardCells.refresh, on open and on every redraw).
--   title bar   Book  12/56                                 [X]
--   sub bar     a short note                     [button] [button]
--   head row    (icon) | SEED | 2/4 | ...
--   rows        one per seed / spirit; tappable rows react, lit rows are framed

local Players = game:GetService("Players")

local Lang = require(script.Parent.Lang)
local BoardCells = require(script.Parent.BoardCells)
local UiTheme = require(script.Parent.UiTheme)

local BoardUI = {}

export type Align = BoardCells.Align
export type Column = BoardCells.Column
export type Cell = BoardCells.Cell

export type Row = {
	cells: { Cell },
	onTap: (() -> ())?,
	lit: boolean?, -- your own / the chosen one: lighter row with a gold frame
}

-- A button in the bar under the title. `hue` = one of the five hues (a coloured pill), else a plain board button.
export type Action = { label: string, onTap: () -> (), width: number?, hue: string? }

export type Board = {
	open: () -> (),
	close: () -> (),
	isOpen: () -> boolean,
	setTitle: (text: string) -> (),
	-- The bar under the title: a note at the left (English for Lang.t) and buttons at the right.
	setBar: (note: string?, actions: { Action }?) -> (),
	-- The table. `empty` is shown when there are no rows.
	setTable: (columns: { Column }, rows: { Row }, empty: string?) -> (),
}

local ROW_HEIGHT = BoardCells.RowHeight
local GAP = BoardCells.Gap
local make = BoardCells.make
local corner = BoardCells.corner
local label = BoardCells.label
local columnFrames = BoardCells.columnFrames
local drawCell = BoardCells.drawCell

local function clear(parent: Instance)
	for _, child in parent:GetChildren() do
		if child:IsA("GuiObject") then
			child:Destroy()
		end
	end
end

function BoardUI.create(name: string, onClose: (() -> ())?): Board
	BoardCells.refresh()
	local gui = make("ScreenGui", {
		Name = name,
		ResetOnSpawn = false,
		IgnoreGuiInset = true,
		DisplayOrder = 55,
		Enabled = false,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
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
		-- lower than centre: the Roblox menu buttons sit in the top-left corner
		Position = UDim2.fromScale(0.5, 0.57),
		Size = UDim2.fromScale(0.92, 0.8),
		BackgroundColor3 = Color3.new(1, 1, 1),
		Active = true,
	}, backdrop) :: Frame
	make("UISizeConstraint", { MaxSize = Vector2.new(780, 470) }, panel)
	make("UIPadding", {
		PaddingTop = UDim.new(0, 10),
		PaddingBottom = UDim.new(0, 10),
		PaddingLeft = UDim.new(0, 12),
		PaddingRight = UDim.new(0, 12),
	}, panel)

	local titleLabel = label(panel, { Size = UDim2.new(1, -56, 0, 40), Text = "" }, 30, true)
	make("UIPadding", { PaddingTop = UDim.new(0, 4), PaddingBottom = UDim.new(0, 4) }, titleLabel)
	local closeButton = BoardCells.closeButton(panel)

	local subBar = make("Frame", {
		Position = UDim2.fromOffset(0, 46),
		Size = UDim2.new(1, 0, 0, 38),
		BackgroundTransparency = 1,
	}, panel) :: Frame
	local headRow = make("Frame", {
		Position = UDim2.fromOffset(0, 90),
		Size = UDim2.new(1, -10, 0, 26),
	}, panel) :: Frame
	corner(headRow, 6)
	local list = make("ScrollingFrame", {
		Position = UDim2.fromOffset(0, 120),
		Size = UDim2.new(1, 0, 1, -120),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ScrollBarThickness = 6,
		CanvasSize = UDim2.new(),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		ScrollingDirection = Enum.ScrollingDirection.Y,
	}, panel) :: ScrollingFrame
	make("UIListLayout", { Padding = UDim.new(0, GAP), SortOrder = Enum.SortOrder.LayoutOrder }, list)

	-- The look of the board itself, for the time of day now.
	local function restyle()
		local theme = BoardCells.refresh()
		BoardCells.styleBoard(panel)
		BoardCells.styleClose(closeButton)
		titleLabel.Font = theme.head
		titleLabel.TextColor3 = BoardCells.Text
		headRow.BackgroundColor3 = BoardCells.HeadRow
		list.ScrollBarImageColor3 = BoardCells.SubText
	end
	restyle()

	local function isOpen(): boolean
		return gui.Enabled
	end
	local function close()
		if not gui.Enabled then
			return
		end
		gui.Enabled = false
		UiTheme.setBlur(name, false)
		if onClose then
			onClose()
		end
	end
	backdrop.Activated:Connect(close)
	closeButton.Activated:Connect(close)

	local function setBar(note: string?, actions: { Action }?)
		restyle()
		clear(subBar)
		local used = 0
		for i, action in actions or {} do
			local width = action.width or 120
			local hue = action.hue
			local button = make("TextButton", {
				AnchorPoint = Vector2.new(1, 0),
				Position = UDim2.new(1, -used, 0, 0),
				Size = UDim2.new(0, width, 1, 0),
				Text = Lang.t(action.label),
				TextScaled = true,
				BackgroundColor3 = if hue then BoardCells.pill(hue) else BoardCells.Row,
				TextColor3 = if hue then BoardCells.PillText else BoardCells.Text,
				Font = UiTheme.get().head,
				AutoButtonColor = true,
				LayoutOrder = i,
			}, subBar) :: TextButton
			corner(button, 8)
			make("UIStroke", {
				Color = if hue then BoardCells.rim(BoardCells.pill(hue)) else BoardCells.SubText,
				Thickness = 1,
				Transparency = if hue then 0 else 0.4,
				ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
			}, button)
			make("UIPadding", {
				PaddingTop = UDim.new(0.24, 0),
				PaddingBottom = UDim.new(0.24, 0),
				PaddingLeft = UDim.new(0, 6),
				PaddingRight = UDim.new(0, 6),
			}, button)
			make("UITextSizeConstraint", { MaxTextSize = 17 }, button)
			button.Activated:Connect(action.onTap)
			used += width + 6
		end
		if note and note ~= "" then
			local noteLabel = label(subBar, {
				Size = UDim2.new(1, -used - 4, 1, 0),
				Text = Lang.t(note),
				TextColor3 = BoardCells.SubText,
				TextWrapped = true,
			}, 15)
			make("UIPadding", { PaddingTop = UDim.new(0.12, 0), PaddingBottom = UDim.new(0.12, 0) }, noteLabel)
		end
	end

	local function setTable(columns: { Column }, rows: { Row }, empty: string?)
		restyle()
		clear(headRow)
		local hasTitles = false
		for _, column in columns do
			hasTitles = hasTitles or column.title ~= ""
		end
		-- no column names (a grid of choices): no head row, the list starts higher
		headRow.Visible = hasTitles
		list.Position = UDim2.fromOffset(0, if hasTitles then 120 else 90)
		list.Size = UDim2.new(1, 0, 1, if hasTitles then -120 else -90)
		local heads = columnFrames(headRow, columns)
		for i, column in columns do
			if column.title ~= "" then
				BoardCells.headLabel(heads[i], Lang.t(column.title), column)
			end
		end

		local keep = list.CanvasPosition
		clear(list)
		for order, row in rows do
			local lit = row.lit == true
			local frame: GuiObject
			if row.onTap then
				local button = make("TextButton", {
					Text = "",
					AutoButtonColor = true,
				}, list) :: TextButton
				button.Activated:Connect(row.onTap)
				frame = button
			else
				frame = make("Frame", {}, list) :: Frame
			end
			frame.LayoutOrder = order
			frame.Size = UDim2.new(1, -10, 0, ROW_HEIGHT)
			frame.BorderSizePixel = 0
			frame.BackgroundColor3 = if lit
				then BoardCells.RowLit
				elseif order % 2 == 0 then BoardCells.RowAlt
				else BoardCells.Row
			corner(frame, 8)
			if lit then
				make(
					"UIStroke",
					{ Color = BoardCells.Gold, Thickness = 2, ApplyStrokeMode = Enum.ApplyStrokeMode.Border },
					frame
				)
			end
			local cells = columnFrames(frame, columns)
			for i, column in columns do
				local cell = row.cells[i]
				if cell then
					drawCell(cells[i], cell, column, lit)
				end
			end
		end
		if #rows == 0 and empty then
			local emptyLabel = label(list, {
				Size = UDim2.new(1, -10, 0, 60),
				Text = Lang.t(empty),
				TextColor3 = BoardCells.SubText,
				TextXAlignment = Enum.TextXAlignment.Center,
			}, 18)
			make("UIPadding", { PaddingTop = UDim.new(0.3, 0), PaddingBottom = UDim.new(0.3, 0) }, emptyLabel)
		end
		list.CanvasPosition = keep
	end

	gui.Parent = (Players.LocalPlayer :: Player):WaitForChild("PlayerGui")

	return {
		open = function()
			if gui.Enabled then
				return
			end
			restyle()
			list.CanvasPosition = Vector2.zero
			gui.Enabled = true
			UiTheme.setBlur(name, true)
		end,
		close = close,
		isOpen = isOpen,
		setTitle = function(text: string)
			titleLabel.Text = Lang.t(text)
		end,
		setBar = setBar,
		setTable = setTable,
	}
end

return BoardUI
