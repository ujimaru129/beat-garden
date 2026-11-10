--!strict
-- Touch-first latency calibration screen.
-- A steady click plays and a ring pulses on each beat. The player taps anywhere on the screen
-- (or presses Space) along with it. The median lateness becomes the recommended latencyMs.
-- The value is stored in the LocalPlayer attribute "LatencyMs" (later: settings.latencyMs).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Calibration = require(ReplicatedStorage.Shared.RhythmEngine).Calibration
local Palette = require(ReplicatedStorage.Shared.Palette)
local Lang = require(script.Parent.Lang)
local RhythmOverlay = require(script.Parent.RhythmOverlay)

local Calibrator = {}

export type Calibrator = {
	open: () -> (),
	isOpen: () -> boolean,
}

local BPM = 100
local BEAT_MS = 60000 / BPM
local COUNT_IN_BEATS = 4
local MEASURED_BEATS = 16
local CLICK_SOUND = "rbxasset://sounds/electronicpingshort.wav"

local function make(className: string, props: { [string]: any }, parent: Instance?): any
	local inst = Instance.new(className)
	for k, v in props do
		(inst :: any)[k] = v
	end
	inst.Parent = parent
	return inst
end

local function bigButton(text: string, color: Color3, order: number, parent: Instance): TextButton
	local button = make("TextButton", {
		LayoutOrder = order,
		Size = UDim2.new(0.5, -6, 1, 0),
		BackgroundColor3 = color,
		Text = text,
		TextColor3 = Palette.Base.YoruSky,
		TextScaled = true,
		Font = Enum.Font.GothamBlack,
	}, parent) :: TextButton
	make("UICorner", { CornerRadius = UDim.new(0, 14) }, button)
	make("UIPadding", {
		PaddingTop = UDim.new(0.25, 0),
		PaddingBottom = UDim.new(0.25, 0),
	}, button)
	return button
end

-- `onSaved` is called with the saved latencyMs after the player accepts a result.
function Calibrator.create(onSaved: ((latencyMs: number) -> ())?): Calibrator
	local player = Players.LocalPlayer :: Player

	local gui = make("ScreenGui", {
		Name = "Calibrator",
		ResetOnSpawn = false,
		IgnoreGuiInset = true,
		DisplayOrder = 60,
		Enabled = false,
	}, nil) :: ScreenGui

	-- The whole screen is the tap target, so thumbs can land anywhere.
	local tapArea = make("TextButton", {
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Palette.Base.YoruSky,
		BackgroundTransparency = 0.1,
		AutoButtonColor = false,
		Text = "",
	}, gui) :: TextButton

	local title = make("TextLabel", {
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.fromScale(0.5, 0.08),
		Size = UDim2.fromScale(0.9, 0.1),
		BackgroundTransparency = 1,
		TextColor3 = Palette.Base.Washi,
		TextScaled = true,
		Font = Enum.Font.GothamBlack,
		Text = "",
	}, tapArea) :: TextLabel
	make("UISizeConstraint", { MaxSize = Vector2.new(600, 60) }, title)

	-- Ring size follows the screen height so it never reaches the title on a landscape phone.
	local function ringBase(): number
		return math.clamp(gui.AbsoluteSize.Y * 0.26, 70, 160)
	end

	local ring = make("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.44),
		Size = UDim2.fromOffset(ringBase(), ringBase()),
		BackgroundColor3 = Palette.Hues.Sora.Night,
		BackgroundTransparency = 0.6,
	}, tapArea) :: Frame
	make("UICorner", { CornerRadius = UDim.new(1, 0) }, ring)
	make("UIStroke", { Color = Palette.Hues.Sora.Night, Thickness = 6 }, ring)

	local hint = make("TextLabel", {
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.fromScale(0.5, 0.64),
		Size = UDim2.fromScale(0.9, 0.07),
		BackgroundTransparency = 1,
		TextColor3 = Palette.Base.Washi,
		TextScaled = true,
		Font = Enum.Font.GothamMedium,
		Text = "",
	}, tapArea) :: TextLabel
	make("UISizeConstraint", { MaxSize = Vector2.new(600, 36) }, hint)

	-- Result buttons (hidden while measuring).
	local buttons = make("Frame", {
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.fromScale(0.5, 0.96),
		Size = UDim2.fromScale(0.9, 0.18),
		BackgroundTransparency = 1,
		Visible = false,
	}, gui) :: Frame
	make("UISizeConstraint", { MaxSize = Vector2.new(560, 140), MinSize = Vector2.new(0, 72) }, buttons)
	make("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal,
		Padding = UDim.new(0, 12),
		SortOrder = Enum.SortOrder.LayoutOrder,
	}, buttons)
	local retryButton = bigButton("Retry", Palette.Hues.Sora.Night, 1, buttons)
	local saveButton = bigButton("Save", Palette.Hues.Matcha.Night, 2, buttons)

	local cancelButton = make("TextButton", {
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -16, 0, 16),
		Size = UDim2.fromOffset(56, 56),
		BackgroundColor3 = Palette.Base.Sumi,
		Text = "X",
		TextColor3 = Palette.Base.Washi,
		TextScaled = true,
		Font = Enum.Font.GothamBlack,
	}, gui) :: TextButton
	make("UICorner", { CornerRadius = UDim.new(1, 0) }, cancelButton)
	make("UIPadding", {
		PaddingTop = UDim.new(0.25, 0),
		PaddingBottom = UDim.new(0.25, 0),
	}, cancelButton)

	local click = make("Sound", { SoundId = CLICK_SOUND, Volume = 0.6 }, gui) :: Sound

	local renderConn: RBXScriptConnection? = nil
	local keyConn: RBXScriptConnection? = nil
	local tapConn: RBXScriptConnection? = nil
	local runId = 0
	local recommended: number? = nil

	local function disconnect()
		if renderConn then
			renderConn:Disconnect()
		end
		if keyConn then
			keyConn:Disconnect()
		end
		if tapConn then
			tapConn:Disconnect()
		end
		renderConn, keyConn, tapConn = nil, nil, nil
	end

	local function showResult(offsets: { number })
		disconnect()
		recommended = Calibration.estimate(offsets)
		ring.Size = UDim2.fromOffset(ringBase(), ringBase())
		buttons.Visible = true
		saveButton.Visible = recommended ~= nil
		saveButton.Size = if recommended then UDim2.new(0.5, -6, 1, 0) else UDim2.fromScale(0, 1)
		if recommended then
			title.Text = Lang.t(`Delay: {recommended} ms`)
			hint.Text = Lang.t(`{#offsets} taps measured`)
		else
			title.Text = Lang.t("Not enough taps")
			hint.Text = Lang.t(`{#offsets} of {MEASURED_BEATS} taps counted - tap with every click`)
		end
	end

	local function start()
		runId += 1
		local myRun = runId
		disconnect()
		recommended = nil
		buttons.Visible = false
		title.Text = Lang.t("Tap with the click")
		hint.Text = Lang.t("Tap anywhere, in time with the beat")

		local startClock = os.clock()
		local taps: { number } = {}
		local lastBeat = -1
		local totalBeats = COUNT_IN_BEATS + MEASURED_BEATS

		local function onTap()
			local nowMs = (os.clock() - startClock) * 1000
			-- Ignore taps before the count-in starts to settle in (one beat of grace).
			if nowMs >= (COUNT_IN_BEATS - 1) * BEAT_MS then
				table.insert(taps, nowMs)
			end
			ring.BackgroundTransparency = 0.2
		end

		tapConn = tapArea.InputBegan:Connect(function(input)
			if
				input.UserInputType == Enum.UserInputType.Touch
				or input.UserInputType == Enum.UserInputType.MouseButton1
			then
				onTap()
			end
		end)
		keyConn = UserInputService.InputBegan:Connect(function(input)
			-- The jump sink marks Space as already processed, so gameProcessed can't be used here.
			if input.KeyCode == Enum.KeyCode.Space and UserInputService:GetFocusedTextBox() == nil then
				onTap()
			end
		end)

		renderConn = RunService.RenderStepped:Connect(function()
			if myRun ~= runId then
				return
			end
			local nowMs = (os.clock() - startClock) * 1000
			local beat = math.floor(nowMs / BEAT_MS)
			if beat > lastBeat then
				lastBeat = beat
				if beat < totalBeats then
					click:Play()
				end
			end

			-- Ring: pulses big on the beat, shrinks back; tap flash fades out.
			local phase = (nowMs % BEAT_MS) / BEAT_MS
			local size = ringBase() * (1 + 0.25 * (1 - phase))
			ring.Size = UDim2.fromOffset(size, size)
			ring.BackgroundTransparency = math.min(0.6, ring.BackgroundTransparency + 0.03)

			if beat < COUNT_IN_BEATS then
				hint.Text = Lang.t(`Get ready... {COUNT_IN_BEATS - beat}`)
			else
				hint.Text = `{math.min(beat - COUNT_IN_BEATS + 1, MEASURED_BEATS)} / {MEASURED_BEATS}`
			end

			-- Wait half a beat after the last click so the final tap is counted.
			if nowMs >= totalBeats * BEAT_MS + BEAT_MS / 2 then
				showResult(Calibration.offsetsFromTaps(taps, COUNT_IN_BEATS * BEAT_MS, BEAT_MS))
			end
		end)
	end

	local function close()
		runId += 1
		disconnect()
		gui.Enabled = false
		RhythmOverlay.setMovementEnabled(true)
	end

	retryButton.Activated:Connect(start)
	cancelButton.Activated:Connect(close)
	saveButton.Activated:Connect(function()
		local value = recommended
		if value then
			player:SetAttribute("LatencyMs", value)
			if onSaved then
				onSaved(value)
			end
		end
		close()
	end)

	gui.Parent = player:WaitForChild("PlayerGui")

	return {
		open = function()
			-- Space is a tap key here, so the character must not jump while calibrating.
			RhythmOverlay.setMovementEnabled(false)
			gui.Enabled = true
			start()
		end,
		isOpen = function()
			return gui.Enabled
		end,
	}
end

return Calibrator
