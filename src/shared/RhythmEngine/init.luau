--!strict
-- RhythmEngine: chart playback, judgement and latency correction shared by the BEAT WORKS series.
-- Pure logic (no Instances, no RunService) so the same code runs on client, server and in Lune tests.
--
-- Client:
--   local session = RhythmEngine.Session.new(segment, { latencyMs = settings.latencyMs, chartOffsetMs = song.offsetMs })
--   every frame:   session:update(songTimeMs)
--   on tap:        session:hit(lane, songTimeMs)
--   when done:     send session:getSummary() to the server
-- Server:
--   RhythmEngine.Validator.validate(segment, summary, { elapsedMs = ... })

local Calibration = require(script.Calibration)
local Chart = require(script.Chart)
local Judge = require(script.Judge)
local Session = require(script.Session)
local Types = require(script.Types)
local Validator = require(script.Validator)

export type Judgement = Types.Judgement
export type Segment = Types.Segment
export type Summary = Types.Summary
export type HitResult = Types.HitResult
export type Windows = Types.Windows
export type Session = Session.Session

return table.freeze({
	Version = "0.1.0",
	Calibration = Calibration,
	Chart = Chart,
	Judge = Judge,
	Session = Session,
	Validator = Validator,
})
