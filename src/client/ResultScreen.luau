--!strict
-- The screen after a tend: rank, score, judgement counts, best combo and what the plant got.
-- Everything shown comes from the server's answer; this module only draws it.

local Players = game:GetService("Players")

local UiTheme = require(script.Parent.UiTheme)

local ResultScreen = {}

export type Data = {
	songName: string,
	difficulty: string,
	rank: string,
	score: number,
	counts: { Perfect: number, Great: number, Good: number, Miss: number },
	maxCombo: number,
	points: number,
	favorite: boolean?, -- the song was the plant's favourite genre
	stage: string,
	fraction: number,
}

-- Night: neon tube colours. Day: candy colours (deeper than the pastel panels so the letter stands out).
local RANK_NIGHT: { [string]: Color3 } = {
	S = Color3.fromHex("#FFE14D"),
	A = Color3.fromHex("#FF4FA3"),
	B = Color3.fromHex("#3FC8FF"),
	C = Color3.fromHex("#3DFFB0"),
	D = Color3.fromHex("#A86BFF"),
}
local RANK_DAY: { [string]: Color3 } = {
	S = Color3.fromHex("#FFB52E"),
	A = Color3.fromHex("#FF5FAE"),
	B = Color3.fromHex("#3DAEFF"),
	C = Color3.fromHex("#2FD39A"),
	D = Color3.fromHex("#9B72FF"),
}

local function make(className: string, props: { [string]: any }, parent: Instance?): any
	local inst = Instance.new(className)
	for k, v in props do
		(inst :: any)[k] = v
	end
	inst.Parent = parent
	return inst
end

local function withCommas(n: number): string
	local text = tostring(math.floor(n))
	local out = text:reverse():gsub("(%d%d%d)", "%1,"):reverse()
	return (out:gsub("^,", ""))
end

local theme = UiTheme.get()

-- `head = true` uses the title font (numbers, rank); the rest uses the body font.
local function label(parent: Instance, props: { [string]: any }): TextLabel
	local base = { BackgroundTransparency = 1, TextScaled = true }
	local head = props.Font == Enum.Font.GothamBlack
	for k, v in props do
		base[k] = v
	end
	local l = make("TextLabel", base, parent) :: TextLabel
	UiTheme.styleText(l, theme, if head then "head" else "body")
	return l
end

-- The big rank letter, drawn in layers inside `box`:
--   night: a neon tube: two soft glows in the colour, then a white-hot core with a coloured edge;
--   day:   a candy sticker: a soft shadow, a thick white outline, and a fill that shades to the colour.
local function drawRank(box: Frame, rank: string, isNight: boolean)
	local function layer(z: number, props: { [string]: any }, stroke: { [string]: any }?, offset: number?): TextLabel
		local l = make("TextLabel", {
			Size = UDim2.fromScale(1, 1),
			Position = UDim2.fromOffset(0, offset or 0),
			BackgroundTransparency = 1,
			Text = rank,
			TextScaled = true,
			Font = Enum.Font.GothamBlack,
			ZIndex = z,
		}, box) :: TextLabel
		for k, v in props do
			(l :: any)[k] = v
		end
		if stroke then
			make("UIStroke", stroke, l)
		end
		return l
	end
	if isNight then
		local color = RANK_NIGHT[rank] or Color3.new(1, 1, 1)
		layer(1, { TextColor3 = color }, { Color = color, Thickness = 14, Transparency = 0.82 })
		layer(2, { TextColor3 = color }, { Color = color, Thickness = 7, Transparency = 0.55 })
		layer(3, { TextColor3 = Color3.new(1, 1, 1) }, { Color = color, Thickness = 3, Transparency = 0 })
	else
		local color = RANK_DAY[rank] or Color3.new(1, 1, 1)
		layer(1, { TextColor3 = color:Lerp(Color3.new(0, 0, 0), 0.3), TextTransparency = 0.55 }, {
			Color = color:Lerp(Color3.new(0, 0, 0), 0.3),
			Thickness = 10,
			Transparency = 0.55,
		}, 6)
		layer(
			2,
			{ TextColor3 = Color3.new(1, 1, 1) },
			{ Color = Color3.new(1, 1, 1), Thickness = 10, Transparency = 0 }
		)
		local fill = layer(3, { TextColor3 = Color3.new(1, 1, 1) })
		make("UIGradient", {
			Rotation = 90,
			Color = ColorSequence.new(color:Lerp(Color3.new(1, 1, 1), 0.45), color),
		}, fill)
	end
end

-- `onClose` runs when the player taps OK.
function ResultScreen.show(data: Data, onClose: () -> ())
	theme = UiTheme.get()
	local gui = make("ScreenGui", {
		Name = "ResultScreen",
		ResetOnSpawn = false,
		IgnoreGuiInset = true,
		DisplayOrder = 80,
	}, nil) :: ScreenGui
	local backdrop = make("Frame", {
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Color3.new(0, 0, 0),
		BackgroundTransparency = 0.4,
	}, gui)
	local panel = make("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.55),
		Size = UDim2.fromScale(0.9, 0.78),
	}, backdrop)
	make("UISizeConstraint", { MaxSize = Vector2.new(620, 360) }, panel)
	UiTheme.stylePanel(panel, theme, 18)

	label(panel, {
		Position = UDim2.fromOffset(16, 8),
		Size = UDim2.new(1, -32, 0, 26),
		Text = `{data.songName}  -  {data.difficulty}{if data.favorite then "   \u{2665} Favourite song!" else ""}`,
		Font = Enum.Font.GothamBlack,
		TextXAlignment = Enum.TextXAlignment.Left,
	})

	-- Left: rank and score
	local rankBox = make("Frame", {
		Position = UDim2.fromOffset(16, 40),
		Size = UDim2.new(0.34, 0, 0, 120),
		BackgroundTransparency = 1,
	}, panel) :: Frame
	make("UIPadding", {
		PaddingTop = UDim.new(0, 6),
		PaddingBottom = UDim.new(0, 14),
		PaddingLeft = UDim.new(0, 20),
		PaddingRight = UDim.new(0, 20),
	}, rankBox)
	drawRank(rankBox, data.rank, theme.night)
	label(panel, {
		Position = UDim2.fromOffset(16, 168),
		Size = UDim2.new(0.34, 0, 0, 40),
		Text = withCommas(data.score),
		Font = Enum.Font.GothamBlack,
	})
	label(panel, {
		Position = UDim2.fromOffset(16, 212),
		Size = UDim2.new(0.34, 0, 0, 22),
		Text = "SCORE",
		TextTransparency = 0.2,
	})

	-- Right: judgement counts, combo and growth
	local rows = {
		{ "Perfect", tostring(data.counts.Perfect) },
		{ "Great", tostring(data.counts.Great) },
		{ "Good", tostring(data.counts.Good) },
		{ "Miss", tostring(data.counts.Miss) },
		{ "Max combo", tostring(data.maxCombo) },
	}
	local x = 0.4
	for i, row in rows do
		local y = 44 + (i - 1) * 30
		label(panel, {
			Position = UDim2.new(x, 0, 0, y),
			Size = UDim2.new(0.32, 0, 0, 24),
			Text = row[1],
			TextXAlignment = Enum.TextXAlignment.Left,
		})
		label(panel, {
			Position = UDim2.new(x + 0.32, 0, 0, y),
			Size = UDim2.new(0.22, 0, 0, 24),
			Text = row[2],
			TextXAlignment = Enum.TextXAlignment.Right,
		})
	end
	label(panel, {
		Position = UDim2.new(x, 0, 0, 202),
		Size = UDim2.new(0.54, 0, 0, 28),
		Text = `+{data.points} growth  -  {data.stage} {math.floor(data.fraction * 100)}%`,
		TextXAlignment = Enum.TextXAlignment.Left,
	})

	local ok = make("TextButton", {
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -14),
		Size = UDim2.fromOffset(160, 52),
		Text = "OK",
		TextScaled = true,
	}, panel) :: TextButton
	UiTheme.styleButton(ok, theme, "Matcha")
	make("UIPadding", { PaddingTop = UDim.new(0.2, 0), PaddingBottom = UDim.new(0.2, 0) }, ok)
	local closed = false
	ok.Activated:Connect(function()
		if closed then
			return
		end
		closed = true
		gui:Destroy()
		UiTheme.setBlur("result", false)
		onClose()
	end)

	UiTheme.setBlur("result", true)
	gui.Parent = (Players.LocalPlayer :: Player):WaitForChild("PlayerGui")
end

return ResultScreen
