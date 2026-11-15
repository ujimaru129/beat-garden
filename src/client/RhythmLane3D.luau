--!strict
-- 3D rhythm lane: four lanes laid on the ground in front of the player, notes slide toward
-- the player and are tapped on the hit line. Same play() contract as RhythmOverlay, so the
-- caller can swap between the two. Everything is client-side (local parts only).
--
-- Prototype only: shapes, sizes and the camera framing are placeholders to tune in Studio.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local Palette = require(ReplicatedStorage.Shared.Palette)
local RhythmEngine = require(ReplicatedStorage.Shared.RhythmEngine)
local HitSounds = require(script.Parent.HitSounds)
local RhythmOverlay = require(script.Parent.RhythmOverlay)
local Lang = require(script.Parent.Lang)
local GardenState = require(script.Parent.GardenState)
local SpiritModel = require(script.Parent.SpiritModel)
local Spirits = require(ReplicatedStorage.Shared.Garden.Spirits)
local UiTheme = require(script.Parent.UiTheme)

local RhythmLane3D = {}

export type Options = RhythmOverlay.Options

local LANE_KEYS = {
	[Enum.KeyCode.D] = 0,
	[Enum.KeyCode.F] = 1,
	[Enum.KeyCode.J] = 2,
	[Enum.KeyCode.K] = 3,
	[Enum.KeyCode.ButtonL2] = 0,
	[Enum.KeyCode.ButtonL1] = 1,
	[Enum.KeyCode.ButtonR1] = 2,
	[Enum.KeyCode.ButtonR2] = 3,
}
local KEY_LABELS = { "D", "F", "J", "K" }
local SHAPE_GLYPHS = { Circle = "●", Triangle = "▲", Square = "■", Diamond = "◆" }

local SCROLL_MS = 1500 -- how long a note is visible before reaching the hit line
local LANE_WIDTH = 4.5 -- studs (wide, so the lanes fill a landscape phone screen)
local NOTE_SCALE = LANE_WIDTH / 3 -- note pieces were drawn for 3-stud lanes
local TRI_BASE = 2.4 -- triangle note size, in the drawing size above
local TRI_SLABS = 14 -- slabs a triangle note is built from
local TRI_SIZE = 1.0 -- the triangle is drawn this much bigger than the other shapes' base, so it looks as large
local BEAM_SLICES = 5 -- the press light up the lane: slices fading out away from the hit line
local BEAM_SLICE_LENGTH = 4
local BEAM_FADE = { 0.2, 0.42, 0.62, 0.8, 0.92 } -- start transparency of each slice
local DIAMOND_SIZE = LANE_WIDTH * 0.85 -- a diamond of light on the hit point (a square turned 45 degrees)
local LANE_LENGTH = 40 -- studs from the hit line to where notes appear
local HIT_AHEAD = 7 -- studs between the character and the hit line
local CHARACTER_FADE = 0.6 -- the character stands near the hit line, so it is drawn faint during a run
local METRONOME_SOUND = "rbxasset://sounds/electronicpingshort.wav"

local JUDGEMENT_COLORS: { [string]: Color3 } = {
	Perfect = Palette.Hues.Yuzu.Night,
	Great = Palette.Hues.Sora.Night,
	Good = Palette.Hues.Matcha.Night,
	Miss = Palette.Rarity.Common,
}

local function make(className: string, props: { [string]: any }, parent: Instance?): any
	local inst = Instance.new(className)
	for k, v in props do
		(inst :: any)[k] = v
	end
	inst.Parent = parent
	return inst
end

local function laneColor(lane: number): Color3
	return Palette.hue(Palette.LaneOrder[lane + 1], "Night")
end

-- By day every lane has the same look: a pale floor and a deep, saturated note (the same value for all four hues,
-- so no note is lighter against its lane than another).
local function DEEP(color: Color3): Color3
	local h = color:ToHSV()
	return Color3.fromHSV(h, 0.92, 0.6)
end

local function laneShape(lane: number): string
	return Palette.LaneShapes[lane + 1]
end

-- Lane centre on the board's x axis (lane 0 is the leftmost).
local function laneX(lane: number): number
	return (lane - 1.5) * LANE_WIDTH
end

local function solidProps(color: Color3): { [string]: any }
	return {
		Anchored = true,
		CanCollide = false,
		CanQuery = false,
		CanTouch = false,
		CastShadow = false,
		Color = color,
	}
end

-- Where the board sits: in front of the character, on the ground, facing the character's look direction.
local function boardOrigin(): CFrame
	local character = (Players.LocalPlayer :: Player).Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not (root and root:IsA("BasePart")) then
		return CFrame.new(0, 0, 0)
	end
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local groundOffset = if humanoid then humanoid.HipHeight + root.Size.Y / 2 else 3
	local look = root.CFrame.LookVector * Vector3.new(1, 0, 1)
	if look.Magnitude < 0.01 then
		look = Vector3.new(0, 0, -1)
	end
	local ground = root.Position - Vector3.new(0, groundOffset, 0)
	return CFrame.lookAt(ground + look.Unit * HIT_AHEAD, ground + look.Unit * (HIT_AHEAD + 1))
end

-- A note piece. Shapes differ per lane so lanes are not told apart by colour alone.
local function makeNotePart(lane: number, parent: Instance): BasePart
	local day = not UiTheme.get().night
	-- The notes are plain (not glowing) so their outline stays crisp: by day deep and saturated against the
	-- pastel floor, by night bright and saturated (the scene is evenly lit during a run, see Atmosphere).
	local color = if day then DEEP(laneColor(lane)) else laneColor(lane):Lerp(Color3.new(1, 1, 1), 0.15)
	local shape = laneShape(lane)
	local props = solidProps(color)
	props.Material = Enum.Material.SmoothPlastic
	props.Transparency = 1
	if shape == "Circle" then
		props.Shape = Enum.PartType.Cylinder
		props.Size = Vector3.new(0.6, 2.0, 2.0) * NOTE_SCALE
		return make("Part", props, parent)
	elseif shape == "Triangle" then
		-- The triangle note is a stack of thin slabs, narrow at the apex (towards the far end of the lane) and
		-- wide at the base: real geometry, so it does not shimmer like a texture would. The returned part is a
		-- tiny invisible anchor; the slabs are its children and are moved with it (see moveNote).
		local anchor = make("Part", props, parent)
		anchor.Size = Vector3.new(0.2, 0.2, 0.2)
		anchor:SetAttribute("Triangle", true)
		local width = TRI_BASE * TRI_SIZE * NOTE_SCALE
		local height = width * 0.866
		for k = 0, TRI_SLABS - 1 do
			local slab = solidProps(color)
			slab.Name = "Slab"
			slab.Material = props.Material
			slab.Transparency = 1
			-- thin: a thick triangle shows its near side face from the low camera and looks like a house
			slab.Size = Vector3.new(width * (k + 0.5) / TRI_SLABS, 0.2 * NOTE_SCALE, height / TRI_SLABS + 0.02)
			make("Part", slab, anchor)
		end
		return anchor
	elseif shape == "Diamond" then
		props.Size = Vector3.new(1.55, 0.6, 1.55) * NOTE_SCALE
		return make("Part", props, parent)
	end
	props.Size = Vector3.new(1.85, 0.6, 1.85) * NOTE_SCALE
	return make("Part", props, parent)
end

-- Orientation that lays each shape flat on the board.
local function noteCFrame(origin: CFrame, lane: number, z: number): CFrame
	local base = origin * CFrame.new(laneX(lane), 0.6, z)
	local shape = laneShape(lane)
	if shape == "Circle" then
		return base * CFrame.Angles(0, 0, math.rad(90))
	elseif shape == "Diamond" then
		return base * CFrame.Angles(0, math.rad(45), 0)
	end
	return base
end

-- Shows / hides a note piece (a triangle note is a stack of slabs under an invisible anchor).
local function setNoteTransparency(part: BasePart, value: number)
	if part:GetAttribute("Triangle") then
		for _, slab in part:GetChildren() do
			if slab:IsA("BasePart") then
				slab.Transparency = value
			end
		end
		return
	end
	part.Transparency = value
end

-- Moves a note piece; a triangle's slabs follow its anchor (apex towards -Z, the far end of the lane).
local function moveNote(part: BasePart, cframe: CFrame)
	part.CFrame = cframe
	if part:GetAttribute("Triangle") then
		local width = TRI_BASE * TRI_SIZE * NOTE_SCALE
		local height = width * 0.866
		for k, slab in part:GetChildren() do
			if slab:IsA("BasePart") then
				local z = -height / 2 + (k - 0.5) * height / TRI_SLABS
				-- Each slab sits a hair higher than the one before: slabs overlap slightly, and two surfaces at the
				-- same height would flicker against each other.
				slab.CFrame = cframe * CFrame.new(0, k * 0.012, z)
			end
		end
	end
end

local function withCommas(n: number): string
	local text = tostring(math.floor(n))
	local out = text:reverse():gsub("(%d%d%d)", "%1,"):reverse()
	return (out:gsub("^,", ""))
end

-- Plays one segment. Returns a function that aborts the run early.
function RhythmLane3D.play(segment: RhythmEngine.Segment, options: Options): () -> ()
	local scrollMs = options.scrollMs or SCROLL_MS
	local session = RhythmEngine.Session.new(segment, {
		latencyMs = options.latencyMs,
		chartOffsetMs = options.chartOffsetMs,
	})

	-- Time source (same default clock as the 2D overlay)
	local leadIn = options.leadInMs or 2000
	local firstNoteMs = session.notes[1].timeMs
	local clockStart = os.clock()
	local getSongTimeMs = options.getSongTimeMs
		or function(): number
			return (os.clock() - clockStart) * 1000 + firstNoteMs - leadIn
		end

	local dayLook = not UiTheme.get().night
	local origin = boardOrigin()
	local folder = make("Folder", { Name = "RhythmLane3D" }, Workspace)

	-- Board: one dark strip per lane, a neon hit line and a tap pad that flashes on hits.
	local pads: { BasePart } = {}
	local beams: { { BasePart } } = {} -- a light shaft up the lane, in slices that fade out towards the far end
	local diamonds: { BasePart } = {} -- a glowing diamond on the hit point
	for lane = 0, 3 do
		local color = laneColor(lane)
		-- The lane floor: tinted glass in the lane's colour (pastel by day, deep neon-tinted by night), made of
		-- slices that get more see-through towards the far end, so the lane fades away into the distance.
		local hueName = Palette.LaneOrder[lane + 1]
		local floorColor = if dayLook
			then Palette.hue(hueName, "Day"):Lerp(Palette.hue(hueName, "Night"), 0.32)
			else color:Lerp(Color3.new(0, 0, 0), 0.93) -- nearly black glass: the notes stand out against it
		local slices = 8
		local sliceLength = (LANE_LENGTH + 6) / slices
		for k = 0, slices - 1 do
			local zCenter = 6 - sliceLength * (k + 0.5)
			local far = math.clamp(-zCenter / LANE_LENGTH, 0, 1)
			local slice = solidProps(floorColor)
			slice.Name = `Lane{lane}_{k}`
			slice.Size = Vector3.new(LANE_WIDTH - 0.15, 0.2, sliceLength + 0.02)
			slice.CFrame = origin * CFrame.new(laneX(lane), 0.1, zCenter)
			slice.Material = Enum.Material.SmoothPlastic
			slice.Transparency = (if dayLook then 0.02 else 0.04) + 0.85 * far ^ 1.6
			make("Part", slice, folder)
		end

		-- Rails along both edges of the lane (neon at night, soft glowing pastel by day).
		local railColor = color
		for _, side in { -1, 1 } do
			local rail = solidProps(railColor)
			rail.Name = `Rail{lane}`
			rail.Size = Vector3.new(0.16, 0.3, LANE_LENGTH + 6)
			rail.CFrame = origin
				* CFrame.new(laneX(lane) + side * (LANE_WIDTH - 0.15 - 0.16) / 2, 0.2, -LANE_LENGTH / 2 + 3)
			rail.Material = Enum.Material.Neon
			rail.Transparency = 0.05
			make("Part", rail, folder)
		end

		local line = solidProps(color)
		line.Name = `HitLine{lane}`
		line.Size = Vector3.new(LANE_WIDTH - 0.15, 0.3, 0.5)
		line.CFrame = origin * CFrame.new(laneX(lane), 0.2, 0)
		line.Material = Enum.Material.Neon
		make("Part", line, folder)

		-- The judgement zone: a wide pale band for Great, and inside it a bright one for Perfect, as wide as the real
		-- windows (a note moves LANE_LENGTH studs in scrollMs). A note whose middle is in the bright band is Perfect.
		local windows = RhythmEngine.Judge.DefaultWindows
		for _, band in { { windows.Great, 0.82, 0.28 }, { windows.Perfect, 0.5, 0.18 } } do
			local half = LANE_LENGTH * band[1] / scrollMs
			local zone =
				solidProps(if band[3] < 0.25 then Color3.new(1, 1, 1) else color:Lerp(Color3.new(1, 1, 1), 0.5))
			zone.Name = `Zone{lane}`
			zone.Size = Vector3.new(LANE_WIDTH - 0.3, 0.06, half * 2)
			zone.CFrame = origin * CFrame.new(laneX(lane), 0.21 + band[3] * 0.05, 0)
			zone.Material = Enum.Material.Neon
			zone.Transparency = band[2]
			make("Part", zone, folder)
		end

		local pad = solidProps(color)
		pad.Name = `Pad{lane}`
		pad.Size = Vector3.new(LANE_WIDTH - 0.3, 0.1, 2.6)
		pad.CFrame = origin * CFrame.new(laneX(lane), 0.25, 1.6)
		pad.Material = Enum.Material.Neon
		pad.Transparency = 1
		pads[lane + 1] = make("Part", pad, folder)

		-- A shaft of light up the lane while a key is pressed (and a button flash, see pressFx): neon slices, strong at the
		-- hit line and fading away towards the far end, and a diamond of light on the hit point.
		local shaft: { BasePart } = {}
		for k = 0, BEAM_SLICES - 1 do
			local slice = solidProps(color:Lerp(Color3.new(1, 1, 1), 0.45))
			slice.Name = `Beam{lane}_{k}`
			slice.Size = Vector3.new(LANE_WIDTH - 0.15, 0.12, BEAM_SLICE_LENGTH)
			slice.CFrame = origin * CFrame.new(laneX(lane), 0.32, -BEAM_SLICE_LENGTH * (k + 0.5))
			slice.Material = Enum.Material.Neon
			slice.Transparency = 1
			shaft[k + 1] = make("Part", slice, folder)
		end
		beams[lane + 1] = shaft

		local diamond = solidProps(color:Lerp(Color3.new(1, 1, 1), 0.6))
		diamond.Name = `HitDiamond{lane}`
		diamond.Size = Vector3.new(DIAMOND_SIZE, 0.1, DIAMOND_SIZE)
		diamond.CFrame = origin * CFrame.new(laneX(lane), 0.36, 0) * CFrame.Angles(0, math.pi / 4, 0)
		diamond.Material = Enum.Material.Neon
		diamond.Transparency = 1
		diamonds[lane + 1] = make("Part", diamond, folder)
	end

	-- Note pieces are made only when a note comes into view and go back to a pool when it is done. A Hard chart
	-- has ~450 notes (a triangle is 15 parts), but never more than about ten are on screen at once, so the
	-- pool stays small instead of creating ~2000 parts at the start of the run.
	local noteParts: { [number]: BasePart? } = {}
	local pools: { [number]: { BasePart } } = { [0] = {}, [1] = {}, [2] = {}, [3] = {} }
	local function acquireNote(index: number, lane: number): BasePart
		local pool = pools[lane]
		local part = table.remove(pool)
		if not part then
			part = makeNotePart(lane, folder)
		end
		noteParts[index] = part :: BasePart
		return part :: BasePart
	end
	local function releaseNote(index: number, lane: number)
		local part = noteParts[index]
		if part then
			setNoteTransparency(part, 1)
			noteParts[index] = nil
			table.insert(pools[lane], part)
		end
	end

	-- Beat lines: thin lines across the board that scroll down with the music, one per beat.
	local beatList: { number } = options.beatTimesMs or {}
	if #beatList == 0 and options.bpm and options.bpm > 0 then
		local step = 60000 / options.bpm
		local t = firstNoteMs - 16 * step
		while t < session.notes[#session.notes].timeMs + step do
			table.insert(beatList, t)
			t += step
		end
	end
	local BEAT_POOL = 24
	local beatParts: { BasePart } = {}
	for k = 1, BEAT_POOL do
		local part = solidProps(if dayLook then Color3.new(1, 1, 1) else Palette.Hues.Fuji.Night)
		part.Name = "BeatLine"
		part.Size = Vector3.new(LANE_WIDTH * 4 - 0.15, 0.08, 0.1)
		part.Material = Enum.Material.Neon
		part.Transparency = 1
		beatParts[k] = make("Part", part, folder)
	end
	local beatLow = 1

	-- Out on the plaza beside the lanes (the lanes themselves stay clean so the notes read well):
	-- a floor whose tiles light up in a wave that runs towards the player on the beat: neon disco floor by night,
	-- soft pastel candy tiles by day. (No tall glowing bars or lamp posts: they dazzle.)
	local tiles: { { part: BasePart, row: number, col: number } } = {}
	local TILE = 4
	local TILE_ROWS = 10
	local tileBase = if dayLook then Color3.fromRGB(255, 244, 250) else Color3.fromRGB(20, 14, 60)
	do
		for _, side in { -1, 1 } do
			for col = 0, 2 do
				for row = 0, TILE_ROWS - 1 do
					local part = solidProps(tileBase)
					part.Name = "PlazaTile"
					part.Size = Vector3.new(TILE - 0.3, 0.1, TILE - 0.3)
					part.CFrame = origin * CFrame.new(side * (2 * LANE_WIDTH + 5 + col * TILE), 0.12, 2 - row * TILE)
					part.Material = if dayLook then Enum.Material.SmoothPlastic else Enum.Material.Neon
					table.insert(tiles, { part = make("Part", part, folder) :: BasePart, row = row, col = col })
				end
			end
		end
	end

	-- Judgement / combo text floating above the hit line.
	local textAnchor = make("Part", {
		Name = "TextAnchor",
		Anchored = true,
		CanCollide = false,
		CanQuery = false,
		CanTouch = false,
		Transparency = 1,
		Size = Vector3.new(1, 1, 1),
		CFrame = origin * CFrame.new(0, 8, -6),
	}, folder)
	local billboard = make("BillboardGui", {
		Adornee = textAnchor,
		AlwaysOnTop = true,
		Size = UDim2.fromOffset(300, 135),
		ResetOnSpawn = false,
	}, textAnchor)
	local judgementLabel = make("TextLabel", {
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.fromScale(0.5, 0),
		Size = UDim2.fromScale(1, 0.42),
		Text = "",
		TextScaled = true,
		Font = UiTheme.get().head,
		TextColor3 = Palette.Base.Washi,
		TextStrokeTransparency = 0.4,
	}, billboard) :: TextLabel
	local comboLabel = make("TextLabel", {
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.fromScale(0.5, 0.46),
		Size = UDim2.fromScale(0.6, 0.22),
		Text = "",
		TextScaled = true,
		Font = UiTheme.get().head,
		TextColor3 = Palette.Hues.Yuzu.Night,
		TextStrokeTransparency = 0.2,
		TextStrokeColor3 = Palette.Base.Sumi,
	}, billboard) :: TextLabel
	local offsetLabel = make("TextLabel", {
		BackgroundTransparency = 1,
		Position = UDim2.fromScale(0, 0.82),
		Size = UDim2.fromScale(1, 0.18),
		Text = "",
		TextScaled = true,
		Font = Enum.Font.Gotham,
		TextColor3 = Palette.Base.Washi,
		TextTransparency = 0.3,
		TextStrokeTransparency = 0.6,
	}, billboard) :: TextLabel

	-- Tap buttons for touch / mouse (the keyboard keys work as well).
	local gui = make("ScreenGui", {
		Name = "RhythmLane3DButtons",
		ResetOnSpawn = false,
		IgnoreGuiInset = true,
		DisplayOrder = 50,
	}, nil) :: ScreenGui
	local theme = UiTheme.get()
	-- Score: a small framed panel, the number in the accent colour with a dark outline.
	local scorePanel = make("Frame", {
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -16, 0, 10),
		Size = UDim2.fromOffset(190, 60),
	}, gui) :: Frame
	UiTheme.stylePanel(scorePanel, theme, 14)
	local scoreTitle = make("TextLabel", {
		Position = UDim2.fromOffset(12, 4),
		Size = UDim2.new(1, -24, 0, 14),
		BackgroundTransparency = 1,
		Text = Lang.t("SCORE"),
		TextScaled = true,
		TextXAlignment = Enum.TextXAlignment.Left,
	}, scorePanel) :: TextLabel
	UiTheme.styleText(scoreTitle, theme, "body")
	scoreTitle.TextTransparency = 0.25
	local scoreLabel = make("TextLabel", {
		Position = UDim2.fromOffset(12, 18),
		Size = UDim2.new(1, -24, 0, 36),
		BackgroundTransparency = 1,
		Text = "0",
		TextScaled = true,
		TextXAlignment = Enum.TextXAlignment.Right,
		Font = theme.head,
		TextColor3 = if theme.night then Palette.Hues.Yuzu.Night else Color3.fromHex("#FF4FA3"),
		TextStrokeColor3 = if theme.night then Palette.Base.YoruSky else Color3.new(1, 1, 1),
		TextStrokeTransparency = 0,
	}, scorePanel) :: TextLabel
	local onTap: (number) -> () = function() end
	local buttonRow = make("Frame", {
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.fromScale(0.5, 0.98),
		Size = UDim2.fromScale(0.9, 0.2),
		BackgroundTransparency = 1,
	}, gui)
	make("UISizeConstraint", { MaxSize = Vector2.new(520, 200) }, buttonRow)
	local laneButtons: { [number]: TextButton } = {}
	local laneGlows: { [number]: Frame } = {}
	local laneScales: { [number]: UIScale } = {}
	for lane = 0, 3 do
		local button = make("TextButton", {
			Position = UDim2.fromScale(lane / 4, 0),
			Size = UDim2.new(0.25, -6, 1, 0),
			AutoButtonColor = false,
			Text = `{SHAPE_GLYPHS[laneShape(lane)]}\n{KEY_LABELS[lane + 1]}`,
			TextScaled = true,
		}, buttonRow) :: TextButton
		make("UITextSizeConstraint", { MaxTextSize = 30 }, button)
		laneButtons[lane] = button
		UiTheme.styleButton(button, theme, Palette.LaneOrder[lane + 1])
		-- Press feedback: a bright flash over the button and a quick squash.
		local glow = make("Frame", {
			Size = UDim2.fromScale(1, 1),
			BackgroundColor3 = Palette.hue(Palette.LaneOrder[lane + 1], "Night"):Lerp(Color3.new(1, 1, 1), 0.65),
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
			Active = false,
			ZIndex = 30,
		}, button) :: Frame
		make("UICorner", { CornerRadius = UDim.new(0, 14) }, glow)
		make("UIStroke", { Color = Color3.new(1, 1, 1), Thickness = 3, Transparency = 1 }, glow)
		laneGlows[lane] = glow
		laneScales[lane] = make("UIScale", {}, button) :: UIScale
		button.InputBegan:Connect(function(input: InputObject)
			local t = input.UserInputType
			if t == Enum.UserInputType.Touch or t == Enum.UserInputType.MouseButton1 then
				onTap(lane)
			end
		end)
	end
	gui.Parent = (Players.LocalPlayer :: Player):WaitForChild("PlayerGui")

	local metronome: Sound? = nil
	if options.metronome and options.bpm and not options.getSongTimeMs then
		metronome = make("Sound", { SoundId = METRONOME_SOUND, Volume = 0.4 }, folder) :: Sound
	end

	-- Camera: behind the character, looking down the lane. Restored when the run ends.
	local camera = Workspace.CurrentCamera
	local savedCameraType: Enum.CameraType? = nil
	local savedCameraCFrame: CFrame? = nil
	if camera then
		savedCameraType = camera.CameraType
		savedCameraCFrame = camera.CFrame
		camera.CameraType = Enum.CameraType.Scriptable
		-- Back off just enough that all four lanes fit the screen width: far for a portrait phone,
		-- close for landscape. It never goes in front of the character's side of the hit line.
		local viewport = camera.ViewportSize
		local aspect = math.max(viewport.X, 1) / math.max(viewport.Y, 1)
		local halfFovTan = math.tan(math.rad(camera.FieldOfView) / 2)
		local back = math.clamp(LANE_WIDTH * 4 * 0.6 / (halfFovTan * aspect), 9, 34)
		back = math.max(back, HIT_AHEAD + 2)
		camera.CFrame = CFrame.lookAt(
			origin:PointToWorldSpace(Vector3.new(0, back * 0.7 + 2, back)),
			origin:PointToWorldSpace(Vector3.new(0, 0, -LANE_LENGTH * 0.3))
		)
	end
	local character = (Players.LocalPlayer :: Player).Character
	if character then
		for _, d in character:GetDescendants() do
			if d:IsA("BasePart") then
				d.LocalTransparencyModifier = CHARACTER_FADE
			end
		end
	end
	RhythmOverlay.setMovementEnabled(false)

	-- Hide the garden (plots, frames, posts, marks, beacon, plants, spirit orbs and their lights): it sits around and
	-- in front of the camera and covers the lane. Everything is put back as it was when the run ends.
	local hidden: { Instance } = {}
	local previous: { [Instance]: number } = {}
	local function hideWorld(inst: Instance)
		if inst:IsA("BasePart") then
			previous[inst] = inst.LocalTransparencyModifier
			inst.LocalTransparencyModifier = 1
			table.insert(hidden, inst)
		elseif
			inst:IsA("PointLight")
			or inst:IsA("SurfaceGui")
			or inst:IsA("BillboardGui")
			or inst:IsA("ParticleEmitter")
		then
			(inst :: any).Enabled = false
			table.insert(hidden, inst)
		end
	end
	-- Anything standing in the lane corridor (a plant, a prop) is hidden too, whatever it is: it would block the notes.
	-- Big things (the ground) and flat things (floor tiles) stay.
	local corridorParams = OverlapParams.new()
	corridorParams.FilterType = Enum.RaycastFilterType.Exclude
	corridorParams.FilterDescendantsInstances = if character then { folder, character } else { folder }
	local function hideCorridor()
		local width = LANE_WIDTH * 4 + 10
		local box = origin * CFrame.new(0, 9, -LANE_LENGTH / 2 + 10)
		for _, part in Workspace:GetPartBoundsInBox(box, Vector3.new(width, 18, LANE_LENGTH + 30), corridorParams) do
			local size = part.Size
			if previous[part] == nil and size.Y > 1.5 and math.max(size.X, size.Z) < 40 then
				hideWorld(part)
			end
		end
	end
	hideCorridor()

	-- Parts that appear during the run (a plant that grows a stage, a spirit) are hidden too.
	local worldConns: { RBXScriptConnection } = {}
	for _, rootName in { "Garden", "PlotVisuals", "PetFx" } do
		local root = Workspace:FindFirstChild(rootName)
		if root then
			for _, d in root:GetDescendants() do
				hideWorld(d)
			end
			table.insert(worldConns, root.DescendantAdded:Connect(hideWorld))
		end
	end

	-- Feedback
	local judgementToken = 0
	local scorePerNote = 1000000 / #session.notes
	local score = 0.0
	-- "+N" floats up from the tapped lane and fades out.
	local function popScore(result: RhythmEngine.HitResult, gained: number)
		local button = laneButtons[result.lane]
		if result.judgement == "Miss" or not button then
			return
		end
		local pop = make("TextLabel", {
			AnchorPoint = Vector2.new(0.5, 1),
			Position = UDim2.fromOffset(
				button.AbsolutePosition.X + button.AbsoluteSize.X / 2,
				button.AbsolutePosition.Y - 4
			),
			Size = UDim2.fromOffset(120, 36),
			BackgroundTransparency = 1,
			Text = `+{math.floor(gained + 0.5)}`,
			TextScaled = true,
			Font = UiTheme.get().head,
			TextColor3 = JUDGEMENT_COLORS[result.judgement],
			TextStrokeTransparency = 0.15,
			TextStrokeColor3 = Palette.Base.Sumi,
		}, gui) :: TextLabel
		local info = TweenInfo.new(0.55, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
		TweenService:Create(pop, info, {
			Position = pop.Position - UDim2.fromOffset(0, 70),
			TextTransparency = 1,
			TextStrokeTransparency = 1,
		}):Play()
		task.delay(0.6, function()
			pop:Destroy()
		end)
	end

	local function showResult(result: RhythmEngine.HitResult)
		releaseNote(result.noteIndex, result.lane)
		local gained = scorePerNote * RhythmEngine.Judge.Weight[result.judgement]
		score += gained
		scoreLabel.Text = withCommas(math.floor(score + 0.5))
		scorePanel.Size = UDim2.fromOffset(204, 65)
		TweenService:Create(
			scorePanel,
			TweenInfo.new(0.18, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
			{ Size = UDim2.fromOffset(190, 60) }
		):Play()
		popScore(result, gained)
		judgementToken += 1
		local token = judgementToken
		judgementLabel.Text = result.judgement
		judgementLabel.TextColor3 = JUDGEMENT_COLORS[result.judgement]
		comboLabel.Text = if result.combo >= 5 then `{result.combo} COMBO` else ""
		-- Pop: the judgement and the combo spring in from a bigger size; milestones pop harder.
		judgementLabel.Size = UDim2.fromScale(1.35, 0.55)
		TweenService:Create(
			judgementLabel,
			TweenInfo.new(0.22, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
			{ Size = UDim2.fromScale(1, 0.42) }
		):Play()
		if result.combo >= 5 then
			local milestone = result.combo % 25 == 0
			comboLabel.Size = if milestone then UDim2.fromScale(0.85, 0.3) else UDim2.fromScale(0.68, 0.25)
			TweenService:Create(
				comboLabel,
				TweenInfo.new(0.25, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
				{ Size = UDim2.fromScale(0.6, 0.22) }
			):Play()
		end
		offsetLabel.Text = if result.judgement == "Miss"
			then ""
			else Lang.t(if result.offsetMs > 0 then `+{result.offsetMs}ms late` else `{result.offsetMs}ms early`)
		if result.judgement ~= "Miss" then
			pads[result.lane + 1].Transparency = if result.judgement == "Perfect" then 0.2 else 0.5
		end
		task.delay(0.5, function()
			if token == judgementToken then
				judgementLabel.Text = ""
				offsetLabel.Text = ""
				if result.judgement == "Miss" then
					comboLabel.Text = ""
				end
			end
		end)
	end

	-- Tap feedback, whether or not a note was hit: the button flashes and squashes, a beam lights the lane.
	local function pressFx(lane: number)
		local glow = laneGlows[lane]
		local scale = laneScales[lane]
		if glow then
			glow.BackgroundTransparency = 0.25
			local stroke = glow:FindFirstChildOfClass("UIStroke")
			if stroke then
				stroke.Transparency = 0
				TweenService:Create(stroke, TweenInfo.new(0.3), { Transparency = 1 }):Play()
			end
			TweenService:Create(glow, TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
				BackgroundTransparency = 1,
			}):Play()
		end
		if scale then
			scale.Scale = 0.88
			TweenService:Create(scale, TweenInfo.new(0.2, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
				Scale = 1,
			}):Play()
		end
		local shaft = beams[lane + 1]
		if shaft then
			for k, slice in shaft do
				slice.Transparency = BEAM_FADE[k] or 0.95
				TweenService:Create(slice, TweenInfo.new(0.34, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
					Transparency = 1,
				}):Play()
			end
		end
		local diamond = diamonds[lane + 1]
		if diamond then
			diamond.Size = Vector3.new(DIAMOND_SIZE * 0.7, 0.1, DIAMOND_SIZE * 0.7)
			diamond.Transparency = 0.05
			TweenService:Create(diamond, TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
				Size = Vector3.new(DIAMOND_SIZE * 1.25, 0.1, DIAMOND_SIZE * 1.25),
				Transparency = 1,
			}):Play()
		end
	end

	-- A ring bursts out of the hit line when a note is hit, in the colour of the judgement.
	local function hitFx(lane: number, judgement: string)
		local ring = make("Part", {
			Anchored = true,
			CanCollide = false,
			CanQuery = false,
			CanTouch = false,
			CastShadow = false,
			Shape = Enum.PartType.Cylinder,
			Material = Enum.Material.SmoothPlastic,
			Color = (JUDGEMENT_COLORS :: any)[judgement] or Color3.new(1, 1, 1),
			Transparency = 0.15,
			Size = Vector3.new(0.12, 1.2, 1.2),
			CFrame = origin * CFrame.new(laneX(lane), 0.4, 0) * CFrame.Angles(0, 0, math.pi / 2),
		}, folder) :: Part
		local big = if judgement == "Perfect" then 5.5 else 4
		TweenService:Create(ring, TweenInfo.new(0.35, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
			Size = Vector3.new(0.12, big, big),
			Transparency = 1,
		}):Play()
		task.delay(0.4, function()
			ring:Destroy()
		end)
	end

	-- The equipped spirit cheers beside the lane: it hops on every beat, jumps higher on a Perfect and spins at every
	-- 10 combo. What it has grown (size, glow, ride ...) is on it.
	local cheerModel: Model? = nil
	local cheerBase = origin * CFrame.new(-(LANE_WIDTH * 2 + 4.2), 0, -1) * CFrame.Angles(0, math.pi, 0)
	local cheerRainbow: BasePart? = nil
	local cheerHopUntil = 0
	local cheerSpinUntil = 0
	local snapshot = GardenState.get()
	if snapshot and snapshot.equippedSpirit then
		for _, spirit in snapshot.spirits do
			if spirit.id == snapshot.equippedSpirit and Spirits.get(spirit.kind) then
				local traits = spirit.traits or {}
				local model = SpiritModel.create(spirit.kind, traits)
				model:ScaleTo(1.1 * math.min(2.2, Spirits.sizeFactor(Spirits.levelOf(spirit.xp or 0), traits)))
				model:PivotTo(cheerBase)
				model.Parent = folder
				cheerModel = model
				cheerRainbow = model:FindFirstChild("RainbowRing") :: BasePart?
			end
		end
	end

	-- Every 10 combos: a big "N COMBO!" springs in at the top of the screen in a new colour each time, and a
	-- gold ring bursts out of every lane. 50 and 100 are bigger still.
	local comboBurst = make("TextLabel", {
		Name = "ComboBurst",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.3),
		Size = UDim2.fromOffset(300, 52),
		BackgroundTransparency = 1,
		Text = "",
		TextScaled = true,
		Font = UiTheme.get().head,
		TextStrokeTransparency = 0,
		TextStrokeColor3 = Palette.Base.Sumi,
		ZIndex = 5,
	}, gui) :: TextLabel
	local comboBurstScale = make("UIScale", { Scale = 1 }, comboBurst) :: UIScale
	local burstToken = 0
	local function celebrateCombo(combo: number)
		cheerSpinUntil = os.clock() + 0.7
		burstToken += 1
		local token = burstToken
		local hue = Palette.Hues[Palette.LaneOrder[(combo // 10 - 1) % #Palette.LaneOrder + 1]]
		local big = combo % 50 == 0
		comboBurst.Text = `{combo} COMBO!`
		comboBurst.TextColor3 = hue.Night:Lerp(Color3.new(1, 1, 1), 0.25)
		comboBurst.TextTransparency = 0
		comboBurst.TextStrokeTransparency = 0
		comboBurst.Position = UDim2.fromScale(0.5, 0.3)
		comboBurstScale.Scale = if big then 0.4 else 0.6
		TweenService:Create(
			comboBurstScale,
			TweenInfo.new(0.35, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
			{ Scale = if big then 1.3 else 1 }
		):Play()
		task.delay(0.65, function()
			if token ~= burstToken then
				return
			end
			TweenService:Create(comboBurst, TweenInfo.new(0.4, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
				TextTransparency = 1,
				TextStrokeTransparency = 1,
				Position = UDim2.fromScale(0.5, 0.24),
			}):Play()
		end)
		-- A wave across the four lanes: each button lights up and a ring bursts out of its lane...
		for lane = 0, 3 do
			task.delay(lane * 0.05, function()
				pressFx(lane)
				hitFx(lane, "Perfect")
			end)
		end
		-- ...and notes and stars fly up from the buttons, spinning, in the colours of the four lanes.
		local glyphs = { "\u{266A}", "\u{266B}", "\u{2605}", "\u{2726}" }
		local count = if big then 28 else 16
		for i = 1, count do
			local lane = (i - 1) % 4
			local button = laneButtons[lane]
			if not button then
				continue
			end
			local color = Palette.hue(Palette.LaneOrder[lane + 1], "Night"):Lerp(Color3.new(1, 1, 1), 0.2)
			local startX = button.AbsolutePosition.X + button.AbsoluteSize.X * (0.2 + math.random() * 0.6)
			local startY = button.AbsolutePosition.Y
			local piece = make("TextLabel", {
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.fromOffset(startX, startY),
				Size = UDim2.fromOffset(34, 34),
				BackgroundTransparency = 1,
				Text = glyphs[math.random(#glyphs)],
				TextSize = 28,
				Font = Enum.Font.GothamBlack,
				TextColor3 = color,
				TextStrokeTransparency = 0.3,
				TextStrokeColor3 = Palette.Base.Sumi,
				Rotation = math.random(-30, 30),
				ZIndex = 4,
			}, gui) :: TextLabel
			local rise = 150 + math.random() * 130
			local drift = (math.random() - 0.5) * 120
			local life = 0.8 + math.random() * 0.4
			task.delay(math.random() * 0.15, function()
				TweenService:Create(piece, TweenInfo.new(life, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
					Position = UDim2.fromOffset(startX + drift, startY - rise),
					Rotation = piece.Rotation + math.random(-180, 180),
					TextTransparency = 1,
					TextStrokeTransparency = 1,
				}):Play()
				task.delay(life + 0.05, function()
					piece:Destroy()
				end)
			end)
		end
	end

	local hitSounds = HitSounds.create(folder)

	local finished = false
	onTap = function(lane: number)
		if finished then
			return
		end
		pressFx(lane)
		local hit, misses = session:hit(lane, getSongTimeMs())
		for _, m in misses do
			showResult(m)
		end
		if hit then
			showResult(hit)
			if hit.judgement ~= "Miss" then
				hitFx(lane, hit.judgement)
				hitSounds.play(hit.judgement)
				if hit.judgement == "Perfect" then
					cheerHopUntil = os.clock() + 0.4
				end
				if hit.combo >= 10 and hit.combo % 10 == 0 then
					celebrateCombo(hit.combo)
				end
			end
		end
	end

	local inputConn = UserInputService.InputBegan:Connect(function(input: InputObject, gameProcessed: boolean)
		if gameProcessed then
			return
		end
		local lane = LANE_KEYS[input.KeyCode]
		if lane then
			onTap(lane)
		end
	end)

	local lastBeat = -math.huge
	local nextBeat = 1
	local firstActive = 1
	local renderConn: RBXScriptConnection
	local function finish(summary: RhythmEngine.Summary?)
		if finished then
			return
		end
		finished = true
		for _, inst in hidden do
			if inst:IsA("BasePart") then
				inst.LocalTransparencyModifier = previous[inst] or 0
			else
				(inst :: any).Enabled = true
			end
		end
		renderConn:Disconnect()
		inputConn:Disconnect()
		for _, conn in worldConns do
			conn:Disconnect()
		end
		if camera then
			camera.CameraType = savedCameraType or Enum.CameraType.Custom
			if savedCameraCFrame then
				camera.CFrame = savedCameraCFrame
			end
		end
		if character then
			for _, d in character:GetDescendants() do
				if d:IsA("BasePart") then
					d.LocalTransparencyModifier = 0
				end
			end
		end
		RhythmOverlay.setMovementEnabled(true)
		gui:Destroy()
		task.delay(0.6, function()
			folder:Destroy()
		end)
		if summary then
			options.onFinished(summary)
		end
	end

	local nextCorridorScan = 0
	renderConn = RunService.RenderStepped:Connect(function()
		local now = getSongTimeMs()
		if os.clock() >= nextCorridorScan then
			nextCorridorScan = os.clock() + 0.5
			hideCorridor()
		end

		local cheering = cheerModel
		if cheering then
			local clock = os.clock()
			local beatPos = (now - firstNoteMs) / (60000 / (options.bpm or 120))
			local height = math.abs(math.sin(beatPos * math.pi)) * 0.7
			if clock < cheerHopUntil then
				height += math.sin((1 - (cheerHopUntil - clock) / 0.4) * math.pi) * 1.6
			end
			local spin = if clock < cheerSpinUntil then (1 - (cheerSpinUntil - clock) / 0.7) * math.pi * 2 else 0
			cheering:PivotTo(cheerBase * CFrame.new(0, height, 0) * CFrame.Angles(0, spin, 0))
			local ring = cheerRainbow
			if ring then
				ring.Color = Color3.fromHSV((clock * 0.25) % 1, 0.65, 1)
			end
		end

		if #tiles > 0 then
			local beatLength = 60000 / (options.bpm or 120)
			local beatPos = (now - firstNoteMs) / beatLength
			-- the lit wave on the floor runs towards the player, two rows per beat
			for _, tile in tiles do
				local wave = (tile.row - beatPos * 2) % 6
				local glow = math.clamp(1 - wave / 2, 0, 1)
				local color = laneColor((tile.row + tile.col) % 4)
				local strength = if dayLook then 0.75 * glow else 0.15 + 0.85 * glow
				tile.part.Color = tileBase:Lerp(color, strength)
			end
		end

		for _, m in session:update(now) do
			showResult(m)
		end

		-- Metronome on the default clock: tick on each beat from the first note.
		if metronome and options.beatTimesMs then
			-- Real beat times of the song (they drift from a fixed bpm over a long chart).
			local beats = options.beatTimesMs
			while nextBeat <= #beats and beats[nextBeat] <= now do
				if now - beats[nextBeat] < 120 then
					metronome:Play()
				end
				nextBeat += 1
			end
		elseif metronome and options.bpm then
			local beat = math.floor((now - firstNoteMs) / (60000 / options.bpm))
			if beat > lastBeat and beat >= -4 then
				lastBeat = beat
				metronome:Play()
			end
		end

		-- Notes are drawn at their latency-corrected time so they cross the hit line
		-- exactly when the player should tap.
		-- Only the notes inside the visible window are touched each frame (a 90 s Hard chart has ~400),
		-- and the ones that are done are hidden once and skipped from then on.
		local latency = session.latencyMs
		local goodWindow = RhythmEngine.Judge.DefaultWindows.Good
		local notes = session.notes
		local i = firstActive
		while i <= #notes do
			local note = notes[i]
			local untilHit = note.timeMs + latency - now
			if untilHit > scrollMs then
				break
			end
			if session.offsets[note.index] ~= nil or untilHit < -goodWindow then
				releaseNote(note.index, note.lane)
				if i == firstActive then
					firstActive += 1
				end
			else
				local part = noteParts[note.index] or acquireNote(note.index, note.lane)
				setNoteTransparency(part, 0)
				local z = -LANE_LENGTH * (untilHit / scrollMs)
				moveNote(part, noteCFrame(origin, note.lane, z))
			end
			i += 1
		end

		-- Beat lines: the ones inside the visible window, fading in from the far end.
		while beatLow <= #beatList and beatList[beatLow] + latency - now < -150 do
			beatLow += 1
		end
		local used = 0
		local b = beatLow
		while b <= #beatList and used < BEAT_POOL do
			local untilBeat = beatList[b] + latency - now
			if untilBeat > scrollMs then
				break
			end
			used += 1
			local line = beatParts[used]
			line.CFrame = origin * CFrame.new(0, 0.3, -LANE_LENGTH * (untilBeat / scrollMs))
			line.Transparency = 0.45 + 0.5 * math.clamp(untilBeat / scrollMs, 0, 1)
			b += 1
		end
		for k = used + 1, BEAT_POOL do
			beatParts[k].Transparency = 1
		end

		for _, pad in pads do
			if pad.Transparency < 1 then
				pad.Transparency = math.min(1, pad.Transparency + 0.06)
			end
		end

		-- With real audio the run ends when the song ends, so the ending is never cut off.
		local audioDone = options.isAudioDone == nil or options.isAudioDone()
		if now > session:endTimeMs() and audioDone then
			finish(session:getSummary())
		end
	end)

	return function()
		finish(nil)
	end
end

return RhythmLane3D
