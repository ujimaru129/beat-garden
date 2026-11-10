--!strict
-- Plays a song from Shared.Songs and reports the song time, for the rhythm lanes and for the
-- song-select preview.
--
-- Two sources:
--   * real audio (song.audioAssetId is set): one Sound limited to the song's region of the
--     medley file. Song time comes from Sound.TimePosition.
--   * demo synth (no audio uploaded yet): a small step sequencer that pitches Roblox's
--     built-in sounds, so no asset upload or permission is needed. Song time is a clock.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local SoundService = game:GetService("SoundService")
local TweenService = game:GetService("TweenService")

local Songs = require(ReplicatedStorage.Shared.Songs)

local SongPlayer = {}

export type PlayOptions = {
	startMs: number?, -- song time to start from (default 0)
	lengthMs: number?, -- stop (or loop) after this long; default: to the end of the song
	loop: boolean?,
	volume: number?, -- 0..1, default 0.8
	fadeInSeconds: number?,
}

export type Playback = {
	-- Current song time in ms. Stays at `startMs` until the audio has loaded and started.
	getTimeMs: () -> number,
	stop: (fadeSeconds: number?) -> (),
}

local LEAD_SOUND = "rbxasset://sounds/electronicpingshort.wav"
local KICK_SOUND = "rbxasset://sounds/bass.wav"
local HAT_SOUND = "rbxasset://sounds/clickfast.wav"

-- TimePosition only updates in steps, so the time is run forward on a clock between updates
-- and re-anchored when the two drift apart (also covers loops and stalls).
local RESYNC_MS = 60
-- If the audio has not started after this long (bad asset id, no permission, no network),
-- the time runs on a clock instead, so that a run can still finish.
local LOAD_TIMEOUT_SECONDS = 8

local function makeGroup(volume: number, fadeInSeconds: number): SoundGroup
	local group = Instance.new("SoundGroup")
	group.Name = "BeatGardenSong"
	group.Volume = if fadeInSeconds > 0 then 0 else volume
	group.Parent = SoundService
	if fadeInSeconds > 0 then
		TweenService:Create(group, TweenInfo.new(fadeInSeconds), { Volume = volume }):Play()
	end
	return group
end

-- Fades the group out (if asked) and destroys it together with its sounds.
local function disposeGroup(group: SoundGroup, fadeSeconds: number?)
	if fadeSeconds and fadeSeconds > 0 then
		TweenService:Create(group, TweenInfo.new(fadeSeconds), { Volume = 0 }):Play()
		task.delay(fadeSeconds, function()
			group:Destroy()
		end)
	else
		group:Destroy()
	end
end

local function makeSound(group: SoundGroup, soundId: string, volume: number): Sound
	local sound = Instance.new("Sound")
	sound.SoundId = soundId
	sound.Volume = volume
	sound.SoundGroup = group
	sound.Parent = group
	return sound
end

local function playAudio(song: Songs.Song, options: PlayOptions): Playback
	local startMs = options.startMs or 0
	local group = makeGroup(options.volume or 0.8, options.fadeInSeconds or 0)
	local sound = makeSound(group, song.audioAssetId, 1)

	local fromMs = song.regionStartMs + startMs
	local songEndMs = if song.regionEndMs > 0 then song.regionEndMs else 60000 * 1000
	local toMs = if options.lengthMs then math.min(songEndMs, fromMs + options.lengthMs) else songEndMs
	local region = NumberRange.new(fromMs / 1000, math.max(toMs, fromMs + 1000) / 1000)
	sound.PlaybackRegionsEnabled = true
	sound.PlaybackRegion = region
	sound.LoopRegion = region
	sound.Looped = options.loop == true
	sound:Play() -- starts at the region start as soon as the audio has loaded

	local anchorMs = startMs
	local anchorClock = os.clock()
	local createdClock = anchorClock
	local started = false
	local failed = false
	local stopped = false

	return {
		getTimeMs = function(): number
			if stopped then
				return anchorMs
			end
			local now = os.clock()
			if failed then
				return anchorMs + (now - anchorClock) * 1000
			end
			local positionMs = sound.TimePosition * 1000 - song.regionStartMs
			if not started then
				-- Not loaded yet: hold the time so that notes wait for the music.
				if not sound.IsPlaying or positionMs <= startMs then
					if now - createdClock > LOAD_TIMEOUT_SECONDS then
						warn(`[SongPlayer] {song.id}: audio {song.audioAssetId} did not start; continuing without it`)
						failed = true
						anchorMs, anchorClock = startMs, now
					end
					return startMs
				end
				started = true
				anchorMs, anchorClock = positionMs, now
			end
			if not sound.IsPlaying then
				anchorMs, anchorClock = positionMs, now
				return positionMs
			end
			local predicted = anchorMs + (now - anchorClock) * 1000 * sound.PlaybackSpeed
			if math.abs(predicted - positionMs) > RESYNC_MS then
				anchorMs, anchorClock = positionMs, now
				return positionMs
			end
			return predicted
		end,
		stop = function(fadeSeconds: number?)
			if stopped then
				return
			end
			stopped = true
			disposeGroup(group, fadeSeconds)
		end,
	}
end

local function playDemo(song: Songs.Song, demo: Songs.DemoTrack, options: PlayOptions): Playback
	local startMs = options.startMs or 0
	local group = makeGroup(options.volume or 0.8, options.fadeInSeconds or 0)

	-- A few voices per part so that a new note does not cut the previous one short.
	local function makeVoices(soundId: string, count: number, volume: number): (speed: number) -> ()
		local voices: { Sound } = {}
		for i = 1, count do
			voices[i] = makeSound(group, soundId, volume)
		end
		local nextVoice = 1
		return function(speed: number)
			local sound = voices[nextVoice]
			nextVoice = nextVoice % count + 1
			sound.PlaybackSpeed = speed
			sound.TimePosition = 0
			sound:Play()
		end
	end
	local lead = makeVoices(LEAD_SOUND, 4, 0.6)
	local bass = makeVoices(LEAD_SOUND, 2, 0.5)
	local kick = makeVoices(KICK_SOUND, 2, 0.5)
	local hat = makeVoices(HAT_SOUND, 2, 0.25)

	local function pitch(semitones: number): number
		return 2 ^ ((demo.root + semitones) / 12)
	end

	local eighthMs = 60000 / song.bpm / 2
	local function playStep(step: number)
		local m = demo.melody[step % #demo.melody + 1]
		if m ~= Songs.REST then
			lead(pitch(m))
		end
		if step % 2 == 0 then
			local b = demo.bass[(step // 2) % #demo.bass + 1]
			if b ~= Songs.REST then
				bass(pitch(b - 12))
			end
			kick(1)
		else
			hat(1)
		end
	end

	local clockStart = os.clock()
	local stoppedAtMs: number? = nil
	local function getTimeMs(): number
		return stoppedAtMs or ((os.clock() - clockStart) * 1000 + startMs)
	end

	-- The tune loops forever, so `lengthMs` and `loop` need no handling here.
	local lastStep = math.ceil(startMs / eighthMs) - 1
	local conn = RunService.Heartbeat:Connect(function()
		local step = math.floor(getTimeMs() / eighthMs)
		if step > lastStep then
			lastStep = step
			playStep(step)
		end
	end)

	return {
		getTimeMs = getTimeMs,
		stop = function(fadeSeconds: number?)
			if stoppedAtMs then
				return
			end
			stoppedAtMs = getTimeMs()
			conn:Disconnect()
			disposeGroup(group, fadeSeconds)
		end,
	}
end

function SongPlayer.play(song: Songs.Song, options: PlayOptions?): Playback
	local opts: PlayOptions = options or {}
	if song.audioAssetId ~= "" then
		return playAudio(song, opts)
	end
	local demo = song.demo
	if demo then
		return playDemo(song, demo, opts)
	end
	-- No audio at all: a silent clock, so that the chart can still be played.
	warn(`[SongPlayer] {song.id} has no audioAssetId and no demo track; playing silently`)
	local startMs = opts.startMs or 0
	local clockStart = os.clock()
	return {
		getTimeMs = function(): number
			return (os.clock() - clockStart) * 1000 + startMs
		end,
		stop = function(_fadeSeconds: number?) end,
	}
end

return SongPlayer
