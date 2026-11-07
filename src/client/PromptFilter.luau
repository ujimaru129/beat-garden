--!strict
-- Prompts that belong to someone else must not show up on this player's screen: other players'
-- plants (Tend / Plant / Harvest) and the player's own Trade button. The server creates one prompt
-- per plot / character for everyone; each client switches off the ones that are not for it.
-- (Changing `Enabled` on the client only affects this client.)

local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")

local PromptFilter = {}

function PromptFilter.start()
	local me = Players.LocalPlayer :: Player

	local function apply(inst: Instance)
		if not inst:IsA("ProximityPrompt") then
			return
		end
		if inst.Name == "TendPrompt" then
			local plot = inst.Parent
			inst.Enabled = plot ~= nil and plot:GetAttribute("OwnerUserId") == me.UserId
		elseif inst.Name == "TradePrompt" then
			local character = inst.Parent and inst.Parent.Parent
			local owner = character and Players:GetPlayerFromCharacter(character)
			inst.Enabled = owner ~= nil and owner ~= me
		end
	end

	Workspace.DescendantAdded:Connect(apply)
	for _, inst in Workspace:GetDescendants() do
		apply(inst)
	end
end

return PromptFilter
