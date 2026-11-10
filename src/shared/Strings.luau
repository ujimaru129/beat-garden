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
		tutorial_plant = "自分の植え場に近づいて「植える」をタップ。タネを植えよう",
		tutorial_tend = "「世話する」をタップして、リズムに合わせて世話しよう！",
		tutorial_harvest = "実ができた！「収穫」をタップ",
		tutorial_sell = "黄色い「マーケット」の屋台に近づいて「売る」をタップ",
		tutorial_buy = "「ショップ」ボタンをタップして、新しいタネを買おう",
		tutorial_skip = "スキップ",
		tutorial_done = "チュートリアル完了！新しいタネを植えて、レベルを上げて、もっとタネを解放しよう",
		tip_levelup = "レベルアップ！ガーデンレベルが上がると、ショップに新しいタネが並ぶよ",
		tip_star = "マスタリーの星！たくさん収穫したタネは、早く、大きく育って、変異しやすくなるよ",
		tip_overripe = "収穫せずに置いた実は、熟しすぎて売値が下がるよ。早めに収穫しよう！",
		tip_rush = "BPM Rush！このジャンルが好きなタネは、しばらく変異しやすいよ",
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
