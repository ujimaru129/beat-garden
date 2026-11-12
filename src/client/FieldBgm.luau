--!strict
-- The music of the field (the island, not the rhythm game): Pastel Trip by day, Metropolitan Expressway by night.
-- It fades from one to the other when day turns to night, fades out during a rhythm run and while the song select
-- (which plays its own previews) is open, and is turned down while any other menu is open. The audio is the songs' own uploaded short edits.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ContentProvider = game:GetService("ContentProvider")
local RunService = game:GetService("RunService")
local SoundService = game:GetService("SoundService")

local Atmosphere = require(script.Parent.Atmosphere)
local Songs = require(ReplicatedStorage.Shared.Songs)

local FieldBgm = {}

local VOLUME = 0.16
local FADE_SECONDS = 2.5 -- a full fade from silent to loud

local DAY_SONG = "pastel_trip"
local NIGHT_SONG = "metropolitan_expressway"

local function makeSound(songId: string): Sound?
	local song = Songs.get(songId)
	if not song or not song.audioAssetId then
		return nil
	end
	local sound = Instance.new("Sound")
	sound.Name = `FieldBgm_{songId}`
	sound.SoundId = `rbxassetid://{song.audioAssetId}`
	sound.Volume = 0
	sound.Looped = true
	sound.Parent = SoundService
	return sound
end

-- One track of the field music. The sound exists only while it is needed (phones have little audio memory: two long
-- songs decoded at once made the sound crackly there), is loaded fully before it plays, and is destroyed after its fade-out.
type Track = { songId: string, sound: Sound?, loading: boolean, level: number }

function FieldBgm.start()
	local player = Players.LocalPlayer :: Player
	if not (Songs.get(DAY_SONG) and Songs.get(NIGHT_SONG)) then
		warn("[FieldBgm] a field song has no audio asset id")
		return
	end
	local tracks: { Track } = {
		{ songId = DAY_SONG, sound = nil, loading = false, level = 0 },
		{ songId = NIGHT_SONG, sound = nil, loading = false, level = 0 },
	}

	local function ensure(track: Track)
		if track.sound or track.loading then
			return
		end
		track.loading = true
		task.spawn(function()
			-- After the game itself has loaded, so the streaming of the world does not compete with the music.
			if not game:IsLoaded() then
				game.Loaded:Wait()
			end
			local sound = makeSound(track.songId)
			if sound then
				pcall(function()
					ContentProvider:PreloadAsync({ sound })
				end)
				local waited = 0
				while not sound.IsLoaded and waited < 20 do
					waited += task.wait(0.25)
				end
				if sound.IsLoaded then
					sound:Play()
					track.sound = sound
				else
					warn(`[FieldBgm] {sound.Name} did not load (permission or moderation?)`)
					sound:Destroy()
				end
			end
			track.loading = false
		end)
	end

	RunService.Heartbeat:Connect(function(dt: number)
		local silent = player:GetAttribute("InRhythm") == true or player:GetAttribute("SongSelectOpen") == true
		local loudness = if silent then 0 elseif player:GetAttribute("MenuOpen") == true then 0.4 else 1
		local isNight = Atmosphere.timeOfDay() == "Night"
		local step = dt / FADE_SECONDS
		for index, track in tracks do
			local wanted = (index == 2) == isNight
			local target = if wanted then loudness else 0
			if wanted and not silent then
				ensure(track)
			end
			track.level += math.clamp(target - track.level, -step, step)
			local sound = track.sound
			if sound then
				sound.Volume = VOLUME * track.level
				if track.level <= 0 and (not wanted or silent) then
					sound:Destroy()
					track.sound = nil
				end
			end
		end
	end)
end

return FieldBgm
