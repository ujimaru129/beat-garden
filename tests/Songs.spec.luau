return function(loader, expect)
	local Songs = loader.require("src/shared/Songs")
	local Chart = loader.require("src/shared/RhythmEngine/Chart")

	local difficulties = { "Easy", "Normal", "Hard", "Expert" }
	-- Lune has no Random; always pick the first segment.
	local rng: any = {
		NextInteger = function(_self, low: number, _high: number)
			return low
		end,
	}

	return {
		{
			"every song chart is well formed and ordered by difficulty",
			function()
				for _, song in Songs.List do
					expect(#song.beatsMs > 20).toBeTruthy()
					expect(song.bpm > 60 and song.bpm < 220).toBeTruthy()
					for _, seg in song.segments do
						local counts = {}
						for _, name in difficulties do
							local segment = { segment = seg.id, startMs = seg.startMs, notes = (seg :: any)[name] }
							local ok, reason = Chart.check(segment)
							if not ok then
								error(`{song.songId} {name}: {reason}`)
							end
							for _, note in segment.notes do
								expect(note[2] >= seg.startMs and note[2] <= seg.endMs).toBeTruthy()
							end
							counts[name] = #segment.notes
						end
						expect(counts.Easy < counts.Normal).toBeTruthy()
						expect(counts.Normal < counts.Hard).toBeTruthy()
						expect(counts.Hard < counts.Expert).toBeTruthy()
					end
				end
			end,
		},
		{
			"pick returns a playable segment for each difficulty",
			function()
				for _, song in Songs.List do
					for _, name in difficulties do
						local pick = Songs.pick(song.songId, name, rng)
						expect(pick ~= nil).toBeTruthy()
						if pick then
							expect(Chart.check(pick.segment)).toBe(true)
							expect(#pick.beatsMs > 10).toBeTruthy()
						end
					end
				end
				expect(Songs.pick("nope", "Easy", rng) == nil).toBeTruthy()
				expect(Songs.pick("kabuki_dance", "Insane", rng) == nil).toBeTruthy()
			end,
		},
	}
end
