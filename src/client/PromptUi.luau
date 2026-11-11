--!strict
-- The button for the prompt in range ("Tend", "Harvest", "Sell" ...), drawn by us at a fixed place at the bottom
-- of the screen. Roblox's own prompt hangs on the object in the 3D world, so it slid off the bottom of the screen
-- (and out of sight) whenever the camera moved. Pressing the button, or the key, does the same as before.
-- Only the look changes: the prompt itself (range, key, hold time) and PromptText (the Japanese text) are as they were.

local Players = game:GetService("Players")
local ProximityPromptService = game:GetService("ProximityPromptService")
local RunService = game:GetService("RunService")
local TextService = game:GetService("TextService")
local UserInputService = game:GetService("UserInputService")

local UiTheme = require(script.Parent.UiTheme)

local PromptUi = {}

local function positionOf(prompt: ProximityPrompt): Vector3?
	local parent = prompt.Parent
	if parent and parent:IsA("BasePart") then
		return parent.Position
	elseif parent and parent:IsA("Attachment") then
		return parent.WorldPosition
	end
	return nil
end

function PromptUi.start()
	local player = Players.LocalPlayer :: Player
	local shown: { [ProximityPrompt]: boolean } = {}

	local gui = Instance.new("ScreenGui")
	gui.Name = "PromptUi"
	gui.ResetOnSpawn = false
	gui.DisplayOrder = 40
	gui.Enabled = false
	UiTheme.hideDuringRun(gui)

	local button = Instance.new("TextButton")
	button.AnchorPoint = Vector2.new(0.5, 1)
	button.Position = UDim2.new(0.5, 0, 1, -22)
	button.Size = UDim2.fromOffset(300, 62)
	button.Text = ""
	button.AutoButtonColor = false
	button.Parent = gui
	UiTheme.watch(function()
		UiTheme.styleButton(button, UiTheme.get(), "Matcha", 16)
	end)

	local keyChip = Instance.new("TextLabel")
	keyChip.AnchorPoint = Vector2.new(0, 0.5)
	keyChip.Position = UDim2.new(0, 12, 0.5, 0)
	keyChip.Size = UDim2.fromOffset(34, 34)
	keyChip.BackgroundColor3 = Color3.new(1, 1, 1)
	keyChip.BackgroundTransparency = 0.15
	keyChip.TextColor3 = Color3.fromRGB(60, 50, 90)
	keyChip.Font = Enum.Font.GothamBlack
	keyChip.TextSize = 20
	keyChip.ZIndex = 5
	keyChip.Parent = button
	local chipCorner = Instance.new("UICorner")
	chipCorner.CornerRadius = UDim.new(0, 8)
	chipCorner.Parent = keyChip

	local action = Instance.new("TextLabel")
	action.AnchorPoint = Vector2.new(0, 0)
	action.BackgroundTransparency = 1
	action.Font = Enum.Font.GothamBlack
	action.TextXAlignment = Enum.TextXAlignment.Left
	action.TextSize = 24
	action.TextColor3 = Color3.fromRGB(40, 30, 70)
	action.ZIndex = 5
	action.Parent = button
	local object = Instance.new("TextLabel")
	object.BackgroundTransparency = 1
	object.Font = Enum.Font.GothamMedium
	object.TextXAlignment = Enum.TextXAlignment.Left
	object.TextSize = 15
	object.TextTransparency = 0.2
	object.TextColor3 = Color3.fromRGB(40, 30, 70)
	object.TextTruncate = Enum.TextTruncate.AtEnd
	object.ZIndex = 5
	object.Parent = button
	gui.Parent = player:WaitForChild("PlayerGui")

	local current: ProximityPrompt? = nil
	local lastKey = ""

	-- The nearest prompt that is on screen is the one the button stands for.
	local function nearest(): ProximityPrompt?
		local character = player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart")
		local here = if root and root:IsA("BasePart") then root.Position else nil
		local best: ProximityPrompt? = nil
		local bestDistance = math.huge
		for prompt in shown do
			local at = positionOf(prompt)
			local distance = if at and here then (at - here).Magnitude else 0
			if distance < bestDistance then
				best, bestDistance = prompt, distance
			end
		end
		return best
	end

	ProximityPromptService.PromptShown:Connect(function(prompt: ProximityPrompt)
		shown[prompt] = true
	end)
	ProximityPromptService.PromptHidden:Connect(function(prompt: ProximityPrompt)
		shown[prompt] = nil
	end)

	-- One press = one trigger (the prompts have no hold time).
	button.Activated:Connect(function()
		local prompt = current
		if prompt then
			prompt:InputHoldBegin()
			task.delay(0.05, function()
				prompt:InputHoldEnd()
			end)
		end
	end)

	RunService.RenderStepped:Connect(function()
		local prompt = nearest()
		current = prompt
		if not prompt or not ProximityPromptService.Enabled then
			gui.Enabled = false
			return
		end
		gui.Enabled = true
		local hasKey = UserInputService.KeyboardEnabled
		keyChip.Visible = hasKey
		keyChip.Text = if hasKey then prompt.KeyboardKeyCode.Name else ""
		local left = if hasKey then 56 else 18
		-- The size is worked out again only when the text changes.
		local key = `{prompt.ActionText}|{prompt.ObjectText}|{left}`
		if key ~= lastKey then
			lastKey = key
			-- The button grows with its text (between 300 and 560 px wide); past that the text gets smaller.
			local actionWidth =
				TextService:GetTextSize(prompt.ActionText, 24, Enum.Font.GothamBlack, Vector2.new(2000, 40)).X
			local objectWidth =
				TextService:GetTextSize(prompt.ObjectText, 15, Enum.Font.GothamMedium, Vector2.new(2000, 40)).X
			local width = math.clamp(left + math.max(actionWidth, objectWidth) + 28, 300, 560)
			button.Size = UDim2.fromOffset(width, 62)
			local room = width - left - 28
			action.TextSize = if actionWidth > room then math.max(16, math.floor(24 * room / actionWidth)) else 24
			action.Position = UDim2.fromOffset(left, 6)
			action.Size = UDim2.new(1, -left - 12, 0, 30)
			object.Position = UDim2.fromOffset(left, 34)
			object.Size = UDim2.new(1, -left - 12, 0, 20)
		end
		action.Text = prompt.ActionText
		object.Text = prompt.ObjectText
	end)
end

-- Makes this client draw the prompt itself (the prompt on the server is unchanged).
function PromptUi.take(prompt: ProximityPrompt)
	prompt.Style = Enum.ProximityPromptStyle.Custom
end

return PromptUi
