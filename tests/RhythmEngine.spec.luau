return function(loader, expect)
	local RE = loader.require("src/shared/RhythmEngine")

	-- 120 BPM, one note per beat for ~15s, lanes 0,1,2,3,0,... starting at 15000ms
	local function makeSegment(count: number?, startMs: number?)
		local notes = {}
		local start = startMs or 15000
		for i = 0, (count or 30) - 1 do
			table.insert(notes, { i % 4, start + i * 500 })
		end
		return { segment = 0, startMs = start, notes = notes }
	end

	-- Plays a segment, hitting every note at the given offsets (false = don't tap).
	local function play(session, offsets)
		for i, note in session.notes do
			local o = offsets[i]
			if o ~= false then
				session:hit(note.lane, note.timeMs + o + session.latencyMs)
			end
		end
		session:update(session:endTimeMs() + 1)
		return session:getSummary()
	end

	-- Small deterministic RNG (Lune has no Roblox `Random`).
	local function rng(seed: number)
		local state = seed
		return function(lo: number, hi: number): number
			state = (state * 1103515245 + 12345) % 2147483648
			return lo + (hi - lo) * state / 2147483648
		end
	end

	local function humanOffsets(n: number, seed: number)
		local nextNumber = rng(seed)
		local out = {}
		for i = 1, n do
			out[i] = math.round(nextNumber(-40, 40))
		end
		return out
	end

	return {
		{
			"classify uses the spec windows (±45 / ±90 / ±135)",
			function()
				expect(RE.Judge.classify(0)).toBe("Perfect")
				expect(RE.Judge.classify(-45)).toBe("Perfect")
				expect(RE.Judge.classify(46)).toBe("Great")
				expect(RE.Judge.classify(-90)).toBe("Great")
				expect(RE.Judge.classify(135)).toBe("Good")
				expect(RE.Judge.classify(136)).toBe(nil)
			end,
		},
		{
			"tally counts combo, perfect streak and accuracy",
			function()
				local t = RE.Judge.tally({ 0, 10, 60, false, 100, 0, 0, 0 })
				expect(t.counts.Perfect).toBe(5)
				expect(t.counts.Great).toBe(1)
				expect(t.counts.Good).toBe(1)
				expect(t.counts.Miss).toBe(1)
				expect(t.maxCombo).toBe(4)
				expect(t.maxPerfectStreak).toBe(3)
				expect(t.accuracy).toBeNear((5 + 0.7 + 0.4) / 8, 1e-9)
			end,
		},
		{
			"chart check rejects bad lanes and stacked notes",
			function()
				expect((RE.Chart.check(makeSegment()))).toBe(true)
				expect((RE.Chart.check({ segment = 0, startMs = 0, notes = { { 4, 0 } } }))).toBe(false)
				expect((RE.Chart.check({ segment = 0, startMs = 0, notes = { { 1, 0 }, { 1, 30 } } }))).toBe(false)
				expect((RE.Chart.check({ segment = 0, startMs = 0, notes = {} }))).toBe(false)
			end,
		},
		{
			"normalize sorts by time and applies the chart offset",
			function()
				local notes = RE.Chart.normalize({ segment = 0, startMs = 0, notes = { { 2, 500 }, { 0, 0 } } }, 42)
				expect(notes[1].lane).toBe(0)
				expect(notes[1].timeMs).toBe(42)
				expect(notes[2].timeMs).toBe(542)
				expect(notes[2].index).toBe(2)
			end,
		},
		{
			"perfect play gives all Perfect and full combo",
			function()
				local s = RE.Session.new(makeSegment())
				local offsets = table.create(30, 0)
				local summary = play(s, offsets)
				expect(summary.counts.Perfect).toBe(30)
				expect(summary.maxCombo).toBe(30)
				expect(summary.accuracy).toBe(1)
				expect(s:isFinished()).toBe(true)
			end,
		},
		{
			"notes nobody taps become Miss once their window passes",
			function()
				local s = RE.Session.new(makeSegment(4))
				expect(#s:update(15000 + 135)).toBe(0) -- still inside Good window
				local misses = s:update(15000 + 136)
				expect(#misses).toBe(1)
				expect(misses[1].judgement).toBe("Miss")
				expect(s:isFinished()).toBe(false)
			end,
		},
		{
			"taps far from any note are ignored, not punished",
			function()
				local s = RE.Session.new(makeSegment(4))
				local r = s:hit(0, 15000 - 300)
				expect(r).toBe(nil)
				local hit = s:hit(0, 15000)
				expect(hit.judgement).toBe("Perfect")
			end,
		},
		{
			"wrong lane does not consume the note",
			function()
				local s = RE.Session.new(makeSegment(4))
				expect(s:hit(1, 15000)).toBe(nil) -- lane 1 note is at 15500
				expect(s:hit(0, 15010).judgement).toBe("Perfect")
			end,
		},
		{
			"latency calibration shifts input time",
			function()
				local s = RE.Session.new(makeSegment(4), { latencyMs = 80 })
				-- player is consistently 80ms late; after correction that is dead on
				local hit = s:hit(0, 15080)
				expect(hit.offsetMs).toBe(0)
				expect(hit.judgement).toBe("Perfect")
				-- the miss deadline moves with latency too
				expect(#s:update(15500 + 135 + 80)).toBe(0)
			end,
		},
		{
			"same-lane notes are judged in order",
			function()
				local seg = { segment = 0, startMs = 0, notes = { { 0, 1000 }, { 0, 1100 } } }
				local s = RE.Session.new(seg)
				local a = s:hit(0, 1050) -- closer to note 2 but note 1 is still pending
				expect(a.noteIndex).toBe(1)
				expect(a.judgement).toBe("Great")
				local b = s:hit(0, 1100)
				expect(b.noteIndex).toBe(2)
				expect(b.judgement).toBe("Perfect")
			end,
		},
		{
			"validator accepts a normal human run and recomputes counts",
			function()
				local seg = makeSegment()
				local summary = play(RE.Session.new(seg), humanOffsets(30, 1))
				summary.counts.Perfect = 999 -- client-side numbers are ignored
				local r = RE.Validator.validate(seg, summary, { elapsedMs = 15200 })
				expect(r.ok).toBe(true)
				expect(r.tally.counts.Perfect < 999).toBe(true)
			end,
		},
		{
			"validator rejects wrong note count",
			function()
				local seg = makeSegment()
				local summary = play(RE.Session.new(seg), humanOffsets(30, 2))
				table.remove(summary.offsets)
				expect(RE.Validator.validate(seg, summary).ok).toBe(false)
			end,
		},
		{
			"validator rejects offsets outside the Good window",
			function()
				local seg = makeSegment()
				local summary = play(RE.Session.new(seg), humanOffsets(30, 3))
				summary.offsets[5] = 500
				expect(RE.Validator.validate(seg, summary).ok).toBe(false)
			end,
		},
		{
			"validator rejects runs finished faster than the chart",
			function()
				local seg = makeSegment()
				local summary = play(RE.Session.new(seg), humanOffsets(30, 4))
				local r = RE.Validator.validate(seg, summary, { elapsedMs = 3000 })
				expect(r.ok).toBe(false)
			end,
		},
		{
			"validator rejects robotic timing",
			function()
				local seg = makeSegment()
				local summary = play(RE.Session.new(seg), table.create(30, 0))
				local r = RE.Validator.validate(seg, summary)
				expect(r.ok).toBe(false)
			end,
		},
		{
			"strict mode (duels) rejects near-perfect runs that normal mode allows",
			function()
				local seg = makeSegment()
				local offsets = {}
				for i = 1, 30 do
					offsets[i] = if i % 2 == 0 then 12 else -12 -- spread 12ms, all Perfect
				end
				local summary = play(RE.Session.new(seg), offsets)
				expect(RE.Validator.validate(seg, summary).ok).toBe(true)
				expect(RE.Validator.validate(seg, summary, { strict = true }).ok).toBe(false)
			end,
		},
		{
			"calibration estimates latency and ignores outliers",
			function()
				local taps = {}
				local nextNumber = rng(7)
				for k = 0, 15 do
					taps[#taps + 1] = 1000 + k * 500 + 70 + nextNumber(-10, 10)
				end
				taps[#taps + 1] = 1000 + 16 * 500 - 200 -- one mistimed tap
				local offsets = RE.Calibration.offsetsFromTaps(taps, 1000, 500)
				expect(RE.Calibration.estimate(offsets)).toBeNear(70, 6)
				expect(RE.Calibration.estimate({ 1, 2, 3 })).toBe(nil)
			end,
		},
		{
			"bad chart throws when starting a session",
			function()
				expect(function()
					RE.Session.new({ segment = 0, startMs = 0, notes = {} })
				end).toThrow()
			end,
		},
	}
end
