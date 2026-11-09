-- Chart load check: how many notes are on screen at once and how many parts a run creates, per difficulty.
-- Run from the repo root:  lune run tests/chart_load
local loader = require("./loader")
local Songs = loader.require("src/shared/Songs")
local Difficulty = loader.require("src/shared/Difficulty")

local TRIANGLE_LANE = 1 -- the Sora lane draws its triangle from 14 slabs + an anchor
local PARTS_TRIANGLE = 15

for _, song in Songs.List do
	for _, name in Difficulty.Names do
		local notes = {}
		for _, segment in song.segments do
			for _, note in segment[name] do
				table.insert(notes, note)
			end
		end
		table.sort(notes, function(a, b)
			return a[2] < b[2]
		end)
		local window = Difficulty.ScrollMs[name]
		local maxOnScreen, parts = 0, 0
		local first = 1
		for i, note in notes do
			while notes[first][2] < note[2] - window do
				first += 1
			end
			maxOnScreen = math.max(maxOnScreen, i - first + 1)
			parts += if note[1] == TRIANGLE_LANE then PARTS_TRIANGLE else 1
		end
		print(`{song.name} {name}: {#notes} notes, max {maxOnScreen} on screen at once, {parts} parts created up front`)
	end
end
