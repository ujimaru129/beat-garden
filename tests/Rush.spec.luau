return function(loader, expect)
	local Rush = loader.require("src/shared/Garden/Rush")
	local Genres = loader.require("src/shared/Garden/Genres")

	return {
		{
			"the rush is on for ten minutes each hour, warns a minute before, and is silent otherwise",
			function()
				local hour = 5 * Rush.CycleSeconds
				expect(Rush.state(hour + 10)).toBe(nil)
				local warn = Rush.state(hour + Rush.StartSeconds - 30)
				expect(warn ~= nil and not warn.active and warn.secondsLeft == 30).toBeTruthy()
				local on = Rush.state(hour + Rush.StartSeconds + 100)
				expect(on ~= nil and on.active and on.secondsLeft == Rush.DurationSeconds - 100).toBeTruthy()
				expect(Rush.state(hour + Rush.StartSeconds + Rush.DurationSeconds)).toBe(nil)
			end,
		},
		{
			"the genre moves on every hour and only that genre's seeds get the boost",
			function()
				local seen: { [string]: boolean } = {}
				for h = 0, #Genres.List - 1 do
					seen[Rush.genreOfHour(h)] = true
				end
				expect(next(seen) ~= nil and #Genres.List == 4).toBeTruthy()
				local count = 0
				for _ in seen do
					count += 1
				end
				expect(count).toBe(#Genres.List)

				local now = 7 * Rush.CycleSeconds + Rush.StartSeconds + 5
				local genre = Rush.genreOfHour(7)
				expect(Rush.boost(genre, now)).toBe(Rush.MutationBoost)
				for _, other in Genres.List do
					if other ~= genre then
						expect(Rush.boost(other, now)).toBe(1)
					end
				end
				expect(Rush.boost(genre, 7 * Rush.CycleSeconds)).toBe(1) -- outside the window
			end,
		},
	}
end
