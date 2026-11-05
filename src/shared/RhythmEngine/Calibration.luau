--!strict
-- Latency calibration: the player taps along to a steady beat, we measure how late they land.
-- The result goes into settings.latencyMs and is passed to Session.new.

local Calibration = {}

Calibration.MinTaps = 8
Calibration.ClampMs = { min = -100, max = 300 }

local function median(list: { number }): number
	local s = table.clone(list)
	table.sort(s)
	local n = #s
	if n % 2 == 1 then
		return s[(n + 1) // 2]
	end
	return (s[n // 2] + s[n // 2 + 1]) / 2
end

-- Raw tap offsets for each beat (tap time - beat time) in a calibration run.
-- Matches each tap to its nearest beat and drops taps more than half a beat away.
function Calibration.offsetsFromTaps(tapTimesMs: { number }, firstBeatMs: number, beatIntervalMs: number): { number }
	local out = {}
	for _, t in tapTimesMs do
		local k = math.round((t - firstBeatMs) / beatIntervalMs)
		if k >= 0 then
			local offset = t - (firstBeatMs + k * beatIntervalMs)
			if math.abs(offset) < beatIntervalMs / 2 then
				table.insert(out, offset)
			end
		end
	end
	return out
end

-- Recommended latencyMs from tap offsets, or nil if there isn't enough consistent data.
-- Uses the median after dropping outliers (more than 3 MADs from the median).
function Calibration.estimate(offsets: { number }): number?
	if #offsets < Calibration.MinTaps then
		return nil
	end
	local m = median(offsets)
	local deviations = {}
	for _, o in offsets do
		table.insert(deviations, math.abs(o - m))
	end
	local mad = math.max(median(deviations), 1)

	local kept = {}
	for _, o in offsets do
		if math.abs(o - m) <= 3 * mad then
			table.insert(kept, o)
		end
	end
	if #kept < Calibration.MinTaps then
		return nil
	end
	return math.clamp(math.round(median(kept)), Calibration.ClampMs.min, Calibration.ClampMs.max)
end

return table.freeze(Calibration)
