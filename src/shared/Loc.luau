--!strict
-- Japanese for the English text the game shows. The code keeps English as the source text; on a Japanese
-- client `Loc.t` swaps it for the Japanese below. Proper names (seed, spirit, song, mutation names) stay English.
--
-- A template's `{}` matches any text. In the Japanese side, `{1}` is the first match as it is and `{t1}` the first
-- match translated again (for a sentence that holds another message). Texts with no entry stay English.

local Loc = {}

local EXACT: { [string]: string } = {
	-- HUD and window titles
	["Shop"] = "ショップ",
	["Seed Shop"] = "タネ屋",
	["Market"] = "マーケット",
	["Spirits"] = "スピリット",
	["Book"] = "図鑑",
	["Park"] = "パーク",
	["Goals"] = "目標",
	["Back"] = "もどる",
	["Names"] = "名前",
	["Give your spirits names"] = "スピリットに名前をつける",
	["Tap a spirit to choose its name"] = "名前をつけるスピリットを選ぼう",
	["Choose a name:"] = "名前を選ぼう:",
	["No name"] = "名前なし",
	["Clear this lot"] = "この区画を、からにする",
	["..."] = "…",
	["Gift Boxes come from goals. Reach a goal to get one!"] = "ギフトボックスは、目標をクリアするともらえるよ！",
	["You have nothing for this lot yet. Open Gift Boxes!"] = "この区画に置けるものが、まだありません。箱を開けよう！",
	["Choose for this lot:"] = "この区画に置くものを選ぼう:",
	["New Gift Box! Open it in Park"] = "新しいギフトボックス！ パークで開けよう",
	["Harvest your first fruit"] = "はじめて実を収穫しよう",
	["Hatch your first spirit"] = "はじめてスピリットをかえそう",
	["Become close friends with a spirit"] = "スピリットと、なかよしになろう",
	["Become best friends with a spirit"] = "スピリットと、いちばんの友だちになろう",
	["no gift box"] = "ギフトボックスがありません",
	["nothing left to find"] = "見つけるものが、もうありません",
	["unknown lot"] = "その区画が見つかりません",
	["that lot is not open yet"] = "その区画は、まだ開いていません",
	["you do not have that"] = "それは持っていません",
	["that does not fit this lot"] = "それは、この区画には置けません",
	["Ranking"] = "ランキング",
	["Calibrate"] = "調整",
	["Trade"] = "交換",
	["Trade request"] = "交換のリクエスト",
	["Plant a seed"] = "タネを植える",
	["Unlock a plot"] = "区画を解放",
	["Plot Pass"] = "Plot Pass",
	["Coins: 0"] = "コイン: 0",
	-- buttons
	["Cancel"] = "キャンセル",
	["Not now"] = "あとで",
	["Back to editing"] = "もどる",
	["Accept"] = "受ける",
	["Decline"] = "断る",
	["I'm ready"] = "準備OK",
	["CONFIRM TRADE"] = "交換を確定",
	["Cancel trade"] = "交換をやめる",
	["Get the Plot Pass"] = "Plot Pass を手に入れる",
	-- song select, results, rhythm screen
	["SELECT SONG"] = "曲を選ぼう",
	["\u{2665} BONUS"] = "♥ ボーナス",
	["SCORE"] = "スコア",
	["Max combo"] = "最大コンボ",
	["Seed"] = "タネ",
	["Sprout"] = "芽",
	["Sapling"] = "若木",
	["Bloom"] = "開花",
	["Fruit"] = "結実",
	-- calibration
	["Not enough taps"] = "タップが足りません",
	["Tap with the click"] = "クリック音に合わせてタップ",
	["Tap anywhere, in time with the beat"] = "画面のどこでも、拍に合わせてタップ",
	-- plot prompts
	["Plant"] = "植える",
	["Tend"] = "世話する",
	["Harvest"] = "収穫",
	["Harvest (overripe)"] = "収穫（熟しすぎ）",
	["Sell"] = "売る",
	["Unlock"] = "解放",
	["Locked"] = "ロック中",
	-- messages and the reasons the server gives
	["Still loading..."] = "読み込み中…",
	["Coming soon!"] = "もうすぐ登場！",
	["The Plot Pass is coming soon!"] = "Plot Pass はもうすぐ登場！",
	["This is not your plant"] = "これはあなたの植物ではありません",
	["Already playing"] = "いま、プレイ中です",
	["Spirit put away"] = "スピリットをしまいました",
	["Trade complete!"] = "交換できたよ！",
	["no answer"] = "サーバーから返事がありません",
	["that did not work"] = "うまくいきませんでした",
	["could not plant"] = "植えられませんでした",
	["could not unlock"] = "解放できませんでした",
	["could not harvest"] = "収穫できませんでした",
	["could not hatch"] = "孵化できませんでした",
	["could not equip"] = "装備できませんでした",
	["ranking not available"] = "ランキングは、まだ見られません",
	["not available"] = "いまは使えません",
	["no such player"] = "その人が見つかりません",
	["not ready"] = "まだ準備中です",
	["finish the tutorial first"] = "先にチュートリアルを終わらせよう",
	["that player is still in the tutorial"] = "その人は、まだチュートリアル中です",
	["someone is already trading"] = "だれかが、すでに交換中です",
	["wait a moment"] = "少し待ってね",
	["that player has another request"] = "その人は、ほかの申し込みを受けています",
	["too far away"] = "遠すぎます",
	["the request has expired"] = "申し込みの期限が切れました",
	["no trade in progress"] = "交換していません",
	["invalid offer"] = "その内容では交換できません",
	["both players must be ready first"] = "2人とも準備OKになってから確定しよう",
	["you no longer have that fruit"] = "その実は、もう持っていません",
	["you no longer have those seeds"] = "そのタネは、もう持っていません",
	["you no longer have that spirit"] = "そのスピリットは、もう持っていません",
	["nothing to trade"] = "交換するものがありません",
	["someone's bag is full"] = "だれかのカバンが、いっぱいです",
	["bad request"] = "うまくいきませんでした",
	["bad value"] = "うまくいきませんでした",
	["bad difficulty"] = "難易度が正しくありません",
	["unknown song"] = "その曲が見つかりません",
	["unknown plot"] = "その区画が見つかりません",
	["unknown seed"] = "そのタネが見つかりません",
	["unknown spirit"] = "そのスピリットが見つかりません",
	["unknown tip"] = "うまくいきませんでした",
	["nothing planted"] = "何も植わっていません",
	["too far from the plant"] = "植物から遠すぎます",
	["too far from the plot"] = "区画から遠すぎます",
	["fully grown"] = "もう育ちきっています",
	["no run in progress"] = "プレイ中ではありません",
	["rejected"] = "受け付けられませんでした",
	["the plot is not empty"] = "その区画には、すでに植物があります",
	["you have no such seed"] = "そのタネを持っていません",
	["not ready yet"] = "まだ実になっていません",
	["your bag is full - sell some fruit"] = "カバンがいっぱい！実を売ろう",
	["that plot is not available"] = "その区画は、まだ使えません",
	["not enough coins"] = "コインが足りません",
	["not in stock right now"] = "いまは在庫がありません",
	["walk to the Market to sell"] = "マーケットに行って売ろう",
	["no fruit to sell"] = "売れる実がありません",
	["you have no egg"] = "卵を持っていません",
	["too many spirits"] = "スピリットが多すぎます",
	["nothing to grow"] = "育てる植物がありません",
	["no Instant Grow to use"] = "Instant Grow を持っていません",
	["already ripe"] = "もう実っています",
	["already at the max level"] = "もう最大レベルです",
	["too fast"] = "操作が速すぎます",
	-- lists
	["No seeds. Buy some from the Shop button!"] = "タネがありません。ショップで買おう！",
	["No fruit to sell yet"] = "売れる実が、まだありません",
	["No eggs. Buy one at the Shop"] = "卵がありません。ショップで買おう",
	["You have no spirits yet"] = "スピリットは、まだいません",
	["No ranking yet. Check back in a few minutes"] = "ランキングは、まだありません。数分後にまた見てね",
	["You offer (tap to remove):"] = "あなたが出すもの（タップで外す）:",
	["Add from your bag:"] = "カバンから足す:",
	["Extras (Robux): save time or add a little luck"] = "Robux のおまけ: 時間の節約と、ちょっとした運のプラス",
	["Double Growth: yours! Plants grow twice as fast"] = "Double Growth: 持っています！植物が 2 倍の速さで育つ",
	["  -  every seed is open"] = "  -  すべてのタネが解放ずみ",
	["Plain"] = "ふつう",
	["Garden level"] = "ガーデンレベル",
	["Book entries"] = "図鑑の数",
	["Spirit put away."] = "スピリットをしまいました",
	-- tips shown with a spirit's effect
	["Hatch an egg"] = "卵をかえす",
}

-- { English template, Japanese }.
local TEMPLATES: { { string } } = {
	{ "Garden Lv {}!  New seed in the shop: {}", "ガーデン Lv {1}！ ショップに新しいタネ: {2}" },
	{ "Garden Lv {}!", "ガーデン Lv {1}！" },
	{ "Can't tend now: {}", "いまは世話できません: {t1}" },
	{ "Run not counted: {}", "今回の記録は数えられません: {t1}" },
	{ "Planted {}! Tend it to make it grow", "{1} を植えたよ！世話して育てよう" },
	{ "Plot {} unlocked!", "区画 {1} を解放したよ！" },
	{ "Plot {}: one more plant growing at a time", "区画 {1}: 同時に育てられる植物が 1 つ増えます" },
	{ "Unlock for {} coins", "{1} コインで解放" },
	{
		"The Plot Pass opens {} extra gold plots, on top of the others",
		"Plot Pass で、金の区画が {1} つ増えます（ほかの区画に追加）",
	},
	{ "rest a little more ({}s)", "もう少し休ませよう（{1} 秒）" },
	{ "{} declined", "{1} に断られました" },
	{ "A {} hatched!", "{1} が生まれたよ！" },
	{ "{} is now with you!", "{1} が、そばにいるよ！" },
	{ "Hatch an egg   (you have {})", "卵をかえす   (持っている: {1})" },
	{ "Equipped: {}", "装備中: {1}" },
	{ "Equip {}", "装備: {1}" },
	{ "BPM Rush soon: {}  {}", "もうすぐ BPM Rush: {1}  {2}" },
	{ "BPM Rush! {} seeds mutate more for a while", "BPM Rush！{1} のタネが、しばらく変異しやすいよ" },
	-- market and shop
	{ "Market   {} coins", "マーケット   {1} コイン" },
	{ "Shop Lv {}  {} coins  {}", "ショップ Lv {1}  {2} コイン  {3}" },
	{ "Lv {}   Coins: {}", "Lv {1}   コイン: {2}" },
	{ "Sell all ({} fruit)  +{}", "ぜんぶ売る（{1} 個）  +{2}" },
	{ "Sold {} fruit for {} coins!", "実を {1} 個売って、{2} コインをゲット！" },
	{
		"Bought a Spirit Egg for {}. Hatch it in Spirits",
		"スピリットの卵を {1} コインで買ったよ。スピリットでかえそう",
	},
	{ "Instant Grow! The plant is ripe", "Instant Grow！ 植物が実ったよ" },
	{ "Buy Spirit Egg  {}   (you have {})", "スピリットの卵を買う  {1}   (持っている: {2})" },
	{ "Egg hatches into: {}", "卵から生まれる: {1}" },
	{ "Garden Lv {}  ({}/{} XP)", "ガーデン Lv {1}  ({2}/{3} XP)" },
	{ "Garden Lv {} (max)", "ガーデン Lv {1} (最大)" },
	{ "  -  {} opens at Lv {}", "  -  {1} は Lv {2} で解放" },
	{ "Restock the shop for you  {} R$", "ショップの品ぞろえを入れ替える  {1} R$" },
	{
		"Growth Sprinkler  {} R$  (all plants grow x{} for {} min)",
		"Growth Sprinkler  {1} R$  (すべての植物が {3} 分間、{2} 倍の速さで育つ)",
	},
	{ "  -  on: {} left", "  -  発動中: 残り {1}" },
	{ "Use Instant Grow  (you have {})", "Instant Grow を使う  (持っている: {1})" },
	{
		"Instant Grow  {} R$  (ripens the plant you tended last)",
		"Instant Grow  {1} R$  (最後に世話した植物が、すぐ実る)",
	},
	{
		"Double Growth pass  {} R$  (plants grow x{}, forever)",
		"Double Growth パス  {1} R$  (植物が {2} 倍の速さで育つ・ずっと)",
	},
	-- book, ranking, trade
	{ "Book  {}/{}", "図鑑  {1}/{2}" },
	{
		"Plain fruit +{}, mutations up to +{} coins. Complete a seed: +{} Spirit Egg",
		"ふつうの実 +{1}、変異は最大 +{2} コイン。1 種類そろえると、スピリットの卵 +{3}",
	},
	{ "Ranking: {}   (tap to switch)", "ランキング: {t1}   (タップで切り替え)" },
	{ "You: {}  (not in the top {} yet)", "あなた: {1}  (まだ上位 {2} 位に入っていません)" },
	{ "Trade with {}", "{1} と交換" },
	{ "{} wants to trade with you", "{1} が、あなたと交換したいって" },
	{ "{} offers ~{} coins   |   you offer ~{}", "{1} の出す分 ~{2} コイン   |   あなたの出す分 ~{3}" },
	{ "Waiting for {} to confirm...", "{1} の確定を待っています…" },
	{
		"Waiting for {} to be ready... (tap to take back)",
		"{1} の準備を待っています…（タップで取り消し）",
	},
	{ "{} is ready. Tap when you are", "{1} は準備OK。あなたもできたらタップ" },
	{ "{} offers:", "{1} が出すもの:" },
	{ "  ...and {} more", "  …ほか {1} 個" },
	{ "+ {} seed   (you have {})", "+ {1} のタネ   (持っている: {2})" },
	{ "Open a Gift Box  ({} left)", "ギフトボックスを開ける  (のこり {1})" },
	{ "Goals  {}/{}", "目標  {1}/{2}" },
	{ "Ground lot {}: opens at Lv {}", "地上の区画 {1}: Lv {2} で開く" },
	{ "Sky lot {}: opens at Lv {}", "空の区画 {1}: Lv {2} で開く" },
	{ "Ground lot {}: empty - tap to place", "地上の区画 {1}: あき（タップで置く）" },
	{ "Sky lot {}: empty - tap to place", "空の区画 {1}: あき（タップで置く）" },
	{ "Ground lot {}: {}", "地上の区画 {1}: {2}" },
	{ "Sky lot {}: {}", "空の区画 {1}: {2}" },
	{ "Gift Box! {}", "ギフトボックス！ {1} をゲット" },
	{ "RAINBOW! {}", "レインボー！ {1} をゲット" },
	{ "Harvest {} fruits", "実を {1} 個、収穫しよう" },
	{ "Play the rhythm {} times", "リズムを {1} 回、プレイしよう" },
	{ "Reach a {} combo", "{1} コンボを出そう" },
	{ "Find {} book entries", "図鑑を {1} 個、見つけよう" },
	{ "Have {} spirits", "スピリットを {1} 匹、そろえよう" },
	{ "Reach garden level {}", "ガーデンレベル {1} になろう" },
	{ "{} likes you more!", "{1} が、もっとなついたよ！" },
	{ "Pet your spirits {} times", "スピリットを {1} 回、なでよう" },
	-- spirits' effects
	{ " / mutations x{}", " / 変異率 x{1}" },
	{ " / your tends grow x{}", " / 世話の成長 x{1}" },
	{ " / book coins x{}", " / 図鑑コイン x{1}" },
	{ " / sells x{}", " / 売値 x{1}" },
	{ " / fruit stays fresh x{}", " / 新鮮な時間 x{1}" },
	{ "+{}ms late", "+{1}ms 遅い" },
	{ "{}ms early", "{1}ms 早い" },
	{ "Tends every {}s (+{})", "{1} 秒ごとに世話 (+{2})" },
	-- calibration
	{ "Delay: {} ms", "ずれ: {1} ms" },
	{ "{} taps measured", "{1} 回のタップを測定しました" },
	{
		"{} of {} taps counted - tap with every click",
		"{2} 回のうち {1} 回だけ数えられました - クリックのたびにタップしてね",
	},
	{ "Get ready... {}", "よーい… {1}" },
	-- results
	{ "{}   \u{2665} Favourite song!", "{1}   ♥ お気に入りの曲！" },
	{ "+{} growth  -  {} {}%", "成長 +{1}  -  {t2} {3}%" },
	-- plot prompts
	{ "Harvest - {}!", "収穫 - {1}！" },
	{ "Harvest (overripe) - {}!", "収穫（熟しすぎ）- {1}！" },
	{ "Premium plot {}", "特別な区画 {1}" },
	{ "Plot {}  -  {} coins", "区画 {1}  -  {2} コイン" },
	{ "Buy plot {} first", "先に区画 {1} を買おう" },
	{ "{}'s plant", "{1} の植物" },
}

local compiled: { { pattern: string, ja: string } } = {}
for _, entry in TEMPLATES do
	local escaped = string.gsub(entry[1], "[%^%$%(%)%%%.%[%]%*%+%-%?]", "%%%0")
	local pattern = "^" .. string.gsub(escaped, "{}", "(.-)") .. "$"
	table.insert(compiled, { pattern = pattern, ja = entry[2] })
end

local function fill(ja: string, captures: { string }): string
	return (
		string.gsub(ja, "{(t?)(%d)}", function(translate, index)
			local value = captures[tonumber(index) :: number] or ""
			return if translate == "t" then Loc.ja(value) else value
		end)
	)
end

-- English -> Japanese, whatever the language (the translation itself).
function Loc.ja(text: string): string
	local exact = EXACT[text]
	if exact then
		return exact
	end
	for _, entry in compiled do
		local captures = { string.match(text, entry.pattern) }
		if #captures > 0 then
			return fill(entry.ja, captures)
		end
	end
	return text
end

-- Text in the player's language: Japanese when `lang` is "ja", the English as it is otherwise.
function Loc.t(text: string, lang: string): string
	if lang == "ja" then
		return Loc.ja(text)
	end
	return text
end

Loc.Exact = EXACT
Loc.Templates = TEMPLATES

return Loc
