--!strict
-- Client side of Tend: tap the plant's prompt -> pick a difficulty -> play the chart -> see the result.
-- The server hands out the chart and decides the growth; this module only shows and plays.

local Players = game:GetService("Players")
local ProximityPromptService = game:GetService("ProximityPromptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local DifficultyPicker = require(script.Parent.DifficultyPicker)
local Palette = require(ReplicatedStorage.Shared.Palette)
local RhythmRunner = require(script.Parent.RhythmRunner)

local TendFlow = {}

local TOAST_SECONDS = 6

local function makeToast(): (text: string) -> ()
	local player = Players.LocalPlayer :: Player
	local gui = Instance.new("ScreenGui")
	gui.Name = "TendToast"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.DisplayOrder = 70

	local label = Instance.new("TextLabel")
	label.AnchorPoint = Vector2.new(0.5, 0.5)
	label.Position = UDim2.fromScale(0.5, 0.3)
	label.Size = UDim2.fromScale(0.55, 0.16)
	label.BackgroundColor3 = Palette.Base.YoruSky
	label.BackgroundTransparency = 0.2
	label.TextColor3 = Palette.Base.Washi
	label.TextScaled = true
	label.Font = Enum.Font.GothamBold
	label.Visible = false
	label.Parent = gui
	local size = Instance.new("UISizeConstraint")
	size.MaxSize = Vector2.new(640, 90)
	size.MinSize = Vector2.new(0, 56)
	size.Parent = label
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 12)
	corner.Parent = label
	local padding = Instance.new("UIPadding")
	padding.PaddingTop = UDim.new(0.15, 0)
	padding.PaddingBottom = UDim.new(0.15, 0)
	padding.PaddingLeft = UDim.new(0.04, 0)
	padding.PaddingRight = UDim.new(0.04, 0)
	padding.Parent = label
	gui.Parent = player:WaitForChild("PlayerGui")

	local token = 0
	return function(text: string)
		token += 1
		local mine = token
		label.Text = text
		label.Visible = true
		task.delay(TOAST_SECONDS, function()
			if token == mine then
				label.Visible = false
			end
		end)
	end
end

function TendFlow.start()
	local remote = ReplicatedStorage:WaitForChild("Tend", 10) :: RemoteFunction?
	if not remote then
		warn("[TendFlow] Tend remote not found")
		return
	end
	local tend: RemoteFunction = remote
	local player = Players.LocalPlayer :: Player
	local toast = makeToast()
	local picking = false

	-- The prompt button sits over the lane buttons and the picker, so it is hidden while either is up.
	local function setPromptsEnabled(enabled: boolean)
		ProximityPromptService.Enabled = enabled
	end

	local picker: DifficultyPicker.Picker
	local function closePicker()
		picking = false
		picker.setVisible(false)
	end
	local function cancelPicker()
		closePicker()
		setPromptsEnabled(true)
	end

	local function onPick(difficulty: string)
		closePicker()
		local info = tend:InvokeServer("begin", difficulty)
		if not (info and info.ok) then
			setPromptsEnabled(true)
			toast(`Can't tend now: {if info then info.reason else "no answer"}`)
			return
		end
		local started = RhythmRunner.play(
			{ segment = info.segment, bpm = info.bpm, difficulty = info.difficulty },
			function(summary)
				local result = tend:InvokeServer("submit", summary)
				setPromptsEnabled(true)
				if result and result.ok then
					toast(`+{result.points} growth!  {result.stage}  {math.floor(result.fraction * 100)}%`)
				else
					toast(`Run not counted: {if result then result.reason else "no answer"}`)
				end
			end
		)
		if not started then
			setPromptsEnabled(true)
			toast("Already playing")
		end
	end

	picker = DifficultyPicker.create(onPick, cancelPicker)
	picker.setVisible(false)

	ProximityPromptService.PromptTriggered:Connect(function(prompt: ProximityPrompt)
		if prompt.Name ~= "TendPrompt" or picking or RhythmRunner.isRunning() then
			return
		end
		local plot = prompt.Parent
		if not plot or plot:GetAttribute("OwnerUserId") ~= player.UserId then
			toast("This is not your plant")
			return
		end
		if plot:GetAttribute("Stage") == "Fruit" then
			toast("Fully grown! (harvest comes later)")
			return
		end
		picking = true
		setPromptsEnabled(false)
		picker.setVisible(true)
	end)
end

return TendFlow
