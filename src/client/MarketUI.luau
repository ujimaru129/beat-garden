--!strict
-- The coin counter and Shop button (HUD), the Shop screen (buy seeds and eggs) and the Market
-- screen (sell fruit). The Shop opens from the HUD button or the Seed Shop NPC; the Market opens
-- only from the Market NPC, and the server only lets you sell near it. The server decides every
-- price and result.

local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ProximityPromptService = game:GetService("ProximityPromptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local GardenState = require(script.Parent.GardenState)
local Lang = require(script.Parent.Lang)
local ListModal = require(script.Parent.ListModal)
local Genres = require(ReplicatedStorage.Shared.Garden.Genres)
local Mutations = require(ReplicatedStorage.Shared.Garden.Mutations)
local Palette = require(ReplicatedStorage.Shared.Palette)
local Progression = require(ReplicatedStorage.Shared.Garden.Progression)
local Products = require(ReplicatedStorage.Shared.Garden.Products)
local Seeds = require(ReplicatedStorage.Shared.Garden.Seeds)
local Shop = require(ReplicatedStorage.Shared.Garden.Shop)
local Spirits = require(ReplicatedStorage.Shared.Garden.Spirits)
local Toast = require(script.Parent.Toast)
local UiTheme = require(script.Parent.UiTheme)
local Tutorial = require(ReplicatedStorage.Shared.Garden.Tutorial)

local MarketUI = {}

-- The shop's stock for a snapshot: the shared stock of the current slot, or the personal restock if it is still valid.
local function stockFor(snapshot: GardenState.Snapshot): { string }
	local slot = Shop.slotOf(math.floor(Workspace:GetServerTimeNow()))
	local shift = if snapshot.restockSlot == slot then snapshot.restockShift else 0
	return Shop.stock(slot, snapshot.level.level, shift)
end

local function seedName(seedId: string): string
	local seed = Seeds.get(seedId)
	return if seed then seed.name.en else seedId
end

local function fruitLabel(seedId: string, mutation: string?): string
	local name = seedName(seedId)
	return if mutation then `{Mutations.displayName(mutation)} {name}` else name
end

-- "  \u{2605}\u{2605}\u{2606}\u{2606}\u{2606}" for the seed's mastery; nothing until the first harvest.
local function stars(snapshot: GardenState.Snapshot, seedId: string): string
	local count = Progression.starsFor(snapshot.mastery[seedId] or 0)
	if count == 0 then
		return ""
	end
	return "  " .. string.rep("\u{2605}", count) .. string.rep("\u{2606}", Progression.MaxStars - count)
end

-- The actions come first (a landscape phone only shows about three rows without scrolling).
local function shopRows(
	snapshot: GardenState.Snapshot,
	buy: (seedId: string) -> boolean,
	buyEgg: () -> boolean,
	purchase: (what: string) -> ()
): { ListModal.Row }
	local rows: { ListModal.Row } = {}
	-- The stock changes every few minutes; it is worked out from the server clock, like on the server.
	for _, seedId in stockFor(snapshot) do
		local seed = Seeds.get(seedId) :: Seeds.Seed
		local own = snapshot.seeds[seed.seedId] or 0
		local genre = (Genres.Names :: any)[seed.favoriteGenre]
		table.insert(rows, {
			text = `{seed.name.en}  {seed.price}   ({own})   {seed.rarity}  \u{2665} {genre.en}{stars(
				snapshot,
				seed.seedId
			)}`,
			color = if snapshot.coins >= seed.price then Palette.Hues.Matcha.Night else Palette.Rarity.Common,
			onTap = function()
				return buy(seed.seedId)
			end,
		})
	end
	table.insert(rows, {
		text = `Buy Spirit Egg  {Spirits.EggPrice}   (you have {snapshot.eggs})`,
		color = if snapshot.coins >= Spirits.EggPrice then Palette.Hues.Fuji.Night else Palette.Rarity.Common,
		onTap = buyEgg,
	})
	-- Paid random items must show their odds.
	local odds: { string } = {}
	for _, o in Spirits.odds() do
		table.insert(odds, `{(Spirits.get(o.kind) :: Spirits.Def).name.en} {o.percent}%`)
	end
	table.insert(rows, { note = true, text = `Egg hatches into: {table.concat(odds, ", ")}` })
	-- Garden level: what opens next.
	local level = snapshot.level
	local nextSeed: Seeds.Seed? = nil
	for _, seed in Seeds.List do
		local opensAt = Progression.unlockLevelOf(seed.seedId)
		if opensAt > level.level and (nextSeed == nil or opensAt < Progression.unlockLevelOf(nextSeed.seedId)) then
			nextSeed = seed
		end
	end
	local progressText = if level.need > 0
		then `Garden Lv {level.level}  ({level.into}/{level.need} XP)`
		else `Garden Lv {level.level} (max)`
	local nextText = if nextSeed
		then `  -  {nextSeed.name.en} opens at Lv {Progression.unlockLevelOf(nextSeed.seedId)}`
		else "  -  every seed is open"
	table.insert(rows, { note = true, text = Lang.t(progressText) .. Lang.t(nextText) })

	-- Robux items, last and quiet: nothing here is needed to play.
	table.insert(rows, { note = true, text = "Extras (Robux): save time or add a little luck" })
	local function extra(text: string, what: string)
		table.insert(rows, {
			text = text,
			onTap = function()
				purchase(what)
			end,
		})
	end
	extra(`Restock the shop for you  {Products.Prices.Restock} R$`, "Restock")
	local sprinklerText = Lang.t(
		`Growth Sprinkler  {Products.Prices.Sprinkler} R$  (all plants grow x{1 + Products.SprinklerGrowBonus} for {Products.SprinklerSeconds // 60} min)`
	)
	if snapshot.sprinklerLeft > 0 then
		sprinklerText ..= Lang.t(
			`  -  on: {snapshot.sprinklerLeft // 60}:{string.format("%02d", snapshot.sprinklerLeft % 60)} left`
		)
	end
	extra(sprinklerText, "Sprinkler")
	extra(
		if snapshot.instantCredits > 0
			then `Use Instant Grow  (you have {snapshot.instantCredits})`
			else `Instant Grow  {Products.Prices.InstantGrow} R$  (ripens the plant you tended last)`,
		"InstantGrow"
	)
	if snapshot.hasDoubleGrowth then
		table.insert(rows, { text = "Double Growth: yours! Plants grow twice as fast" })
	else
		extra(
			`Double Growth pass  {Products.Prices.DoubleGrowth} R$  (plants grow x{Products.GrowSpeedMult}, forever)`,
			"DoubleGrowth"
		)
	end
	return rows
end

local function sellRows(snapshot: GardenState.Snapshot, sellAll: () -> boolean): { ListModal.Row }
	local rows: { ListModal.Row } = {}
	local total = 0
	local groups: { [string]: { label: string, count: number, value: number } } = {}
	local order: { string } = {}
	for _, fruit in snapshot.fruits do
		total += fruit.value
		local key = `{fruit.seedId}|{fruit.mutation or ""}`
		local group = groups[key]
		if not group then
			group = { label = fruitLabel(fruit.seedId, fruit.mutation), count = 0, value = 0 }
			groups[key] = group
			table.insert(order, key)
		end
		group.count += 1
		group.value += fruit.value
	end
	total = math.round(total * snapshot.sellMult)
	if #snapshot.fruits == 0 then
		table.insert(rows, { text = "No fruit to sell yet" })
	else
		table.insert(rows, {
			text = `Sell all ({#snapshot.fruits} fruit)  +{total}`,
			color = Palette.Hues.Yuzu.Night,
			onTap = sellAll,
		})
	end
	for _, key in order do
		local group = groups[key]
		table.insert(rows, { text = `{group.label} x{group.count}  ({group.value})` })
	end
	return rows
end

local function makeHudButton(gui: ScreenGui, text: string, y: number): TextButton
	local button = Instance.new("TextButton")
	button.AnchorPoint = Vector2.new(1, 0)
	button.Position = UDim2.new(1, -12, 0, y)
	button.Size = UDim2.fromOffset(104, 36)
	button.TextScaled = true
	button.Text = Lang.t(text)
	button.Parent = gui
	local limit = Instance.new("UITextSizeConstraint")
	limit.MaxTextSize = 18
	limit.Parent = button
	UiTheme.watch(function()
		UiTheme.styleButton(button, UiTheme.get(), "Sora", 12)
	end)
	return button
end

MarketUI.makeHudButton = makeHudButton

function MarketUI.start()
	local player = Players.LocalPlayer :: Player

	local function reportResult(result: any, success: string): boolean
		Toast.show(if result.ok then success else (result.reason or "that did not work"))
		return result.ok == true
	end

	local function sellAll(): boolean
		local result = GardenState.call("sellAll")
		return reportResult(result, `Sold {result.count} fruit for {result.total} coins!`)
	end
	local function buy(seedId: string): boolean
		local result = GardenState.call("buy", seedId)
		return reportResult(result, `Bought {seedName(seedId)} for {result.price}`)
	end
	local function buyEgg(): boolean
		local result = GardenState.call("buyEgg")
		return reportResult(result, `Bought a Spirit Egg for {result.price}. Hatch it in Spirits`)
	end

	-- Robux items. A developer product is bought through Roblox's own purchase window; the server grants it (see
	-- Garden.processReceipt). An Instant Grow is used on the plant the player tended last, as soon as it is paid.
	local waitingInstant = false
	local function useInstantGrow()
		local plotKey = tostring(player:GetAttribute("LastPlotKey") or "1")
		local result = GardenState.call("useInstantGrow", plotKey)
		reportResult(result, "Instant Grow! The plant is ripe")
	end
	local function purchase(what: string)
		if what == "InstantGrow" then
			local snapshot = GardenState.get()
			if snapshot and snapshot.instantCredits > 0 then
				useInstantGrow()
				return
			end
		end
		local id = if what == "Restock"
			then Products.RestockId
			elseif what == "Sprinkler" then Products.SprinklerId
			elseif what == "InstantGrow" then Products.InstantGrowId
			else Products.DoubleGrowthPassId
		if id <= 0 then
			Toast.show("Coming soon!")
			return
		end
		if what == "DoubleGrowth" then
			MarketplaceService:PromptGamePassPurchase(player, id)
		else
			waitingInstant = what == "InstantGrow"
			MarketplaceService:PromptProductPurchase(player, id)
		end
	end
	local lastCredits = 0
	GardenState.onChanged(function(snapshot)
		-- a paid Instant Grow arrives as a credit: use it right away
		if waitingInstant and snapshot.instantCredits > lastCredits then
			waitingInstant = false
			useInstantGrow()
		end
		lastCredits = snapshot.instantCredits
	end)

	-- The world prompts sit over the modals, so they are off while a modal is open.
	local function onClose()
		ProximityPromptService.Enabled = true
	end
	local shop = ListModal.create("Shop", onClose)
	local market = ListModal.create("Market", onClose)

	local function shopTitle(snapshot: GardenState.Snapshot): string
		local left = Shop.secondsLeft(math.floor(Workspace:GetServerTimeNow()))
		return `Shop Lv {snapshot.level.level}  {snapshot.coins} coins  {left // 60}:{string.format("%02d", left % 60)}`
	end
	local shownStock = ""
	local function rebuildShop(snapshot: GardenState.Snapshot)
		shop.setTitle(shopTitle(snapshot))
		shownStock = table.concat(stockFor(snapshot), ",")
		shop.setRows(shopRows(snapshot, buy, buyEgg, purchase))
	end
	-- While the shop is open the countdown ticks, and the rows are rebuilt when the stock changes.
	task.spawn(function()
		while true do
			task.wait(1)
			local snapshot = GardenState.get()
			if snapshot and shop.isOpen() then
				if table.concat(stockFor(snapshot), ",") ~= shownStock then
					rebuildShop(snapshot)
				else
					shop.setTitle(shopTitle(snapshot))
				end
			end
		end
	end)
	local function rebuildMarket(snapshot: GardenState.Snapshot)
		market.setTitle(`Market   {snapshot.coins} coins`)
		market.setRows(sellRows(snapshot, sellAll))
	end

	local function open(modal: ListModal.Modal, rebuild: (GardenState.Snapshot) -> ())
		local snapshot = GardenState.get()
		if not snapshot then
			Toast.show("Still loading...")
			return
		end
		rebuild(snapshot)
		ProximityPromptService.Enabled = false
		modal.open()
	end

	-- HUD: coins and the Shop button, stacked under the Calibrate button.
	local gui = Instance.new("ScreenGui")
	gui.Name = "GardenHud"
	gui.ResetOnSpawn = false
	gui.DisplayOrder = 30

	local coins = Instance.new("TextLabel")
	coins.AnchorPoint = Vector2.new(1, 0)
	coins.Position = UDim2.new(1, -12, 0, 52)
	coins.Size = UDim2.fromOffset(150, 38)
	coins.TextScaled = true
	coins.Text = "Coins: 0"
	coins.Parent = gui
	-- A thin XP bar along the bottom edge of the counter: how far to the next garden level.
	local xpTrack = Instance.new("Frame")
	xpTrack.AnchorPoint = Vector2.new(0.5, 1)
	xpTrack.Position = UDim2.new(0.5, 0, 1, -2)
	xpTrack.Size = UDim2.new(1, -20, 0, 4)
	xpTrack.BackgroundColor3 = Color3.new(0, 0, 0)
	xpTrack.BackgroundTransparency = 0.7
	xpTrack.BorderSizePixel = 0
	xpTrack.ZIndex = 5
	xpTrack.Parent = coins
	local xpFill = Instance.new("Frame")
	xpFill.Size = UDim2.fromScale(0, 1)
	xpFill.BackgroundColor3 = Color3.fromHex("#3DFFB0")
	xpFill.BorderSizePixel = 0
	xpFill.ZIndex = 6
	xpFill.Parent = xpTrack
	for _, bar in { xpTrack, xpFill } do
		local round = Instance.new("UICorner")
		round.CornerRadius = UDim.new(1, 0)
		round.Parent = bar
	end
	local coinsPad = Instance.new("UIPadding")
	coinsPad.PaddingTop = UDim.new(0, 1)
	coinsPad.PaddingBottom = UDim.new(0, 11)
	coinsPad.Parent = coins
	local coinsLimit = Instance.new("UITextSizeConstraint")
	coinsLimit.MaxTextSize = 16
	coinsLimit.Parent = coins
	UiTheme.watch(function()
		local theme = UiTheme.get()
		UiTheme.stylePanel(coins, theme, 10)
		UiTheme.styleText(coins, theme, "head")
		coins.TextColor3 = theme.hue("Yuzu")
		if not theme.night then
			coins.TextColor3 = Color3.fromHex("#B8860B")
		end
	end)

	UiTheme.hideDuringRun(gui)
	local shopButton = makeHudButton(gui, "Shop", 94)
	gui.Parent = player:WaitForChild("PlayerGui")

	-- The tutorial step that asks for a purchase lights up the Shop button (the one accent colour).
	local function render(snapshot: GardenState.Snapshot)
		coins.Text = `Lv {snapshot.level.level}   Coins: {snapshot.coins}`
		local level = snapshot.level
		xpFill.Size = UDim2.fromScale(if level.need > 0 then level.into / level.need else 1, 1)
		UiTheme.setAccent(shopButton, snapshot.tutorialStep == Tutorial.Steps.Buy)
		if shop.isOpen() then
			rebuildShop(snapshot)
		end
		if market.isOpen() then
			rebuildMarket(snapshot)
		end
	end
	GardenState.onChanged(render)
	local first = GardenState.get()
	if first then
		render(first)
	end

	shopButton.Activated:Connect(function()
		open(shop, rebuildShop)
	end)

	ProximityPromptService.PromptTriggered:Connect(function(prompt: ProximityPrompt)
		if prompt.Name == "ShopPrompt" then
			open(shop, rebuildShop)
		elseif prompt.Name == "MarketPrompt" then
			open(market, rebuildMarket)
		end
	end)
end

return MarketUI
