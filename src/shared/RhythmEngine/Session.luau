--!strict
-- One play of one chart segment. Pure logic: the caller feeds it the current song time,
-- so it works the same with Sound.TimePosition in Roblox or a fake clock in tests.

local Chart = require(script.Parent.Chart)
local Judge = require(script.Parent.Judge)
local Types = require(script.Parent.Types)

type Note = Types.Note
type Segment = Types.Segment
type Windows = Types.Windows
type Summary = Types.Summary
type HitResult = Types.HitResult

export type Options = {
	latencyMs: number?, -- player calibration (settings.latencyMs). Positive = player hits late.
	chartOffsetMs: number?, -- Master_Songs.offsetMs
	windows: Windows?,
}

local Session = {}
Session.__index = Session

export type Session = typeof(setmetatable(
	{} :: {
		segmentId: number,
		notes: { Note },
		windows: Windows,
		latencyMs: number,
		offsets: { [number]: number | false }, -- per note index; nil = not judged yet
		laneQueues: { [number]: { number } }, -- lane -> note indices in time order
		laneHeads: { [number]: number }, -- lane -> next candidate position in its queue
		missHead: number, -- scan position for automatic misses
		judgedCount: number,
		combo: number,
	},
	Session
))

function Session.new(segment: Segment, options: Options?): Session
	local ok, reason = Chart.check(segment)
	assert(ok, `RhythmEngine: bad chart segment: {reason}`)

	local opts: Options = options or {}
	local notes = Chart.normalize(segment, opts.chartOffsetMs)

	local laneQueues: { [number]: { number } } = {}
	local laneHeads: { [number]: number } = {}
	for lane = 0, Chart.LaneCount - 1 do
		laneQueues[lane] = {}
		laneHeads[lane] = 1
	end
	for _, n in notes do
		table.insert(laneQueues[n.lane], n.index)
	end

	return setmetatable({
		segmentId = segment.segment,
		notes = notes,
		windows = opts.windows or Judge.DefaultWindows,
		latencyMs = opts.latencyMs or 0,
		offsets = {},
		laneQueues = laneQueues,
		laneHeads = laneHeads,
		missHead = 1,
		judgedCount = 0,
		combo = 0,
	}, Session)
end

function Session._judge(self: Session, note: Note, offset: number | false): HitResult
	self.offsets[note.index] = offset
	self.judgedCount += 1
	local judgement = if offset == false then "Miss" else (Judge.classify(offset, self.windows) or "Miss")
	if judgement == "Miss" then
		self.combo = 0
	else
		self.combo += 1
	end
	return {
		judgement = judgement,
		noteIndex = note.index,
		lane = note.lane,
		offsetMs = if offset == false then 0 else offset,
		combo = self.combo,
	}
end

-- Marks every note whose Good window has fully passed as a Miss. Call every frame.
-- Returns the misses produced by this call (for UI feedback).
function Session.update(self: Session, songTimeMs: number): { HitResult }
	local t = songTimeMs - self.latencyMs
	local results = {}
	while self.missHead <= #self.notes do
		local note = self.notes[self.missHead]
		if self.offsets[note.index] == nil then
			if t - note.timeMs <= self.windows.Good then
				break
			end
			table.insert(results, self:_judge(note, false))
		end
		self.missHead += 1
	end
	return results
end

-- A tap on `lane` at `songTimeMs`. Returns the hit, or nil if there was no note close enough
-- (taps far from any note are ignored, never punished).
function Session.hit(self: Session, lane: number, songTimeMs: number): (HitResult?, { HitResult })
	local misses = self:update(songTimeMs)
	local t = songTimeMs - self.latencyMs

	local queue = self.laneQueues[lane]
	if not queue then
		return nil, misses
	end
	local head = self.laneHeads[lane]
	while head <= #queue and self.offsets[queue[head]] ~= nil do
		head += 1
	end
	self.laneHeads[lane] = head
	if head > #queue then
		return nil, misses
	end

	local note = self.notes[queue[head]]
	local offset = t - note.timeMs
	if math.abs(offset) > self.windows.Good then
		return nil, misses
	end
	self.laneHeads[lane] = head + 1
	return self:_judge(note, math.round(offset)), misses
end

function Session.isFinished(self: Session): boolean
	return self.judgedCount >= #self.notes
end

-- Song time at which every note is guaranteed judged (last note + Good window + latency).
function Session.endTimeMs(self: Session): number
	return self.notes[#self.notes].timeMs + self.windows.Good + self.latencyMs
end

function Session.getSummary(self: Session): Summary
	local offsets: { number | false } = table.create(#self.notes)
	for i = 1, #self.notes do
		local o = self.offsets[i]
		offsets[i] = if o == nil then false else o
	end
	local tally = Judge.tally(offsets, self.windows)
	return {
		v = 1,
		segment = self.segmentId,
		noteCount = #self.notes,
		offsets = offsets,
		counts = tally.counts,
		maxCombo = tally.maxCombo,
		maxPerfectStreak = tally.maxPerfectStreak,
		accuracy = tally.accuracy,
	}
end

return Session
