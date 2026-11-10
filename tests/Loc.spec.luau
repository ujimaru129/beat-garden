return function(loader, expect)
	local Loc = loader.require("src/shared/Loc")

	return {
		{
			"English stays as it is",
			function()
				expect(Loc.t("Shop", "en")).toBe("Shop")
				expect(Loc.t("Garden Lv 3!", "en")).toBe("Garden Lv 3!")
			end,
		},
		{
			"exact and template texts are translated",
			function()
				expect(Loc.t("Shop", "ja")).toBe("ショップ")
				expect(Loc.t("Garden Lv 3!", "ja")).toBe("ガーデン Lv 3！")
				expect(Loc.t("Garden Lv 4!  New seed in the shop: Kiwi Kick", "ja")).toBe(
					"ガーデン Lv 4！ ショップに新しいタネ: Kiwi Kick"
				)
				expect(Loc.t("Plot 2  -  200 coins", "ja")).toBe("区画 2  -  200 コイン")
				expect(Loc.t("Taylor's plant", "ja")).toBe("Taylor の植物")
			end,
		},
		{
			"a message that holds another message translates both",
			function()
				expect(Loc.t("Can't tend now: too far from the plant", "ja")).toBe(
					"いまは世話できません: 植物から遠すぎます"
				)
				expect(Loc.t("Ranking: Garden level   (tap to switch)", "ja")).toBe(
					"ランキング: ガーデンレベル   (タップで切り替え)"
				)
			end,
		},
		{
			"unknown text is left alone (names, numbers)",
			function()
				expect(Loc.t("Sakura Pop", "ja")).toBe("Sakura Pop")
				expect(Loc.t("Blue Samurai", "ja")).toBe("Blue Samurai")
			end,
		},
		{
			"every template is well formed and fills its placeholders",
			function()
				for _, entry in Loc.Templates do
					local english, japanese = entry[1], entry[2]
					local _, wildcards = string.gsub(english, "{}", "")
					-- Build a sample from the English template and translate it.
					local index = 0
					local sample = string.gsub(english, "{}", function()
						index += 1
						return "X" .. tostring(index)
					end)
					local result = Loc.ja(sample)
					expect(result == sample).toBe(false)
					expect(string.find(result, "{", 1, true) == nil).toBe(true)
					-- Every `{n}` in the Japanese must be one the English template captures.
					for n in string.gmatch(japanese, "{t?(%d)}") do
						expect(tonumber(n) <= wildcards).toBe(true)
					end
				end
			end,
		},
	}
end
