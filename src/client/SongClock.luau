--!strict
-- Plays a song's audio and exposes its position as the rhythm clock (song time in ms).
-- Before the audio starts (the lead-in) it counts on os.clock; once playing it follows
-- Sound.TimePosition, so the notes stay locked to what the player hears.

local ContentProvider = game:GetService("ContentProvider")
local SoundService = game:GetService("SoundService")

local LOAD_TIMEOUT_S = 6

local SongClock = {}

export type Clock = {
	getTimeMs: () -> number,
	isDone: () -> boolean, -- the audio has played to its end
	stop: () -> (),
}

-- Loads the audio. Yields until it is ready; returns nil when it cannot be loaded in time.
function SongClock.create(assetId: string, firstNoteMs: number, leadInMs: number): Clock?
	local sound = Instance.new("Sound")
	sound.Name = "SongAudio"
	sound.SoundId = `rbxassetid://{assetId}`
	sound.Volume = 0.8
	sound.Parent = SoundService

	local loaded = false
	task.spawn(function()
		pcall(function()
			ContentProvider:PreloadAsync({ sound })
		end)
		loaded = true
	end)
	local waited = 0
	while not loaded and waited < LOAD_TIMEOUT_S do
		waited += task.wait(0.1)
	end
	if not (loaded and sound.IsLoaded and sound.TimeLength > 0) then
		sound:Destroy()
		return nil
	end

	local startMs = firstNoteMs - leadInMs -- song time when the clock starts (negative = silent lead-in)
	local t0 = os.clock()
	local playing = false
	local last = startMs
	if startMs > 0 then
		sound.TimePosition = startMs / 1000
		sound:Play()
		playing = true
	end

	local ended = false
	sound.Ended:Connect(function()
		ended = true
	end)
	local length = sound.TimeLength

	local clock = {} :: Clock
	clock.isDone = function(): boolean
		-- Also stops waiting if playback never started or never reported its end.
		return ended or (os.clock() - t0) * 1000 + startMs > length * 1000 + 3000
	end
	clock.getTimeMs = function(): number
		local t = (os.clock() - t0) * 1000 + startMs
		if not playing and t >= 0 then
			sound:Play()
			playing = true
		end
		if playing and sound.IsPlaying and sound.TimePosition > 0 then
			t = sound.TimePosition * 1000
		end
		last = math.max(last, t) -- never run backwards
		return last
	end
	clock.stop = function()
		sound:Stop()
		sound:Destroy()
	end
	return clock
end

return SongClock
