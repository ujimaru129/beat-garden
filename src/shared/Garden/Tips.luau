--!strict
-- One-time tips: short hints shown the first time something happens (level-up, a mastery star, an overripe fruit,
-- the first BPM Rush). Each is shown once per player; "seen" is saved with the player data. The text is in
-- Shared/Strings under `tip_<key>`.

local Tips = {}

Tips.Keys = table.freeze({ "levelup", "star", "overripe", "rush", "park", "pet", "daily" })

function Tips.isKey(key: unknown): boolean
	return type(key) == "string" and table.find(Tips.Keys :: any, key) ~= nil
end

return table.freeze(Tips)
