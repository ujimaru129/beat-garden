--!strict
-- Prototype rhythm overlay: 4 lanes, notes fall top to bottom, tap zone at the bottom.
-- Drives RhythmEngine.Session with the current song time and shows judgements and combo.
--
-- Prototype only: strings are not yet routed through the translation table,
-- and the look is placeholder (Palette night colors on a dark backdrop).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Palette = require(ReplicatedStorage.Shared.Palette)
local RhythmEngine = require(ReplicatedStorage.Shared.RhythmEngine)

local RhythmOverlay = {}

export type Options = {
	latencyMs: number?,
	chartOffsetMs: number?,
	-- Song time source. Default: a clock that starts `leadInMs` before the first note.
	-- With real audio, pass a function reading Sound.TimePosition (minus regionStartMs).
	getSongTimeMs: (() -> number)?,
	leadInMs: number?,
	-- How long a note is visible before the hit line (ms). Default SCROLL_MS; see Shared.Difficulty.
	scrollMs: number?,
	-- Metronome tick on every beat (only used with the default clock).
	bpm: number?,
	metronome: boolean?,
	onFinished: (RhythmEngine.Summary) -> (),
}

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

local SCROLL_MS = 1400 -- how long a note is visible before reaching the hit line
local HIT_LINE = 0.78 -- hit line position (fraction of lane height)
local NOTE_SIZE = 0.16 -- note height as a fraction of lane height
local METRONOME_SOUND = "rbxasset://sounds/electronicpingshort.wav"

local JUDGEMENT_COLORS: { [string]: Color3 } = {
	Perfect = Palette.Hues.Yuzu.Night,
	Great = Palette.Hues.Sora.Night,
	Good = Palette.Hues.Matcha.Night,
	Miss = Palette.Rarity.Common,
}

-- Character movement shares keys with the lanes (D), so movement is off while the overlay is up.
local savedWalkSpeed: number? = nil

local function setMovementEnabled(enabled: boolean)
	local player = Players.LocalPlayer :: Player
	-- Never wait for the PlayerModule: if it is missing, WaitForChild would block the whole run.
	local scripts = player:FindFirstChild("PlayerScripts")
	local moduleScript = scripts and scripts:FindFirstChild("PlayerModule")
	if moduleScript and moduleScript:IsA("ModuleScript") then
		local ok, err = pcall(function()
			local controls = (require(moduleScript) :: any):GetControls()
			if enabled then
				controls:Enable()
			else
				controls:Disable()
			end
		end)
		if not ok then
			warn("[RhythmOverlay] could not toggle movement:", err)
		end
		return
	end

	-- Fallback: freeze the character by walk speed.
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not humanoid then
		return
	end
	if enabled then
		if savedWalkSpeed then
			humanoid.WalkSpeed = savedWalkSpeed
			savedWalkSpeed = nil
		end
	elseif savedWalkSpeed == nil then
		savedWalkSpeed = humanoid.WalkSpeed
		humanoid.WalkSpeed = 0
	end
end

local function laneColor(lane: number): Color3
	return Palette.hue(Palette.LaneOrder[lane + 1], "Night")
end

local function laneGlyph(lane: number): string
	return SHAPE_GLYPHS[Palette.LaneShapes[lane + 1]]
end

local function make(className: string, props: { [string]: any }, children: { Instance }?): Instance
	local inst = Instance.new(className)
	for k, v in props do
		(inst :: any)[k] = v
	end
	local list: { Instance } = children or {}
	for _, child in list do
		child.Parent = inst
	end
	return inst
end

-- Plays one segment. Returns a function that aborts the run early.
function RhythmOverlay.play(segment: RhythmEngine.Segment, options: Options): () -> ()
	local scrollMs = options.scrollMs or SCROLL_MS
	local session = RhythmEngine.Session.new(segment, {
		latencyMs = options.latencyMs,
		chartOffsetMs = options.chartOffsetMs,
	})

	-- Time source
	local leadIn = options.leadInMs or 2000
	local firstNoteMs = session.notes[1].timeMs
	local clockStart = os.clock()
	local getSongTimeMs = options.getSongTimeMs
		or function(): number
			return (os.clock() - clockStart) * 1000 + firstNoteMs - leadIn
		end

	-- UI
	local gui = make("ScreenGui", {
		Name = "RhythmOverlay",
		IgnoreGuiInset = true,
		ResetOnSpawn = false,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
		DisplayOrder = 50,
	}) :: ScreenGui

	make("Frame", {
		Name = "Backdrop",
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Palette.Base.YoruSky,
		BackgroundTransparency = 0.25,
		BorderSizePixel = 0,
		Parent = gui,
	})

	local board = make("Frame", {
		Name = "Board",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.fromScale(0.5, 0),
		Size = UDim2.fromScale(0.9, 1),
		BackgroundTransparency = 1,
		Parent = gui,
	}, {
		make("UISizeConstraint", { MaxSize = Vector2.new(520, math.huge) }),
	}) :: Frame

	local lanes: { Frame } = {}
	local flashes: { Frame } = {}
	for lane = 0, 3 do
		local color = laneColor(lane)
		local laneFrame = make("Frame", {
			Name = `Lane{lane}`,
			Position = UDim2.fromScale(lane / 4, 0),
			Size = UDim2.fromScale(1 / 4, 1),
			BackgroundColor3 = Palette.Base.YoruGround,
			BackgroundTransparency = 0.3,
			BorderSizePixel = 0,
			ClipsDescendants = true,
			Parent = board,
		}, {
			make("UIStroke", { Color = color, Transparency = 0.7, Thickness = 1 }),
			-- hit line
			make("Frame", {
				Name = "HitLine",
				AnchorPoint = Vector2.new(0, 0.5),
				Position = UDim2.fromScale(0, HIT_LINE),
				Size = UDim2.new(1, 0, 0, 4),
				BackgroundColor3 = color,
				BorderSizePixel = 0,
			}),
		}) :: Frame
		lanes[lane + 1] = laneFrame

		flashes[lane + 1] = make("Frame", {
			Name = "Flash",
			Size = UDim2.fromScale(1, 1),
			BackgroundColor3 = color,
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
			ZIndex = 0,
			Parent = laneFrame,
		}) :: Frame

		-- Tap zone (below the hit line, sized for thumbs on mobile)
		local button = make("TextButton", {
			Name = "Tap",
			AnchorPoint = Vector2.new(0, 1),
			Position = UDim2.fromScale(0, 1),
			Size = UDim2.fromScale(1, 1 - HIT_LINE + 0.02),
			BackgroundColor3 = color,
			BackgroundTransparency = 0.8,
			AutoButtonColor = false,
			Text = `{laneGlyph(lane)}\n{KEY_LABELS[lane + 1]}`,
			TextColor3 = Palette.Base.Washi,
			TextScaled = true,
			Font = Enum.Font.GothamBold,
			ZIndex = 5,
			Parent = laneFrame,
		}, {
			make("UIPadding", {
				PaddingTop = UDim.new(0.25, 0),
				PaddingBottom = UDim.new(0.25, 0),
			}),
		}) :: TextButton

		button.InputBegan:Connect(function(input: InputObject)
			local t = input.UserInputType
			if t == Enum.UserInputType.Touch or t == Enum.UserInputType.MouseButton1 then
				RhythmOverlay._onTap(lane)
			end
		end)
	end

	local judgementLabel = make("TextLabel", {
		Name = "Judgement",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.42),
		Size = UDim2.fromScale(0.8, 0.08),
		BackgroundTransparency = 1,
		Text = "",
		TextScaled = true,
		Font = Enum.Font.GothamBlack,
		TextColor3 = Palette.Base.Washi,
		ZIndex = 10,
		Parent = board,
	}) :: TextLabel

	local comboLabel = make("TextLabel", {
		Name = "Combo",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(0.5, 0.05),
		BackgroundTransparency = 1,
		Text = "",
		TextScaled = true,
		Font = Enum.Font.GothamBold,
		TextColor3 = Palette.Base.Washi,
		ZIndex = 10,
		Parent = board,
	}) :: TextLabel

	local offsetLabel = make("TextLabel", {
		Name = "Offset",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.55),
		Size = UDim2.fromScale(0.5, 0.03),
		BackgroundTransparency = 1,
		Text = "",
		TextScaled = true,
		Font = Enum.Font.Gotham,
		TextColor3 = Palette.Base.Washi,
		TextTransparency = 0.3,
		ZIndex = 10,
		Parent = board,
	}) :: TextLabel

	-- One label per note, created up front (segments are short).
	local noteViews: { [number]: TextLabel } = {}
	for _, note in session.notes do
		noteViews[note.index] = make("TextLabel", {
			Name = `Note{note.index}`,
			AnchorPoint = Vector2.new(0.5, 0.5),
			Size = UDim2.fromScale(0.8, NOTE_SIZE),
			BackgroundTransparency = 1,
			Text = laneGlyph(note.lane),
			TextScaled = true,
			Font = Enum.Font.GothamBlack,
			TextColor3 = laneColor(note.lane),
			Visible = false,
			ZIndex = 3,
			Parent = lanes[note.lane + 1],
		}, {
			make("UIAspectRatioConstraint", { AspectRatio = 1 }),
		}) :: TextLabel
	end

	local metronome: Sound? = nil
	if options.metronome and options.bpm and not options.getSongTimeMs then
		metronome = make("Sound", { SoundId = METRONOME_SOUND, Volume = 0.4, Parent = gui }) :: Sound
	end

	gui.Parent = (Players.LocalPlayer :: Player):WaitForChild("PlayerGui")
	setMovementEnabled(false)

	-- Feedback
	local judgementToken = 0
	local function showResult(result: RhythmEngine.HitResult)
		local view = noteViews[result.noteIndex]
		if view then
			view.Visible = false
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
			local flash = flashes[result.lane + 1]
			flash.BackgroundTransparency = if result.judgement == "Perfect" then 0.35 else 0.6
		end
		task.delay(0.5, function()
			if token == judgementToken then
				judgementLabel.Text = ""
				offsetLabel.Text = ""
			end
		end)
	end

	local finished = false
	function RhythmOverlay._onTap(lane: number)
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
			RhythmOverlay._onTap(lane)
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
		RhythmOverlay._onTap = function() end
		setMovementEnabled(true)
		task.delay(0.6, function()
			gui:Destroy()
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

		-- Positions. Notes are drawn at their latency-corrected time so they cross the line
		-- exactly when the player should tap.
		local latency = session.latencyMs
		for _, note in session.notes do
			local view = noteViews[note.index]
			if session.offsets[note.index] ~= nil then
				continue
			end
			local untilHit = note.timeMs + latency - now
			if untilHit > scrollMs or untilHit < -RhythmEngine.Judge.DefaultWindows.Good then
				view.Visible = false
			else
				view.Visible = true
				view.Position = UDim2.fromScale(0.5, HIT_LINE * (1 - untilHit / scrollMs))
			end
		end

		for _, flash in flashes do
			if flash.BackgroundTransparency < 1 then
				flash.BackgroundTransparency = math.min(1, flash.BackgroundTransparency + 0.06)
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

-- Replaced while a run is active.
function RhythmOverlay._onTap(_lane: number) end

-- Shared with RhythmLane3D: character movement shares keys with the lanes (D).
RhythmOverlay.setMovementEnabled = setMovementEnabled

return RhythmOverlay
