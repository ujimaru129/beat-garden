--!strict
-- The prompts that pop up over plants and shop signs ("Plant", "Tend", "Harvest"...) are made by the server in
-- English. Each client swaps the text for its own language when the prompt is shown.

local ProximityPromptService = game:GetService("ProximityPromptService")

local Lang = require(script.Parent.Lang)

local PromptText = {}

local function translate(prompt: ProximityPrompt)
	local action = Lang.t(prompt.ActionText)
	if action ~= prompt.ActionText then
		prompt.ActionText = action
	end
	local object = Lang.t(prompt.ObjectText)
	if object ~= prompt.ObjectText then
		prompt.ObjectText = object
	end
end

function PromptText.start()
	if Lang.code == "en" then
		return
	end
	ProximityPromptService.PromptShown:Connect(function(prompt: ProximityPrompt)
		translate(prompt)
		-- The server rewrites the text as the plant grows; translate again while the prompt is on screen.
		local connections: { RBXScriptConnection } = {}
		table.insert(
			connections,
			prompt:GetPropertyChangedSignal("ActionText"):Connect(function()
				translate(prompt)
			end)
		)
		table.insert(
			connections,
			prompt:GetPropertyChangedSignal("ObjectText"):Connect(function()
				translate(prompt)
			end)
		)
		local hidden: RBXScriptConnection
		hidden = ProximityPromptService.PromptHidden:Connect(function(hiddenPrompt: ProximityPrompt)
			if hiddenPrompt ~= prompt then
				return
			end
			for _, connection in connections do
				connection:Disconnect()
			end
			hidden:Disconnect()
		end)
	end)
end

return PromptText
