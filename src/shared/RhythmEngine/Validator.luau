--!strict
-- Server-side check of a client Summary. The server never trusts the client's counts:
-- it recomputes them from the per-note offsets and rejects runs that look impossible.

local Chart = require(script.Parent.Chart)
local Judge = require(script.Parent.Judge)
local Types = require(script.Parent.Types)

type Segment = Types.Segment
type Summary = Types.Summary
type Windows = Types.Windows

local Validator = {}

export type Context = {
	-- Server-measured ms between handing out the segment and receiving the summary.
	elapsedMs: number?,
	-- Stricter thresholds (Night Heist duels).
	strict: boolean?,
	windows: Windows?,
}

export type Result = {
	ok: boolean,
	reason: string?,
	tally: Judge.Tally?, -- trusted, recomputed numbers (only when ok)
}

-- Thresholds for "too precise to be human". Normal play has a spread of roughly 15-40ms.
-- maxPerfectRatio above 1 turns that check off (normal tends allow an all-Perfect run).
Validator.Limits = table.freeze({
	normal = { minHitsForStats = 16, minStdDevMs = 3, maxPerfectRatio = 1.01, elapsedSlackMs = 1500 },
	strict = { minHitsForStats = 8, minStdDevMs = 5, maxPerfectRatio = 0.98, elapsedSlackMs = 800 },
})

local function fail(reason: string): Result
	return { ok = false, reason = reason, tally = nil }
end

function Validator.validate(segment: Segment, summary: any, ctx: Context?): Result
	local c: Context = ctx or {}
	local limits = if c.strict then Validator.Limits.strict else Validator.Limits.normal
	local windows = c.windows or Judge.DefaultWindows

	-- Shape
	if type(summary) ~= "table" or summary.v ~= 1 then
		return fail("bad summary shape")
	end
	if summary.segment ~= segment.segment then
		return fail("segment mismatch")
	end
	local offsets = summary.offsets
	if type(offsets) ~= "table" then
		return fail("missing offsets")
	end

	-- Note count must match the chart the server handed out.
	local noteCount = #segment.notes
	if summary.noteCount ~= noteCount or #offsets ~= noteCount then
		return fail(`note count mismatch (chart {noteCount}, got {#offsets})`)
	end

	-- Every offset is false or a finite whole number inside the Good window.
	local hits: { number } = {}
	for i = 1, noteCount do
		local o = offsets[i]
		if o == false then
			continue
		end
		if type(o) ~= "number" or o ~= o or o % 1 ~= 0 or math.abs(o) > windows.Good then
			return fail(`bad offset at note {i}`)
		end
		table.insert(hits, o)
	end

	-- The run can't finish faster than the chart is long.
	if c.elapsedMs then
		local notes = Chart.normalize(segment)
		local first, last = Chart.span(notes)
		local minDuration = (last - first) - limits.elapsedSlackMs
		if c.elapsedMs < minDuration then
			return fail(`finished too fast ({math.floor(c.elapsedMs)}ms < {minDuration}ms)`)
		end
	end

	-- Inhumanly tight timing.
	if #hits >= limits.minHitsForStats then
		local sum = 0
		for _, o in hits do
			sum += o
		end
		local mean = sum / #hits
		local sq = 0
		for _, o in hits do
			sq += (o - mean) ^ 2
		end
		local stdDev = math.sqrt(sq / #hits)
		if stdDev < limits.minStdDevMs then
			return fail(`timing spread too small ({string.format("%.1f", stdDev)}ms)`)
		end
	end

	local tally = Judge.tally(offsets, windows)
	if noteCount >= limits.minHitsForStats and tally.counts.Perfect / noteCount > limits.maxPerfectRatio then
		return fail("perfect ratio too high")
	end

	return { ok = true, reason = nil, tally = tally }
end

return table.freeze(Validator)
