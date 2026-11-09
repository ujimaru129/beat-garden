--!strict
-- The song select screen (Tend, step 1). Left: a list of song cards; the selected card pops out and glows in
-- its genre colour. Right: a jacket for the selected song with a spinning record, a BPM read-out and an
-- equalizer that bounces on the song's own beat, then the name and a big PLAY button.
-- Tap a card to select it; PLAY (or tapping the selected card again) picks it. Touch first.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local Palette = require(ReplicatedStorage.Shared.Palette)
local ScrollThumb = require(script.Parent.ScrollThumb)
local UiTheme = require(script.Parent.UiTheme)

local SongSelect = {}

export type Item = {
	songId: string,
	name: string,
	genre: string, -- "Pop" | "Japan" | "Dance" | "Rock"
	bpm: number,
	favorite: boolean,
	artAssetId: string?, -- artwork for the sleeve (Songs/Art); nil = initials on the genre colours
}

export type Select = {
	open: (items: { Item }) -> (),
	close: () -> (),
	isOpen: () -> boolean,
}

local BAR_COUNT = 12
local CARD_HEIGHT = 58
local CARD_HEIGHT_SELECTED = 72

local function make(className: string, props: { [string]: any }, parent: Instance?): any
	local inst = Instance.new(className)
	for k, v in props do
		(inst :: any)[k] = v
	end
	inst.Parent = parent
	return inst
end

-- One vivid colour per genre (same in day and night: the cards are tinted by it).
local function genreColor(genre: string): Color3
	if genre == "Japan" then
		return Palette.Base.Torii
	elseif genre == "Pop" then
		return Palette.hue("Sakura", "Night")
	elseif genre == "Dance" then
		return Palette.hue("Sora", "Night")
	end
	return Palette.hue("Fuji", "Night")
end

local function setGradient(obj: GuiObject, top: Color3, bottom: Color3, rotation: number?)
	local g = obj:FindFirstChildOfClass("UIGradient") or make("UIGradient", {}, obj)
	g.Color = ColorSequence.new(top, bottom)
	g.Rotation = rotation or 90
end

type Entry = {
	item: Item,
	color: Color3,
	holder: Frame,
	card: TextButton,
	stripe: Frame,
	nameLabel: TextLabel,
	subLabel: TextLabel,
	heart: TextLabel,
	stroke: UIStroke,
}

-- `onPick` runs when the player confirms a song. `onClose` runs whenever the screen closes.
function SongSelect.create(onPick: (item: Item) -> (), onClose: (() -> ())?): Select
	local gui = make("ScreenGui", {
		Name = "SongSelect",
		ResetOnSpawn = false,
		IgnoreGuiInset = true,
		DisplayOrder = 55,
		Enabled = false,
		ZIndexBehavior = Enum.ZIndexBehavior.Global,
	}, nil) :: ScreenGui

	local backdrop = make("TextButton", {
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Color3.new(0, 0, 0),
		BackgroundTransparency = 0.45,
		AutoButtonColor = false,
		Text = "",
	}, gui) :: TextButton

	-- Lower than centre: the Roblox menu buttons sit in the top-left corner and cover anything there.
	local panel = make("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.58),
		Size = UDim2.fromScale(0.94, 0.8),
		Active = true,
	}, backdrop) :: Frame
	make("UISizeConstraint", { MaxSize = Vector2.new(780, 420), MinSize = Vector2.new(420, 250) }, panel)

	local titleLabel = make("TextLabel", {
		Position = UDim2.fromOffset(18, 8),
		Size = UDim2.new(0.6, 0, 0, 40),
		BackgroundTransparency = 1,
		Text = "SELECT SONG",
		TextScaled = true,
		TextXAlignment = Enum.TextXAlignment.Left,
	}, panel) :: TextLabel
	make("UITextSizeConstraint", { MaxTextSize = 30 }, titleLabel)

	local closeButton = make("TextButton", {
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -10, 0, 8),
		Size = UDim2.fromOffset(44, 44),
		Text = "X",
		TextScaled = true,
	}, panel) :: TextButton
	make("UITextSizeConstraint", { MaxTextSize = 24 }, closeButton)

	-- Left: the list ------------------------------------------------------------------------------
	local list = make("ScrollingFrame", {
		Position = UDim2.fromOffset(12, 56),
		Size = UDim2.new(0.5, -18, 1, -68),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ScrollBarThickness = 4,
		CanvasSize = UDim2.new(),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		ScrollingEnabled = false, -- done by hand below (the cards are buttons and swallow the touch)
	}, panel) :: ScrollingFrame
	make("UIListLayout", { Padding = UDim.new(0, 8), SortOrder = Enum.SortOrder.LayoutOrder }, list)
	make("UIPadding", { PaddingTop = UDim.new(0, 4), PaddingBottom = UDim.new(0, 8) }, list)
	ScrollThumb.attach(list, panel, UDim2.new(0.5, -4, 0, 60), UDim2.new(0, 5, 1, -76))

	-- Right: the preview ----------------------------------------------------------------------------
	local preview = make("Frame", {
		Position = UDim2.new(0.5, 6, 0, 56),
		Size = UDim2.new(0.5, -18, 1, -68),
		BackgroundTransparency = 1,
	}, panel) :: Frame

	-- Top block: the record sleeve (artwork) with the record peeking out behind it, and the read-outs.
	local top = make("Frame", {
		Size = UDim2.fromScale(1, 0.55),
		BackgroundTransparency = 1,
	}, preview) :: Frame

	-- Square box, as wide as it is high; the record is sized and placed relative to it.
	local sleeveBox = make("Frame", {
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
	}, top) :: Frame
	sleeveBox.SizeConstraint = Enum.SizeConstraint.RelativeYY
	local sleeveScale = make("UIScale", {}, sleeveBox) :: UIScale

	local vinyl = make("Frame", {
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(0.92, 0.92),
		BackgroundColor3 = Color3.new(1, 1, 1),
		BorderSizePixel = 0,
		ZIndex = 1,
	}, sleeveBox) :: Frame
	make("UICorner", { CornerRadius = UDim.new(0.5, 0) }, vinyl)
	make("UIGradient", {
		Color = ColorSequence.new({
			ColorSequenceKeypoint.new(0, Color3.fromRGB(18, 14, 30)),
			ColorSequenceKeypoint.new(0.25, Color3.fromRGB(95, 88, 120)),
			ColorSequenceKeypoint.new(0.5, Color3.fromRGB(18, 14, 30)),
			ColorSequenceKeypoint.new(0.75, Color3.fromRGB(95, 88, 120)),
			ColorSequenceKeypoint.new(1, Color3.fromRGB(18, 14, 30)),
		}),
		Rotation = 35,
	}, vinyl)
	for _, ring in { 0.78, 0.58 } do
		local r = make("Frame", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.fromScale(ring, ring),
			BackgroundTransparency = 1,
		}, vinyl)
		make("UICorner", { CornerRadius = UDim.new(0.5, 0) }, r)
		make("UIStroke", { Color = Color3.new(1, 1, 1), Thickness = 1.5, Transparency = 0.75 }, r)
	end
	local recordLabel = make("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(0.3, 0.3),
		BackgroundColor3 = Color3.new(1, 1, 1),
		BorderSizePixel = 0,
	}, vinyl) :: Frame
	make("UICorner", { CornerRadius = UDim.new(0.5, 0) }, recordLabel)
	local recordDot = make("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(0.22, 0.22),
		BackgroundColor3 = Color3.fromRGB(18, 14, 30),
		BorderSizePixel = 0,
	}, recordLabel) :: Frame
	make("UICorner", { CornerRadius = UDim.new(0.5, 0) }, recordDot)

	-- The sleeve: the artwork image if the song has one (Songs/Art), else the genre colours with the song's
	-- initials. Either way the genre pill sits on its corner.
	local sleeve = make("Frame", {
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Color3.new(1, 1, 1),
		ClipsDescendants = true,
		ZIndex = 2,
	}, sleeveBox) :: Frame
	make("UICorner", { CornerRadius = UDim.new(0, 14) }, sleeve)
	make("UIStroke", { Color = Color3.new(1, 1, 1), Thickness = 3 }, sleeve)
	local initials = make("TextLabel", {
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		Text = "",
		TextScaled = true,
		Font = Enum.Font.GothamBlack,
		TextColor3 = Color3.new(1, 1, 1),
		TextTransparency = 0.12,
		TextStrokeColor3 = Color3.fromRGB(40, 10, 90),
		TextStrokeTransparency = 0.7,
		ZIndex = 3,
	}, sleeve) :: TextLabel
	make("UIPadding", {
		PaddingTop = UDim.new(0.22, 0),
		PaddingBottom = UDim.new(0.22, 0),
		PaddingLeft = UDim.new(0.1, 0),
		PaddingRight = UDim.new(0.1, 0),
	}, initials)
	local art = make("ImageLabel", {
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		ScaleType = Enum.ScaleType.Crop,
		Image = "",
		Visible = false,
		ZIndex = 4,
	}, sleeve) :: ImageLabel
	local genrePill = make("TextLabel", {
		Position = UDim2.fromOffset(6, 6),
		Size = UDim2.fromOffset(62, 20),
		BackgroundColor3 = Color3.new(1, 1, 1),
		BackgroundTransparency = 0.08,
		Text = "",
		TextScaled = true,
		Font = Enum.Font.GothamBlack,
		TextColor3 = Color3.fromRGB(31, 42, 68),
		ZIndex = 5,
	}, sleeve) :: TextLabel
	make("UICorner", { CornerRadius = UDim.new(0.5, 0) }, genrePill)
	make("UIPadding", {
		PaddingTop = UDim.new(0, 3),
		PaddingBottom = UDim.new(0, 3),
		PaddingLeft = UDim.new(0, 6),
		PaddingRight = UDim.new(0, 6),
	}, genrePill)

	-- Read-outs to the right of the record: the BPM and an equalizer that bounces on the beat.
	local readout = make("Frame", {
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.fromScale(1, 0),
		Size = UDim2.new(0, 112, 1, 0),
		BackgroundTransparency = 1,
		ZIndex = 3,
	}, top) :: Frame
	local bpmLabel = make("TextLabel", {
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.fromScale(1, 0.04),
		Size = UDim2.new(1, 0, 0, 40),
		BackgroundTransparency = 1,
		Text = "",
		RichText = true,
		TextSize = 36,
		Font = Enum.Font.GothamBlack,
		TextXAlignment = Enum.TextXAlignment.Right,
		ZIndex = 3,
	}, readout) :: TextLabel
	-- Favourite songs get a badge under the BPM instead of a sentence.
	local bonusBadge = make("TextLabel", {
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, 0, 0, 50),
		Size = UDim2.fromOffset(92, 24),
		BackgroundColor3 = Palette.Base.Torii,
		Text = "\u{2665} BONUS",
		TextSize = 14,
		Font = Enum.Font.GothamBlack,
		TextColor3 = Color3.new(1, 1, 1),
		Visible = false,
		ZIndex = 3,
	}, readout) :: TextLabel
	make("UICorner", { CornerRadius = UDim.new(0.5, 0) }, bonusBadge)
	make("UIStroke", {
		Color = Color3.new(1, 1, 1),
		Thickness = 1.5,
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border, -- on a TextLabel the default outlines the letters
	}, bonusBadge)
	local bars: { Frame } = {}
	for i = 1, BAR_COUNT do
		bars[i] = make("Frame", {
			AnchorPoint = Vector2.new(1, 1),
			Position = UDim2.new(1, -(BAR_COUNT - i) * 9, 1, -2),
			Size = UDim2.fromOffset(6, 10),
			BackgroundTransparency = 0.05,
			BorderSizePixel = 0,
			ZIndex = 3,
		}, readout)
		make("UICorner", { CornerRadius = UDim.new(0, 2) }, bars[i])
	end

	local nameLabel = make("TextLabel", {
		Position = UDim2.fromScale(0, 0.6),
		Size = UDim2.fromScale(1, 0.17),
		BackgroundTransparency = 1,
		Text = "",
		TextScaled = true,
		TextXAlignment = Enum.TextXAlignment.Left,
	}, preview) :: TextLabel
	make("UITextSizeConstraint", { MaxTextSize = 28 }, nameLabel)

	-- PLAY: the one loud button. The orange fill is its own frame behind the text, because a gradient
	-- on the button itself would tint the text orange as well (it did, and the label vanished).
	local playButton = make("TextButton", {
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.fromScale(0, 1),
		Size = UDim2.fromScale(1, 0.17),
		BackgroundTransparency = 1,
		Text = "PLAY",
		TextScaled = true,
		Font = Enum.Font.GothamBlack,
		TextColor3 = Color3.new(1, 1, 1),
		TextStrokeColor3 = Color3.fromRGB(150, 40, 10),
		TextStrokeTransparency = 0.45,
		ZIndex = 3,
	}, preview) :: TextButton
	make("UITextSizeConstraint", { MaxTextSize = 26 }, playButton)
	make("UIPadding", { PaddingTop = UDim.new(0.12, 0), PaddingBottom = UDim.new(0.12, 0) }, playButton)
	local playFill = make("Frame", {
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Color3.new(1, 1, 1),
		BorderSizePixel = 0,
		ZIndex = 2,
	}, playButton) :: Frame
	make("UICorner", { CornerRadius = UDim.new(0, 14) }, playFill)
	make("UIStroke", { Color = Color3.new(1, 1, 1), Thickness = 3 }, playFill)
	setGradient(playFill, Color3.fromHex("#FFB347"), Palette.Base.Torii)
	local playScale = make("UIScale", {}, playButton) :: UIScale

	-- State -----------------------------------------------------------------------------------------
	local theme = UiTheme.get()
	local entries: { Entry } = {}
	local selected = 0
	local renderConnection: RBXScriptConnection? = nil

	local function restylePanel()
		theme = UiTheme.get()
		UiTheme.stylePanel(panel, theme, 20)
		UiTheme.styleText(titleLabel, theme, "head")
		UiTheme.styleText(nameLabel, theme, "head")
		UiTheme.styleButton(closeButton, theme, "Sakura", 22)
	end

	local function styleEntry(entry: Entry, isSelected: boolean, animate: boolean)
		local height = UDim2.new(1, -8, 0, if isSelected then CARD_HEIGHT_SELECTED else CARD_HEIGHT)
		local position = UDim2.fromOffset(if isSelected then 14 else 0, 0)
		if animate then
			local info = TweenInfo.new(0.22, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
			TweenService:Create(entry.holder, info, { Size = height }):Play()
			TweenService:Create(entry.card, info, { Position = position }):Play()
		else
			entry.holder.Size = height
			entry.card.Position = position
		end
		local color = entry.color
		if isSelected then
			entry.card.BackgroundColor3 = Color3.new(1, 1, 1)
			entry.card.BackgroundTransparency = 0
			setGradient(entry.card, color:Lerp(Color3.new(1, 1, 1), 0.3), color, 0)
			entry.stroke.Color = Color3.new(1, 1, 1)
			entry.stroke.Thickness = 3
			entry.stroke.Transparency = 0
			for _, label in { entry.nameLabel, entry.subLabel, entry.heart } do
				label.TextColor3 = Color3.new(1, 1, 1)
				label.TextStrokeTransparency = 0.55
				label.TextStrokeColor3 = Color3.fromRGB(30, 20, 50)
			end
		else
			entry.card.BackgroundColor3 = Color3.new(1, 1, 1)
			entry.card.BackgroundTransparency = if theme.night then 0.1 else 0.05
			local base = if theme.night then Color3.fromHex("#150F33") else Color3.fromHex("#FFF6FB")
			setGradient(entry.card, base:Lerp(color, if theme.night then 0.22 else 0.3), base, 0)
			entry.stroke.Color = color
			entry.stroke.Thickness = 1.5
			entry.stroke.Transparency = 0.45
			entry.nameLabel.TextColor3 = theme.text
			entry.subLabel.TextColor3 = if theme.night then color:Lerp(Color3.new(1, 1, 1), 0.3) else color
			entry.heart.TextColor3 = color
			for _, label in { entry.nameLabel, entry.subLabel, entry.heart } do
				label.TextStrokeTransparency = 1
			end
		end
	end

	local function showPreview(entry: Entry)
		local item = entry.item
		local color = entry.color
		setGradient(sleeve, color:Lerp(Color3.new(1, 1, 1), 0.3), color:Lerp(Color3.fromRGB(40, 10, 90), 0.5), 60)
		recordLabel.BackgroundColor3 = color:Lerp(Color3.new(1, 1, 1), 0.2)
		genrePill.Text = string.upper(item.genre)
		-- initials of the first two words
		local letters = ""
		for word in string.gmatch(item.name, "%S+") do
			letters ..= string.upper(string.sub(word, 1, 1))
			if #letters >= 2 then
				break
			end
		end
		initials.Text = letters
		art.Image = item.artAssetId or ""
		art.Visible = item.artAssetId ~= nil
		initials.Visible = item.artAssetId == nil
		bpmLabel.Text = `{math.floor(item.bpm + 0.5)}<font size="16"> BPM</font>`
		bpmLabel.TextColor3 = theme.text
		for _, bar in bars do
			bar.BackgroundColor3 = color
		end
		nameLabel.Text = item.name
		bonusBadge.Visible = item.favorite
		sleeveScale.Scale = 0.9
		TweenService:Create(sleeveScale, TweenInfo.new(0.3, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
			Scale = 1,
		}):Play()
	end

	local function selectEntry(index: number, animate: boolean)
		local entry = entries[index]
		if not entry then
			return
		end
		selected = index
		for i, e in entries do
			styleEntry(e, i == index, animate)
		end
		showPreview(entry)
	end

	-- Drag scrolling by hand ------------------------------------------------------------------------
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
		if not (input == active or kind == Enum.UserInputType.MouseMovement or kind == Enum.UserInputType.Touch) then
			return
		end
		local dy = lastY - input.Position.Y
		lastY = input.Position.Y
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
	RunService.Heartbeat:Connect(function()
		if dragging == nil and math.abs(velocity) > 0.4 then
			scrollBy(velocity)
			velocity *= 0.93
		end
	end)

	-- Open / close ---------------------------------------------------------------------------------
	local function stopRender()
		if renderConnection then
			renderConnection:Disconnect()
			renderConnection = nil
		end
	end

	local function close()
		if not gui.Enabled then
			return
		end
		gui.Enabled = false
		stopRender()
		UiTheme.setBlur("songselect", false)
		if onClose then
			onClose()
		end
	end

	local function confirm()
		local entry = entries[selected]
		if entry then
			onPick(entry.item)
		end
	end

	backdrop.Activated:Connect(close)
	closeButton.Activated:Connect(close)
	playButton.Activated:Connect(confirm)

	local function build(items: { Item })
		for _, entry in entries do
			entry.holder:Destroy()
		end
		table.clear(entries)
		for i, item in items do
			local color = genreColor(item.genre)
			local holder = make("Frame", {
				LayoutOrder = i,
				Size = UDim2.new(1, -8, 0, CARD_HEIGHT),
				BackgroundTransparency = 1,
			}, list) :: Frame
			local card = make("TextButton", {
				Size = UDim2.new(1, -14, 1, 0),
				Position = UDim2.fromOffset(0, 0),
				Text = "",
				AutoButtonColor = false,
				BorderSizePixel = 0,
				BackgroundColor3 = Color3.new(1, 1, 1),
			}, holder) :: TextButton
			make("UICorner", { CornerRadius = UDim.new(0, 14) }, card)
			local stroke = make("UIStroke", { Color = color, Thickness = 1.5 }, card) :: UIStroke
			local stripe = make("Frame", {
				Size = UDim2.new(0, 8, 1, -16),
				Position = UDim2.fromOffset(8, 8),
				BackgroundColor3 = color,
				BorderSizePixel = 0,
			}, card) :: Frame
			make("UICorner", { CornerRadius = UDim.new(0.5, 0) }, stripe)
			local heart = make("TextLabel", {
				AnchorPoint = Vector2.new(1, 0.5),
				Position = UDim2.new(1, -12, 0.5, 0),
				Size = UDim2.fromOffset(26, 26),
				BackgroundTransparency = 1,
				Text = if item.favorite then "\u{2665}" else "",
				TextSize = 24,
				Font = Enum.Font.GothamBlack,
			}, card) :: TextLabel
			local cardName = make("TextLabel", {
				Position = UDim2.fromOffset(26, 0),
				Size = UDim2.new(1, -62, 0.58, 0),
				BackgroundTransparency = 1,
				Text = item.name,
				TextSize = 20,
				Font = Enum.Font.GothamBlack,
				TextXAlignment = Enum.TextXAlignment.Left,
				TextYAlignment = Enum.TextYAlignment.Bottom,
				TextTruncate = Enum.TextTruncate.AtEnd,
			}, card) :: TextLabel
			local subLabel = make("TextLabel", {
				Position = UDim2.new(0, 26, 0.58, 0),
				Size = UDim2.new(1, -62, 0.34, 0),
				BackgroundTransparency = 1,
				Text = `{item.genre}  |  {math.floor(item.bpm + 0.5)} BPM`,
				TextSize = 14,
				Font = Enum.Font.GothamBold,
				TextXAlignment = Enum.TextXAlignment.Left,
				TextYAlignment = Enum.TextYAlignment.Top,
			}, card) :: TextLabel
			local entry: Entry = {
				item = item,
				color = color,
				holder = holder,
				card = card,
				stripe = stripe,
				nameLabel = cardName,
				subLabel = subLabel,
				heart = heart,
				stroke = stroke,
			}
			entries[i] = entry
			card.InputBegan:Connect(beginDrag)
			card.Activated:Connect(function()
				if moved >= 10 then -- a drag is a scroll, not a tap
					return
				end
				if selected == i then
					confirm()
				else
					selectEntry(i, true)
				end
			end)
		end
	end

	gui.Parent = (Players.LocalPlayer :: Player):WaitForChild("PlayerGui")

	return {
		open = function(items: { Item })
			if #items == 0 then
				return
			end
			restylePanel()
			build(items)
			list.CanvasPosition = Vector2.new(0, 0)
			velocity = 0
			gui.Enabled = true
			UiTheme.setBlur("songselect", true)
			selectEntry(1, false)
			-- the cards fly in from the left, one after another
			for i, entry in entries do
				local target = entry.card.Position
				entry.card.Position = UDim2.fromScale(-1.3, 0)
				task.delay((i - 1) * 0.05, function()
					TweenService:Create(
						entry.card,
						TweenInfo.new(0.38, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
						{ Position = target }
					):Play()
				end)
			end
			-- record, bars and BPM pulse
			stopRender()
			renderConnection = RunService.RenderStepped:Connect(function()
				local entry = entries[selected]
				if not entry then
					return
				end
				local t = os.clock()
				local beat = (t * entry.item.bpm / 60) % 1
				local pulse = (1 - beat) ^ 3
				vinyl.Rotation = (t * 50) % 360
				bpmLabel.TextSize = 34 + 5 * pulse
				playScale.Scale = 1 + 0.035 * pulse
				for i, bar in bars do
					local wobble = 0.35 + 0.65 * math.abs(math.sin(t * 2.3 + i * 1.7))
					bar.Size = UDim2.fromOffset(6, 6 + 30 * wobble * (0.25 + 0.75 * pulse))
				end
			end)
		end,
		close = close,
		isOpen = function()
			return gui.Enabled
		end,
	}
end

return SongSelect
