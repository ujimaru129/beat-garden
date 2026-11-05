--!strict
-- Judgement windows and pure scoring helpers. No Roblox APIs, so it runs in Lune tests too.

local Types = require(script.Parent.Types)

type Judgement = Types.Judgement
type Windows = Types.Windows

local Judge = {}

-- Initial values from the spec. Tune after playtests.
Judge.DefaultWindows = table.freeze({
	Perfect = 45,
	Great = 90,
	Good = 135,
}) :: Windows

-- Contribution of each judgement to accuracy (0..1).
Judge.Weight = table.freeze({
	Perfect = 1,
	Great = 0.7,
	Good = 0.4,
	Miss = 0,
}) :: { [Judgement]: number }

-- Judgement for a signed offset in ms, or nil if outside the Good window.
function Judge.classify(offsetMs: number, windows: Windows?): Judgement?
	local w = windows or Judge.DefaultWindows
	local a = math.abs(offsetMs)
	if a <= w.Perfect then
		return "Perfect"
	elseif a <= w.Great then
		return "Great"
	elseif a <= w.Good then
		return "Good"
	end
	return nil
end

export type Tally = {
	counts: { [Judgement]: number },
	maxCombo: number,
	maxPerfectStreak: number,
	accuracy: number,
}

-- Recompute counts, combo and accuracy from a per-note offsets list (false = miss).
-- The client and the server both use this so they always agree.
function Judge.tally(offsets: { number | false }, windows: Windows?): Tally
	local counts: { [Judgement]: number } = { Perfect = 0, Great = 0, Good = 0, Miss = 0 }
	local combo, maxCombo = 0, 0
	local streak, maxStreak = 0, 0
	local weightSum = 0

	for _, o in offsets do
		local j: Judgement = "Miss"
		if o ~= false then
			j = Judge.classify(o, windows) or "Miss"
		end
		counts[j] += 1
		weightSum += Judge.Weight[j]

		if j == "Miss" then
			combo = 0
		else
			combo += 1
			maxCombo = math.max(maxCombo, combo)
		end
		if j == "Perfect" then
			streak += 1
			maxStreak = math.max(maxStreak, streak)
		else
			streak = 0
		end
	end

	return {
		counts = counts,
		maxCombo = maxCombo,
		maxPerfectStreak = maxStreak,
		accuracy = if #offsets > 0 then weightSum / #offsets else 0,
	}
end

return table.freeze(Judge)
