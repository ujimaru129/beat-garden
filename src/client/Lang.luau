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

-- Roblox's automatic translation (set up in Creator Hub) works from the English text of the game. A Japanese player
-- already sees the game's own Japanese (Loc), so on a Japanese client every interface is kept out of it: Roblox then
-- neither re-translates that text nor captures the Japanese as if it were English source text.
function Lang.keepOwnText(player: Player)
	if Lang.code ~= "ja" then
		return
	end
	local function keep(item: Instance)
		if item:IsA("GuiBase2d") then
			item.AutoLocalize = false
		end
	end
	for _, root in { player:WaitForChild("PlayerGui"), workspace } do
		for _, item in root:GetDescendants() do
			keep(item)
		end
		root.DescendantAdded:Connect(keep)
	end
end

return Lang
