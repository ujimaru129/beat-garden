return function(loader, expect)
	local Daily = loader.require("src/shared/Garden/Daily")

	local function stats(overrides: { [string]: number }?)
		local s = { harvests = 0, runs = 0, perfects = 0, pats = 0, level = 5, spirits = 1 }
		for k, v in overrides or {} do
			s[k] = v
		end
		return s
	end

	local DAY = 86400
	local noon = 20000 * DAY -- a time on some day (UTC midnight is 9 am in Japan)

	return {
		{
			"the first visit pays the login bonus and gives three missions with different stats",
			function()
				local state = Daily.newState()
				local update = Daily.update(state, stats(), noon)
				expect(update.newDay).toBe(true)
				expect(state.streak).toBe(1)
				expect(update.loginCoins).toBe(Daily.loginCoins(1, 5))
				expect(update.coins).toBe(update.loginCoins)
				expect(#state.missions).toBe(Daily.MissionsPerDay)
				local seen = {}
				for _, id in state.missions do
					local m = Daily.mission(id) :: any
					expect(seen[m.stat] == nil).toBe(true)
					seen[m.stat] = true
				end
				-- a second look the same day pays nothing more
				local again = Daily.update(state, stats(), noon + 3600)
				expect(again.newDay).toBe(false)
				expect(again.coins).toBe(0)
			end,
		},
		{
			"the streak grows day by day, resets after a missed day, and day 7 gives a box",
			function()
				local state = Daily.newState()
				local boxes = 0
				for i = 0, 6 do
					local update = Daily.update(state, stats(), noon + i * DAY)
					boxes += update.boxes
					expect(state.streak).toBe(i + 1)
				end
				expect(boxes).toBe(1)
				Daily.update(state, stats(), noon + 9 * DAY) -- skipped a day
				expect(state.streak).toBe(1)
			end,
		},
		{
			"missions count from the start of the day and pay once; all three pay a box",
			function()
				local state = Daily.newState()
				Daily.update(state, stats({ harvests = 100, runs = 50, perfects = 900, pats = 70 }), noon)
				local total, boxes = 0, 0
				-- nothing done yet
				expect(Daily.update(state, stats({ harvests = 100, runs = 50, perfects = 900, pats = 70 }), noon).coins).toBe(
					0
				)
				-- do everything by a lot
				local update =
					Daily.update(state, stats({ harvests = 200, runs = 100, perfects = 1500, pats = 200 }), noon + 60)
				total += update.coins
				boxes += update.boxes
				expect(update.missionsDone).toBe(Daily.MissionsPerDay)
				expect(total).toBe(Daily.MissionsPerDay * Daily.missionCoins(5))
				expect(boxes).toBe(1)
				local again =
					Daily.update(state, stats({ harvests = 300, runs = 200, perfects = 2500, pats = 300 }), noon + 120)
				expect(again.coins).toBe(0)
				expect(again.boxes).toBe(0)
			end,
		},
		{
			"a player without spirits gets no petting mission; the day changes at midnight in Japan",
			function()
				for day = 1, 40 do
					for _, id in Daily.pick(day, false) do
						expect((Daily.mission(id) :: any).stat ~= "pats").toBe(true)
					end
				end
				-- 14:59 UTC and 15:00 UTC are on either side of Japanese midnight
				expect(Daily.dayOf(20000 * DAY + 15 * 3600 - 1)).toBe(20000)
				expect(Daily.dayOf(20000 * DAY + 15 * 3600)).toBe(20001)
			end,
		},
		{
			"sanitize keeps only valid things",
			function()
				local clean = Daily.sanitize({
					day = 5,
					streak = 3,
					base = { harvests = 4, junk = 9 },
					missions = { "harvest_3", "nope" },
					claimed = { harvest_3 = true, nope = true },
					bonus = true,
				})
				expect(clean.day).toBe(5)
				expect(clean.base.junk == nil).toBe(true)
				expect(#clean.missions).toBe(1)
				expect(clean.claimed.nope == nil).toBe(true)
				expect(Daily.sanitize(nil).day).toBe(0)
			end,
		},
	}
end
