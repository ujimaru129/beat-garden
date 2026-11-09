return function(loader, expect)
	local Leaderboard = loader.require("src/shared/Garden/Leaderboard")
	local Progression = loader.require("src/shared/Garden/Progression")

	return {
		{
			"the level board stores total xp, the book board the number of entries found",
			function()
				expect(Leaderboard.valueFor("Level", 1234.9, {})).toBe(1234)
				expect(Leaderboard.valueFor("Level", -5, {})).toBe(0)
				local book = { ["seed_sakura|Normal"] = true, ["seed_sakura|Film"] = true, ["seed_yuzu|Normal"] = true }
				expect(Leaderboard.valueFor("Book", 0, book)).toBe(3)
			end,
		},
		{
			"values are shown as a level or a count out of the total",
			function()
				expect(Leaderboard.format("Level", Progression.xpToReach(7))).toBe("Lv 7")
				expect(Leaderboard.format("Level", 0)).toBe("Lv 1")
				local text = Leaderboard.format("Book", 3)
				expect(string.sub(text, 1, 4)).toBe("3 / ")
			end,
		},
		{
			"every board has a title",
			function()
				for _, board in Leaderboard.Boards do
					expect(Leaderboard.title(board) ~= board).toBeTruthy()
				end
			end,
		},
	}
end
