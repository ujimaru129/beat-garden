--!strict
-- Hand-made charts for trying the rhythm engine before real songs and generated charts exist.
-- Same shape as Master_Songs.charts.tend[n].

local TestCharts = {}

-- Builds a segment at `bpm` from a pattern of lanes per eighth note (-1 = rest).
local function fromPattern(id: number, bpm: number, startMs: number, bars: number, pattern: { number })
	local eighth = 60000 / bpm / 2
	local notes = {}
	local steps = bars * 8
	for step = 0, steps - 1 do
		local lane = pattern[(step % #pattern) + 1]
		if lane >= 0 then
			table.insert(notes, { lane, math.round(startMs + step * eighth) })
		end
	end
	return { segment = id, startMs = startMs, notes = notes }
end

TestCharts.Easy = fromPattern(0, 100, 0, 6, { 0, -1, 1, -1, 2, -1, 3, -1 })
TestCharts.Normal = fromPattern(1, 128, 0, 8, { 0, -1, 2, 1, -1, 3, 2, -1, 1, -1, 3, 0, -1, 2, 1, -1 })
TestCharts.Hard = fromPattern(2, 150, 0, 9, { 0, 2, 1, 3, 2, 0, 3, 1, 0, 1, 2, 3, 3, 2, 1, 0 })

TestCharts.Bpm = { Easy = 100, Normal = 128, Hard = 150 }

return table.freeze(TestCharts)
