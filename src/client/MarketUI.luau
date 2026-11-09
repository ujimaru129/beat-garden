--!strict
-- The coin counter and Shop button (HUD), the Shop screen (buy seeds and eggs) and the Market
-- screen (sell fruit). The Shop opens from the HUD button or the Seed Shop NPC; the Market opens
-- only from the Market NPC, and the server only lets you sell near it. The server decides every
-- price and result.

local Players = game:GetService("Players")
local ProximityPromptService = game:GetService("ProximityPromptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local GardenState = require(script.Parent.GardenState)
local ListModal = require(script.Parent.ListModal)
local Genres = require(ReplicatedStorage.Shared.Garden.Genres)
local Mutations = require(ReplicatedStorage.Shared.Garden.Mutations)
local Palette = require(ReplicatedStorage.Shared.Palette)
local Seeds = require(ReplicatedStorage.Shared.Garden.Seeds)
local Shop = require(ReplicatedStorage.Shared.Garden.Shop)
local Spirits = require(ReplicatedStorage.Shared.Garden.Spirits)
local Toast = require(script.Parent.Toast)
local UiTheme = require(script.Parent.UiTheme)
local Tutorial = require(ReplicatedStorage.Shared.Garden.Tutorial)

local MarketUI = {}

local function seedName(seedId: string): string
	local seed = Seeds.get(seedId)
	return if seed then seed.name.en else seedId
end

local function fruitLabel(seedId: string, mutation: string?): string
	local name = seedName(seedId)
	return if mutation then `{Mutations.displayName(mutation)} {name}` else name
end

-- The actions come first (a landscape phone only shows about three rows without scrolling).
local function shopRows(
	snapshot: GardenState.Snapshot,
	buy: (seedId: string) -> (),
	buyEgg: () -> ()
): { ListModal.Row }
	local rows: { ListModal.Row } = {}
	-- The stock changes every few minutes; it is worked out from the server clock, like on the server.
	local stock = Shop.stock(Shop.slotOf(math.floor(Workspace:GetServerTimeNow())))
	for _, seedId in stock do
		local seed = Seeds.get(seedId) :: Seeds.Seed
		local own = snapshot.seeds[seed.seedId] or 0
		local genre = (Genres.Names :: any)[seed.favoriteGenre]
		table.insert(rows, {
			text = `{seed.name.en}  {seed.price}   ({own})   {seed.rarity}  \u{2665} {genre.en}`,
			color = if snapshot.coins >= seed.price then Palette.Hues.Matcha.Night else Palette.Rarity.Common,
			onTap = function()
				buy(seed.seedId)
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
	return rows
end

local function sellRows(snapshot: GardenState.Snapshot, sellAll: () -> ()): { ListModal.Row }
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
	button.Position = UDim2.new(1, -16, 0, y)
	button.Size = UDim2.fromOffset(120, 48)
	button.TextScaled = true
	button.Text = text
	button.Parent = gui
	local limit = Instance.new("UITextSizeConstraint")
	limit.MaxTextSize = 24
	limit.Parent = button
	UiTheme.watch(function()
		UiTheme.styleButton(button, UiTheme.get(), "Sora", 12)
	end)
	return button
end

MarketUI.makeHudButton = makeHudButton

function MarketUI.start()
	local player = Players.LocalPlayer :: Player

	local function reportResult(result: any, success: string)
		Toast.show(if result.ok then success else (result.reason or "that did not work"))
	end

	local function sellAll()
		local result = GardenState.call("sellAll")
		reportResult(result, `Sold {result.count} fruit for {result.total} coins!`)
	end
	local function buy(seedId: string)
		local result = GardenState.call("buy", seedId)
		reportResult(result, `Bought {seedName(seedId)} for {result.price}`)
	end
	local function buyEgg()
		local result = GardenState.call("buyEgg")
		reportResult(result, `Bought a Spirit Egg for {result.price}. Hatch it in Spirits`)
	end

	-- The world prompts sit over the modals, so they are off while a modal is open.
	local function onClose()
		ProximityPromptService.Enabled = true
	end
	local shop = ListModal.create("Shop", onClose)
	local market = ListModal.create("Market", onClose)

	local function shopTitle(coins: number): string
		local left = Shop.secondsLeft(math.floor(Workspace:GetServerTimeNow()))
		return `Shop  {coins} coins  new stock {left // 60}:{string.format("%02d", left % 60)}`
	end
	local shownStock = ""
	local function rebuildShop(snapshot: GardenState.Snapshot)
		shop.setTitle(shopTitle(snapshot.coins))
		shownStock = table.concat(Shop.stock(Shop.slotOf(math.floor(Workspace:GetServerTimeNow()))), ",")
		shop.setRows(shopRows(snapshot, buy, buyEgg))
	end
	-- While the shop is open the countdown ticks, and the rows are rebuilt when the stock changes.
	task.spawn(function()
		while true do
			task.wait(1)
			local snapshot = GardenState.get()
			if snapshot and shop.isOpen() then
				local now = Shop.stock(Shop.slotOf(math.floor(Workspace:GetServerTimeNow())))
				if table.concat(now, ",") ~= shownStock then
					rebuildShop(snapshot)
				else
					shop.setTitle(shopTitle(snapshot.coins))
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
	coins.Position = UDim2.new(1, -16, 0, 72)
	coins.Size = UDim2.fromOffset(120, 36)
	coins.TextScaled = true
	coins.Text = "Coins: 0"
	coins.Parent = gui
	local coinsLimit = Instance.new("UITextSizeConstraint")
	coinsLimit.MaxTextSize = 22
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
	local shopButton = makeHudButton(gui, "Shop", 116)
	gui.Parent = player:WaitForChild("PlayerGui")

	-- The tutorial step that asks for a purchase lights up the Shop button (the one accent colour).
	local function render(snapshot: GardenState.Snapshot)
		coins.Text = `Coins: {snapshot.coins}`
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
