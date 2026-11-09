--!strict
-- Server entry point (ServerScriptService/Server)
-- Garden, economy and save systems will be required from here.

local Garden = require(script.Garden)
local Leaderboards = require(script.Leaderboards)
local RhythmDev = require(script.RhythmDev)
local World = require(script.World)

World.start() -- first: the plots and shops place themselves on the island's floor
Garden.start()
Leaderboards.start()
RhythmDev.start() -- Studio only

print("[BeatGarden] server started")
