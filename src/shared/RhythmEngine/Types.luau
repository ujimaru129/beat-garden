--!strict
-- Shared types for RhythmEngine.

-- Judgement names, best to worst.
export type Judgement = "Perfect" | "Great" | "Good" | "Miss"

-- Number of notes per judgement.
export type Counts = {
	Perfect: number,
	Great: number,
	Good: number,
	Miss: number,
}

-- Half-widths of each judgement window in ms (a hit counts if |offset| <= window).
export type Windows = {
	Perfect: number,
	Great: number,
	Good: number,
}

-- One note in the chart master data: { lane (0-3), songTimeMs }.
export type RawNote = { number }

-- One tend segment from Master_Songs.charts.tend.
export type Segment = {
	segment: number,
	startMs: number,
	notes: { RawNote },
}

-- Normalized note used at runtime.
export type Note = {
	index: number, -- 1-based, in time order
	lane: number, -- 0-3
	timeMs: number, -- song time (chart offset already applied)
}

-- What the client sends to the server after a run. The server recomputes everything from `offsets`.
export type Summary = {
	v: number,
	segment: number,
	noteCount: number,
	-- Per note, in note order: hit offset in ms (input time - note time, after latency correction),
	-- or false for a miss.
	offsets: { number | false },
	counts: Counts,
	maxCombo: number,
	maxPerfectStreak: number,
	accuracy: number, -- 0..1, weighted by JudgementWeight
}

export type HitResult = {
	judgement: Judgement,
	noteIndex: number,
	lane: number,
	offsetMs: number,
	combo: number,
}

return {}
