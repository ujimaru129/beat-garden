--!strict
-- One-time tips: asks the server whether this tip has been shown before (it remembers per player) and, if it is
-- new, shows it as a toast a moment later so it does not cover the message that caused it.

local LocalizationService = game:GetService("LocalizationService")

local GardenState = require(script.Parent.GardenState)
local Strings = require(game:GetService("ReplicatedStorage").Shared.Strings)
local Toast = require(script.Parent.Toast)

local TipsUI = {}

local asked: { [string]: boolean } = {} -- this session: do not ask the server twice

function TipsUI.show(key: string)
	if asked[key] then
		return
	end
	asked[key] = true
	task.spawn(function()
		local result = GardenState.call("tip", key)
		if result.ok and result.new then
			task.wait(3)
			Toast.show(Strings.get(`tip_{key}`, Strings.langFromLocale(LocalizationService.RobloxLocaleId)))
		end
	end)
end

return TipsUI
