--!strict
-- The tap sound of the rhythm game: one short, unpitched sound (a key tap) for every hit that counts (Perfect, Great
-- and Good sound the same; a Miss is silent). Unpitched, so it never clashes with the song.
-- Until the real sound file is uploaded a quiet built-in click stands in. To use the real one, put its asset id in
-- `ASSET` below.

local HitSounds = {}

-- Asset id of the uploaded tap sound (audio/sfx/tap_key.mp3), e.g. "rbxassetid://123456". nil = built-in click.
local ASSET: string? = "rbxassetid://138623766818077"

local FALLBACK = "rbxasset://sounds/clickfast.wav"
local VOLUME = if ASSET then 0.2 else 0.15
local VOICES = 4 -- taps can come fast, so a few copies take turns instead of cutting each other off

export type Player = {
	play: (judgement: string) -> (),
}

-- `parent` is where the Sound objects live (destroyed with it).
function HitSounds.create(parent: Instance): Player
	local voices: { Sound } = {}
	for _ = 1, VOICES do
		local sound = Instance.new("Sound")
		sound.SoundId = ASSET or FALLBACK
		sound.Volume = VOLUME
		sound.Parent = parent
		table.insert(voices, sound)
	end
	local nextVoice = 1

	return {
		play = function(judgement: string)
			if judgement == "Miss" then
				return
			end
			voices[nextVoice]:Play()
			nextVoice = nextVoice % #voices + 1
		end,
	}
end

return HitSounds
