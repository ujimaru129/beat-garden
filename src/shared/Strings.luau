--!strict
-- UI strings in English and Japanese (spec: no hard-coded UI text; other languages use Roblox's
-- auto translation). Only the tutorial is moved here so far; the older screens still use plain
-- English and should move here when the translation data is done (Week 5).

local Strings = {}

local tables: { [string]: { [string]: string } } = {
	en = {
		tutorial_plant = "Walk to your garden spot and tap Plant",
		tutorial_tend = "Tap Tend and play along with the beat!",
		tutorial_harvest = "It's ready! Tap Harvest",
		tutorial_sell = "Walk to the Market and tap Sell",
		tutorial_buy = "Open Shop and buy a new seed",
		tutorial_skip = "Skip",
		tutorial_done = "Tutorial complete! Plant your new seed and keep growing",
	},
	ja = {
		tutorial_plant = "畑に近づいて「Plant」をタップ。種を植えよう",
		tutorial_tend = "「Tend」をタップして、リズムに合わせて世話しよう！",
		tutorial_harvest = "実ができた！「Harvest」をタップ",
		tutorial_sell = "マーケットに近づいて「Sell」をタップ",
		tutorial_buy = "「Shop」を開いて新しい種を買おう",
		tutorial_skip = "スキップ",
		tutorial_done = "チュートリアル完了！新しい種を植えて、育て続けよう",
	},
}

-- "ja-jp" -> "ja"; anything else -> "en".
function Strings.langFromLocale(localeId: string): string
	return if string.sub(string.lower(localeId), 1, 2) == "ja" then "ja" else "en"
end

-- Falls back to English, then to the key itself, so a missing string is visible but never an error.
function Strings.get(key: string, lang: string): string
	local t = tables[lang] or tables.en
	return t[key] or tables.en[key] or key
end

return table.freeze(Strings)
