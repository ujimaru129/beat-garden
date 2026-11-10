--!strict
-- Switches for prototype-only features.

local Flags = {}

-- Rhythm prototype (song select, test charts, the RhythmDev endpoint).
-- true: also runs in the published game, so it can be checked in the Roblox app on a phone.
-- Set to false before the public launch: the real Tend flow replaces it.
Flags.RhythmPrototype = true

return table.freeze(Flags)
