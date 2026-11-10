--!strict
-- Touch-first song select: a list of songs with the difficulty buttons under it.
-- The selected song's preview plays while the screen is up (and changes with the selection).
-- Prototype stand-in for the real "Tend" flow. Keyboard shortcuts live in the caller.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Difficulty = require(ReplicatedStorage.Shared.Difficulty)
local Palette = require(ReplicatedStorage.Shared.Palette)
local SongPlayer = require(script.Parent.SongPlayer)
local Songs = require(ReplicatedStorage.Shared.Songs)

local SongSelect = {}

export type Screen = {
	-- Hiding the screen stops the preview; showing it starts the preview again.
	setVisible: (visible: boolean) -> (),
	getSelected: () -> Songs.Song,
	-- Moves the selection by `delta` rows (wraps around).
	step: (delta: number) -> (),
}

local PREVIEW_VOLUME = 0.5
local PREVIEW_FADE_IN = 0.4
local PREVIEW_FADE_OUT = 0.2

local DIFFICULTY_COLORS: { [string]: Color3 } = {
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

-- `onPick` is called with the selected song and "Easy" / "Normal" / "Hard" when a difficulty
-- button is tapped or clicked.
function SongSelect.create(onPick: (song: Songs.Song, difficulty: string) -> ()): Screen
	local gui = make("ScreenGui", {
		Name = "SongSelect",
		ResetOnSpawn = false,
		IgnoreGuiInset = true,
		DisplayOrder = 40,
	}, nil) :: ScreenGui

	-- Song list
	local panel = make("Frame", {
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.fromScale(0.5, 0.12),
		Size = UDim2.fromScale(0.9, 0.58),
		BackgroundColor3 = Palette.Base.YoruSky,
		BackgroundTransparency = 0.25,
	}, gui)
	make("UISizeConstraint", { MaxSize = Vector2.new(560, 420) }, panel)
	make("UICorner", { CornerRadius = UDim.new(0, 16) }, panel)
	make("UIPadding", {
		PaddingTop = UDim.new(0, 10),
		PaddingBottom = UDim.new(0, 10),
		PaddingLeft = UDim.new(0, 12),
		PaddingRight = UDim.new(0, 12),
	}, panel)
	make("TextLabel", {
		Size = UDim2.new(1, 0, 0, 28),
		BackgroundTransparency = 1,
		Text = "Select a song",
		TextColor3 = Palette.Base.Washi,
		TextSize = 20,
		Font = Enum.Font.GothamBold,
		TextXAlignment = Enum.TextXAlignment.Left,
	}, panel)
	local list = make("ScrollingFrame", {
		Position = UDim2.fromOffset(0, 36),
		Size = UDim2.new(1, 0, 1, -36),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ScrollBarThickness = 4,
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		CanvasSize = UDim2.new(),
		ScrollingDirection = Enum.ScrollingDirection.Y,
	}, panel) :: ScrollingFrame
	make("UIListLayout", { Padding = UDim.new(0, 8), SortOrder = Enum.SortOrder.LayoutOrder }, list)

	local selectedIndex = 1
	local visible = true
	local preview: SongPlayer.Playback? = nil
	local strokes: { UIStroke } = {}
	local badges: { TextLabel } = {}

	local function stopPreview()
		if preview then
			preview.stop(PREVIEW_FADE_OUT)
			preview = nil
		end
	end

	local function startPreview()
		stopPreview()
		local song = Songs.List[selectedIndex]
		preview = SongPlayer.play(song, {
			startMs = song.previewStartMs,
			lengthMs = song.previewLengthMs,
			loop = true,
			volume = PREVIEW_VOLUME,
			fadeInSeconds = PREVIEW_FADE_IN,
		})
	end

	local function refresh()
		for i, stroke in strokes do
			stroke.Transparency = if i == selectedIndex then 0 else 1
			badges[i].Visible = i == selectedIndex
		end
	end

	local function selectSong(index: number)
		if index == selectedIndex then
			return
		end
		selectedIndex = index
		refresh()
		if visible then
			startPreview()
		end
	end

	for i, song in Songs.List do
		local card = make("TextButton", {
			LayoutOrder = i,
			Size = UDim2.new(1, -6, 0, 64),
			BackgroundColor3 = Palette.Base.YoruGround,
			AutoButtonColor = true,
			Text = "",
		}, list) :: TextButton
		make("UICorner", { CornerRadius = UDim.new(0, 12) }, card)
		strokes[i] = make("UIStroke", {
			ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
			Color = Palette.Hues.Yuzu.Night,
			Thickness = 3,
			Transparency = 1,
		}, card)
		make("TextLabel", {
			Position = UDim2.fromOffset(14, 8),
			Size = UDim2.new(1, -110, 0, 26),
			BackgroundTransparency = 1,
			Text = song.title,
			TextColor3 = Palette.Base.Washi,
			TextSize = 20,
			Font = Enum.Font.GothamBold,
			TextXAlignment = Enum.TextXAlignment.Left,
			TextTruncate = Enum.TextTruncate.AtEnd,
		}, card)
		make("TextLabel", {
			Position = UDim2.fromOffset(14, 36),
			Size = UDim2.new(1, -110, 0, 18),
			BackgroundTransparency = 1,
			Text = `{song.bpm} BPM`,
			TextColor3 = Palette.Base.Washi,
			TextTransparency = 0.35,
			TextSize = 14,
			Font = Enum.Font.Gotham,
			TextXAlignment = Enum.TextXAlignment.Left,
		}, card)
		-- Shown on the selected song only: tells the player which song they are hearing.
		badges[i] = make("TextLabel", {
			AnchorPoint = Vector2.new(1, 0.5),
			Position = UDim2.new(1, -14, 0.5, 0),
			Size = UDim2.fromOffset(84, 24),
			BackgroundTransparency = 1,
			Text = "♪ Playing",
			TextColor3 = Palette.Hues.Yuzu.Night,
			TextSize = 14,
			Font = Enum.Font.GothamBold,
			TextXAlignment = Enum.TextXAlignment.Right,
			Visible = false,
		}, card)
		-- Activated fires for touch, mouse click and gamepad select.
		card.Activated:Connect(function()
			selectSong(i)
		end)
	end

	-- Difficulty buttons: tapping one starts the run with the selected song.
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
			BackgroundColor3 = DIFFICULTY_COLORS[name],
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
		button.Activated:Connect(function()
			onPick(Songs.List[selectedIndex], name)
		end)
	end

	refresh()
	gui.Parent = (Players.LocalPlayer :: Player):WaitForChild("PlayerGui")
	startPreview()

	return {
		setVisible = function(show: boolean)
			if show == visible then
				return
			end
			visible = show
			gui.Enabled = show
			if show then
				startPreview()
			else
				stopPreview()
			end
		end,
		getSelected = function(): Songs.Song
			return Songs.List[selectedIndex]
		end,
		step = function(delta: number)
			selectSong((selectedIndex - 1 + delta) % #Songs.List + 1)
		end,
	}
end

return SongSelect
