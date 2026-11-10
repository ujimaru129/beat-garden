--!strict
-- Pattern-made charts for trying the rhythm engine before generated charts exist.
-- Same shape as Master_Songs.charts.tend[n]. Note times are song time in ms.

local TestCharts = {}

local TARGET_MS = 13000 -- a tend segment is 10-15 seconds
local MIN_LEAD_MS = 3000 -- music before the first note

-- Lane per eighth note (-1 = rest), looped.
local PATTERNS: { [string]: { number } } = {
	Easy = { 0, -1, 1, -1, 2, -1, 3, -1 },
	Normal = { 0, -1, 2, 1, -1, 3, 2, -1, 1, -1, 3, 0, -1, 2, 1, -1 },
	Hard = { 0, 2, 1, 3, 2, 0, 3, 1, 0, 1, 2, 3, 3, 2, 1, 0 },
}

function TestCharts.has(difficulty: string): boolean
	return PATTERNS[difficulty] ~= nil
end

-- Builds one segment for a song at `bpm`. The first note lands on a bar line at least
-- MIN_LEAD_MS into the song, so the music is heard before the notes arrive.
function TestCharts.build(bpm: number, difficulty: string)
	local pattern = PATTERNS[difficulty] or PATTERNS.Normal
	local eighth = 60000 / bpm / 2
	local barMs = eighth * 8
	local startMs = math.ceil(MIN_LEAD_MS / barMs) * barMs
	local bars = math.max(2, math.round(TARGET_MS / barMs))
	local notes = {}
	for step = 0, bars * 8 - 1 do
		local lane = pattern[(step % #pattern) + 1]
		if lane >= 0 then
			table.insert(notes, { lane, math.round(startMs + step * eighth) })
		end
	end
	return { segment = 0, startMs = math.round(startMs), notes = notes }
end

return table.freeze(TestCharts)
