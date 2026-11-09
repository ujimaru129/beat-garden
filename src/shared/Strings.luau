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
		tutorial_sell = "Walk to the yellow Market stall and tap Sell",
		tutorial_buy = "Tap the Shop button and buy a new seed",
		tutorial_skip = "Skip",
		tutorial_done = "Tutorial complete! Plant your new seed, level up to open new seeds, and keep growing",
		tip_levelup = "Level up! Higher garden levels open new seeds in the Shop",
		tip_star = "Mastery star! Seeds you harvest a lot grow faster, bigger and mutate more",
		tip_overripe = "Fruit left on the plant gets overripe and sells for less. Harvest it soon!",
		tip_rush = "BPM Rush! Seeds that love this genre mutate more for a while",
	},
	ja = {
		tutorial_plant = "畑に近づいて「Plant」をタップ。種を植えよう",
		tutorial_tend = "「Tend」をタップして、リズムに合わせて世話しよう！",
		tutorial_harvest = "実ができた！「Harvest」をタップ",
		tutorial_sell = "黄色い「Market」の屋台に近づいて「Sell」をタップ",
		tutorial_buy = "「Shop」ボタンをタップして、新しい種を買おう",
		tutorial_skip = "スキップ",
		tutorial_done = "チュートリアル完了！新しい種を植えて、レベルを上げて、新しい種を開放しよう",
		tip_levelup = "レベルアップ！ガーデンレベルが上がると、ショップに新しい種が並ぶよ",
		tip_star = "マスタリーの星！たくさん収穫した種は、早く、大きく育って、変異しやすくなるよ",
		tip_overripe = "収穫せずに置いた実は熟しすぎて、安くなるよ。早めに収穫しよう！",
		tip_rush = "BPM Rush！このジャンルが好きな種は、しばらく変異しやすいよ",
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
