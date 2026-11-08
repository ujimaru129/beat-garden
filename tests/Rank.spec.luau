return function(loader, expect)
	local Rank = loader.require("src/shared/Rank")

	return {
		{
			"rank follows accuracy",
			function()
				expect(Rank.forAccuracy(1)).toBe("S")
				expect(Rank.forAccuracy(0.95)).toBe("S")
				expect(Rank.forAccuracy(0.9)).toBe("A")
				expect(Rank.forAccuracy(0.8)).toBe("B")
				expect(Rank.forAccuracy(0.65)).toBe("C")
				expect(Rank.forAccuracy(0.2)).toBe("D")
			end,
		},
		{
			"score is out of one million and clamped",
			function()
				expect(Rank.score(1)).toBe(1000000)
				expect(Rank.score(0.5)).toBe(500000)
				expect(Rank.score(2)).toBe(1000000)
				expect(Rank.score(-1)).toBe(0)
			end,
		},
	}
end
