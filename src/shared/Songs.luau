--!strict
-- Song list for the rhythm prototype. Same fields as Master_Songs (docs/spec.md); this module
-- stands in for it until the master data is served through Open Cloud.
--
-- A song with an empty `audioAssetId` has no uploaded audio yet. It is played by the built-in
-- demo synth (client/SongPlayer) from `demo`, so that something is audible in the meantime.
-- To use real audio: upload it, allow it for this experience, then fill in `audioAssetId`,
-- `regionStartMs` / `regionEndMs` (medley file) and `offsetMs`.

-- Placeholder tune for the demo synth. Notes are semitones above `root`; REST is silence.
export type DemoTrack = {
	root: number, -- semitones to shift the whole tune
	melody: { number }, -- one entry per eighth note, looped
	bass: { number }, -- one entry per quarter note, looped
}

export type Song = {
	id: string,
	title: string,
	bpm: number,
	audioAssetId: string, -- "rbxassetid://..." or "" while there is no upload
	regionStartMs: number, -- where the song starts inside the audio file
	regionEndMs: number, -- where it ends (0 = end of the file)
	offsetMs: number, -- chart offset: shifts every note of the chart
	previewStartMs: number, -- song time where the song-select preview starts
	previewLengthMs: number, -- preview length before it loops
	demo: DemoTrack?,
}

local Songs = {}

local R = -100
Songs.REST = R

local list: { Song } = {
	{
		id = "demo_sakura_step",
		title = "Sakura Step (demo)",
		bpm = 100,
		audioAssetId = "",
		regionStartMs = 0,
		regionEndMs = 0,
		offsetMs = 0,
		previewStartMs = 0,
		previewLengthMs = 15000,
		demo = {
			root = 0,
			-- stylua: ignore
			melody = {
				0, R, 4, R, 7, R, 4, R, 9, R, 7, R, 4, 2, 0, R,
				0, R, 4, R, 7, R, 12, R, 9, 7, 4, R, 2, R, 0, R,
			},
			bass = { 0, 0, 0, 0, -3, -3, -3, -3, -7, -7, -7, -7, -5, -5, -5, -5 },
		},
	},
	{
		id = "demo_sora_drive",
		title = "Sora Drive (demo)",
		bpm = 128,
		audioAssetId = "",
		regionStartMs = 0,
		regionEndMs = 0,
		offsetMs = 0,
		previewStartMs = 0,
		previewLengthMs = 15000,
		demo = {
			root = 2,
			-- stylua: ignore
			melody = {
				7, R, 7, 9, R, 7, 4, R, 2, R, 4, R, 7, R, R, R,
				9, R, 9, 12, R, 9, 7, R, 4, R, 2, R, 0, R, R, R,
			},
			bass = { 0, 0, 0, 0, -7, -7, -7, -7, -3, -3, -3, -3, -5, -5, -5, -5 },
		},
	},
	{
		id = "demo_matcha_rush",
		title = "Matcha Rush (demo)",
		bpm = 150,
		audioAssetId = "",
		regionStartMs = 0,
		regionEndMs = 0,
		offsetMs = 0,
		previewStartMs = 0,
		previewLengthMs = 15000,
		demo = {
			root = -3,
			-- stylua: ignore
			melody = {
				0, 4, 7, 12, 7, 4, 0, R, 2, 4, 9, 12, 9, 4, 2, R,
				0, 4, 7, 12, 14, 12, 7, 4, 9, 7, 4, 2, 0, R, 0, R,
			},
			bass = { 0, 0, 0, 0, -3, -3, -3, -3, -7, -7, -7, -7, -5, -5, -5, -5 },
		},
	},
}
Songs.List = table.freeze(list)

function Songs.byId(id: string): Song?
	for _, song in list do
		if song.id == id then
			return song
		end
	end
	return nil
end

return table.freeze(Songs)
