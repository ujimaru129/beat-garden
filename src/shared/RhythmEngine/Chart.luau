--!strict
-- Turns a chart segment from master data into sorted runtime notes, and checks it is well formed.

local Types = require(script.Parent.Types)

type Segment = Types.Segment
type Note = Types.Note

local Chart = {}

Chart.LaneCount = 4

-- Notes on the same lane closer than this are treated as a chart error (unplayable / double note).
Chart.MinSameLaneGapMs = 60

-- Returns (true, nil) if the segment is usable, or (false, reason).
function Chart.check(segment: Segment): (boolean, string?)
	if type(segment) ~= "table" or type(segment.notes) ~= "table" then
		return false, "segment has no notes table"
	end
	if #segment.notes == 0 then
		return false, "segment has no notes"
	end
	local lastByLane: { [number]: number } = {}
	for i, raw in segment.notes do
		local lane, t = raw[1], raw[2]
		if type(lane) ~= "number" or lane % 1 ~= 0 or lane < 0 or lane >= Chart.LaneCount then
			return false, `note {i}: bad lane {tostring(lane)}`
		end
		if type(t) ~= "number" or t ~= t then
			return false, `note {i}: bad time {tostring(t)}`
		end
		local prev = lastByLane[lane]
		if prev and t - prev < Chart.MinSameLaneGapMs then
			return false, `note {i}: lane {lane} notes only {t - prev}ms apart`
		end
		if prev and t < prev then
			return false, `note {i}: lane {lane} notes out of order`
		end
		lastByLane[lane] = t
	end
	return true, nil
end

-- Sorted runtime notes. chartOffsetMs (Master_Songs.offsetMs) shifts every note; positive = later.
function Chart.normalize(segment: Segment, chartOffsetMs: number?): { Note }
	local shift = chartOffsetMs or 0
	local notes: { Note } = {}
	for _, raw in segment.notes do
		table.insert(notes, { index = 0, lane = raw[1], timeMs = raw[2] + shift })
	end
	table.sort(notes, function(a, b)
		if a.timeMs == b.timeMs then
			return a.lane < b.lane
		end
		return a.timeMs < b.timeMs
	end)
	for i, n in notes do
		n.index = i
	end
	return notes
end

-- First and last note times (after normalize).
function Chart.span(notes: { Note }): (number, number)
	return notes[1].timeMs, notes[#notes].timeMs
end

return table.freeze(Chart)
