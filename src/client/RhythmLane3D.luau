--!strict
-- 3D rhythm lane: four lanes laid on the ground in front of the player, notes slide toward
-- the player and are tapped on the hit line. Same play() contract as RhythmOverlay, so the
-- caller can swap between the two. Everything is client-side (local parts only).
--
-- Prototype only: shapes, sizes and the camera framing are placeholders to tune in Studio.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local Palette = require(ReplicatedStorage.Shared.Palette)
local RhythmEngine = require(ReplicatedStorage.Shared.RhythmEngine)
local RhythmOverlay = require(script.Parent.RhythmOverlay)

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
local LANE_WIDTH = 3 -- studs
local LANE_LENGTH = 50 -- studs from the hit line to where notes appear
local HIT_AHEAD = 7 -- studs between the character and the hit line
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
	local color = laneColor(lane)
	local shape = laneShape(lane)
	local props = solidProps(color)
	props.Material = Enum.Material.Neon
	props.Transparency = 1
	if shape == "Circle" then
		props.Shape = Enum.PartType.Cylinder
		props.Size = Vector3.new(0.6, 2.4, 2.4)
		return make("Part", props, parent)
	elseif shape == "Triangle" then
		props.Size = Vector3.new(0.6, 2.4, 2.4)
		return make("WedgePart", props, parent)
	elseif shape == "Diamond" then
		props.Size = Vector3.new(1.8, 0.6, 1.8)
		return make("Part", props, parent)
	end
	props.Size = Vector3.new(2.2, 0.6, 2.2)
	return make("Part", props, parent)
end

-- Orientation that lays each shape flat on the board.
local function noteCFrame(origin: CFrame, lane: number, z: number): CFrame
	local base = origin * CFrame.new(laneX(lane), 0.6, z)
	local shape = laneShape(lane)
	if shape == "Circle" or shape == "Triangle" then
		return base * CFrame.Angles(0, 0, math.rad(90))
	elseif shape == "Diamond" then
		return base * CFrame.Angles(0, math.rad(45), 0)
	end
	return base
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

	local origin = boardOrigin()
	local folder = make("Folder", { Name = "RhythmLane3D" }, Workspace)

	-- Board: one dark strip per lane, a neon hit line and a tap pad that flashes on hits.
	local pads: { BasePart } = {}
	for lane = 0, 3 do
		local color = laneColor(lane)
		local strip = solidProps(Palette.Base.YoruGround)
		strip.Name = `Lane{lane}`
		strip.Size = Vector3.new(LANE_WIDTH - 0.15, 0.2, LANE_LENGTH + 6)
		strip.CFrame = origin * CFrame.new(laneX(lane), 0.1, -LANE_LENGTH / 2 + 3)
		strip.Material = Enum.Material.SmoothPlastic
		strip.Transparency = 0.15
		make("Part", strip, folder)

		local line = solidProps(color)
		line.Name = `HitLine{lane}`
		line.Size = Vector3.new(LANE_WIDTH - 0.15, 0.3, 0.35)
		line.CFrame = origin * CFrame.new(laneX(lane), 0.2, 0)
		line.Material = Enum.Material.Neon
		make("Part", line, folder)

		local pad = solidProps(color)
		pad.Name = `Pad{lane}`
		pad.Size = Vector3.new(LANE_WIDTH - 0.3, 0.1, 2.6)
		pad.CFrame = origin * CFrame.new(laneX(lane), 0.25, 1.6)
		pad.Material = Enum.Material.Neon
		pad.Transparency = 1
		pads[lane + 1] = make("Part", pad, folder)
	end

	-- One piece per note, created up front (segments are short).
	local noteParts: { [number]: BasePart } = {}
	for _, note in session.notes do
		noteParts[note.index] = makeNotePart(note.lane, folder)
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
		CFrame = origin * CFrame.new(0, 4.5, -4),
	}, folder)
	local billboard = make("BillboardGui", {
		Adornee = textAnchor,
		AlwaysOnTop = true,
		Size = UDim2.fromOffset(360, 130),
		ResetOnSpawn = false,
	}, textAnchor)
	local judgementLabel = make("TextLabel", {
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 0.5),
		Text = "",
		TextScaled = true,
		Font = Enum.Font.GothamBlack,
		TextColor3 = Palette.Base.Washi,
		TextStrokeTransparency = 0.4,
	}, billboard) :: TextLabel
	local comboLabel = make("TextLabel", {
		BackgroundTransparency = 1,
		Position = UDim2.fromScale(0, 0.5),
		Size = UDim2.fromScale(1, 0.3),
		Text = "",
		TextScaled = true,
		Font = Enum.Font.GothamBold,
		TextColor3 = Palette.Base.Washi,
		TextStrokeTransparency = 0.5,
	}, billboard) :: TextLabel
	local offsetLabel = make("TextLabel", {
		BackgroundTransparency = 1,
		Position = UDim2.fromScale(0, 0.8),
		Size = UDim2.fromScale(1, 0.2),
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
	local onTap: (number) -> () = function() end
	local buttonRow = make("Frame", {
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.fromScale(0.5, 0.98),
		Size = UDim2.fromScale(0.9, 0.2),
		BackgroundTransparency = 1,
	}, gui)
	make("UISizeConstraint", { MaxSize = Vector2.new(520, 200) }, buttonRow)
	for lane = 0, 3 do
		local button = make("TextButton", {
			Position = UDim2.fromScale(lane / 4, 0),
			Size = UDim2.new(0.25, -6, 1, 0),
			BackgroundColor3 = laneColor(lane),
			BackgroundTransparency = 0.55,
			AutoButtonColor = false,
			Text = `{SHAPE_GLYPHS[laneShape(lane)]}\n{KEY_LABELS[lane + 1]}`,
			TextColor3 = Palette.Base.Washi,
			TextScaled = true,
			Font = Enum.Font.GothamBold,
		}, buttonRow) :: TextButton
		make("UIPadding", { PaddingTop = UDim.new(0.2, 0), PaddingBottom = UDim.new(0.2, 0) }, button)
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
		camera.CFrame = CFrame.lookAt(
			origin:PointToWorldSpace(Vector3.new(0, 11, HIT_AHEAD + 8)),
			origin:PointToWorldSpace(Vector3.new(0, 0, -LANE_LENGTH * 0.3))
		)
	end
	RhythmOverlay.setMovementEnabled(false)

	-- Feedback
	local judgementToken = 0
	local function showResult(result: RhythmEngine.HitResult)
		local part = noteParts[result.noteIndex]
		if part then
			part.Transparency = 1
		end
		judgementToken += 1
		local token = judgementToken
		judgementLabel.Text = result.judgement
		judgementLabel.TextColor3 = JUDGEMENT_COLORS[result.judgement]
		comboLabel.Text = if result.combo >= 2 then `{result.combo} combo` else ""
		offsetLabel.Text = if result.judgement == "Miss"
			then ""
			else (if result.offsetMs > 0 then `+{result.offsetMs}ms late` else `{result.offsetMs}ms early`)
		if result.judgement ~= "Miss" then
			pads[result.lane + 1].Transparency = if result.judgement == "Perfect" then 0.2 else 0.5
		end
		task.delay(0.5, function()
			if token == judgementToken then
				judgementLabel.Text = ""
				offsetLabel.Text = ""
			end
		end)
	end

	local finished = false
	onTap = function(lane: number)
		if finished then
			return
		end
		local hit, misses = session:hit(lane, getSongTimeMs())
		for _, m in misses do
			showResult(m)
		end
		if hit then
			showResult(hit)
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
	local renderConn: RBXScriptConnection
	local function finish(summary: RhythmEngine.Summary?)
		if finished then
			return
		end
		finished = true
		renderConn:Disconnect()
		inputConn:Disconnect()
		if camera then
			camera.CameraType = savedCameraType or Enum.CameraType.Custom
			if savedCameraCFrame then
				camera.CFrame = savedCameraCFrame
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

	renderConn = RunService.RenderStepped:Connect(function()
		local now = getSongTimeMs()

		for _, m in session:update(now) do
			showResult(m)
		end

		-- Metronome on the default clock: tick on each beat from the first note.
		if metronome and options.bpm then
			local beat = math.floor((now - firstNoteMs) / (60000 / options.bpm))
			if beat > lastBeat and beat >= -4 then
				lastBeat = beat
				metronome:Play()
			end
		end

		-- Notes are drawn at their latency-corrected time so they cross the hit line
		-- exactly when the player should tap.
		local latency = session.latencyMs
		for _, note in session.notes do
			local part = noteParts[note.index]
			if session.offsets[note.index] ~= nil then
				continue
			end
			local untilHit = note.timeMs + latency - now
			if untilHit > scrollMs or untilHit < -RhythmEngine.Judge.DefaultWindows.Good then
				part.Transparency = 1
			else
				part.Transparency = 0
				part.CFrame = noteCFrame(origin, note.lane, -LANE_LENGTH * (untilHit / scrollMs))
			end
		end

		for _, pad in pads do
			if pad.Transparency < 1 then
				pad.Transparency = math.min(1, pad.Transparency + 0.06)
			end
		end

		if now > session:endTimeMs() then
			finish(session:getSummary())
		end
	end)

	return function()
		finish(nil)
	end
end

return RhythmLane3D
