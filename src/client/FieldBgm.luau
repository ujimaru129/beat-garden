--!strict
-- The music of the field (the island, not the rhythm game): Pastel Trip by day, Metropolitan Expressway by night.
-- It fades from one to the other when day turns to night, fades out during a rhythm run and while the song select
-- (which plays its own previews) is open, and is turned down while any other menu is open. The audio is the songs' own uploaded short edits.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local SoundService = game:GetService("SoundService")

local Atmosphere = require(script.Parent.Atmosphere)
local Songs = require(ReplicatedStorage.Shared.Songs)

local FieldBgm = {}

local VOLUME = 0.3
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

function FieldBgm.start()
	local player = Players.LocalPlayer :: Player
	local day = makeSound(DAY_SONG)
	local night = makeSound(NIGHT_SONG)
	if not (day and night) then
		warn("[FieldBgm] a field song has no audio asset id")
		return
	end

	-- Both are started once the audio is there and keep playing silently, so a switch never waits for a load.
	for _, sound in { day, night } do
		task.spawn(function()
			local waited = 0
			while not sound.IsLoaded and waited < 20 do
				waited += task.wait(0.25)
			end
			if sound.IsLoaded then
				sound:Play()
			else
				warn(`[FieldBgm] {sound.Name} did not load (permission or moderation?)`)
			end
		end)
	end

	local levelDay, levelNight = 0, 0
	RunService.Heartbeat:Connect(function(dt: number)
		local silent = player:GetAttribute("InRhythm") == true or player:GetAttribute("SongSelectOpen") == true
		local loudness = if silent then 0 elseif player:GetAttribute("MenuOpen") == true then 0.4 else 1
		local isNight = Atmosphere.timeOfDay() == "Night"
		local targetDay = if isNight then 0 else loudness
		local targetNight = if isNight then loudness else 0
		local step = dt / FADE_SECONDS
		levelDay += math.clamp(targetDay - levelDay, -step, step)
		levelNight += math.clamp(targetNight - levelNight, -step, step)
		day.Volume = VOLUME * levelDay
		night.Volume = VOLUME * levelNight
	end)
end

return FieldBgm
