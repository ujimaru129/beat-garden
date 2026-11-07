--!strict
-- Server entry point (ServerScriptService/Server)
-- Garden, economy and save systems will be required from here.

local Garden = require(script.Garden)
local RhythmDev = require(script.RhythmDev)

Garden.start()
RhythmDev.start() -- Studio only

print("[BeatGarden] server started")
