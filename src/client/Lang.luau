--!strict
-- The player's language ("ja" or "en", from their Roblox language) and the translation of the game's text.

local LocalizationService = game:GetService("LocalizationService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Loc = require(ReplicatedStorage.Shared.Loc)
local Strings = require(ReplicatedStorage.Shared.Strings)

local Lang = {}

Lang.code = Strings.langFromLocale(LocalizationService.RobloxLocaleId)

-- Translates an English text for this player. Texts with no entry (names and the like) come back as they are.
function Lang.t(text: string): string
	return Loc.t(text, Lang.code)
end

return Lang
