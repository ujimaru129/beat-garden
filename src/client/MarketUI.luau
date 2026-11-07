--!strict
-- HUD (coins + Market button) and the Market modal: sell fruit, buy seeds.
-- Prototype stand-in for the shop NPC and the market NPC; the server decides every price and result.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GardenState = require(script.Parent.GardenState)
local ListModal = require(script.Parent.ListModal)
local Mutations = require(ReplicatedStorage.Shared.Garden.Mutations)
local Palette = require(ReplicatedStorage.Shared.Palette)
local Seeds = require(ReplicatedStorage.Shared.Garden.Seeds)
local Toast = require(script.Parent.Toast)
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

-- The actions come first (a landscape phone only shows about three rows without scrolling);
-- the details of what is in the bag come last. Coins are in the title.
local function rowsFor(
	snapshot: GardenState.Snapshot,
	sellAll: () -> (),
	buy: (seedId: string) -> ()
): { ListModal.Row }
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

	for _, seed in Seeds.List do
		local own = snapshot.seeds[seed.seedId] or 0
		local affordable = snapshot.coins >= seed.price
		table.insert(rows, {
			text = `Buy {seed.name.en}  {seed.price}   (you have {own})`,
			color = if affordable then Palette.Hues.Matcha.Night else Palette.Rarity.Common,
			onTap = function()
				buy(seed.seedId)
			end,
		})
	end

	for _, key in order do
		local group = groups[key]
		table.insert(rows, { text = `In your bag: {group.label} x{group.count}  ({group.value})` })
	end
	return rows
end

function MarketUI.start()
	local player = Players.LocalPlayer :: Player

	local function sellAll()
		local result = GardenState.call("sellAll")
		if result.ok then
			Toast.show(`Sold {result.count} fruit for {result.total} coins!`)
		else
			Toast.show(result.reason or "could not sell")
		end
	end

	local function buy(seedId: string)
		local result = GardenState.call("buy", seedId)
		if result.ok then
			Toast.show(`Bought {seedName(seedId)} for {result.price}`)
		else
			Toast.show(result.reason or "could not buy")
		end
	end

	local modal = ListModal.create("Market")
	local function rebuild(snapshot: GardenState.Snapshot)
		modal.setTitle(`Market   {snapshot.coins} coins`)
		modal.setRows(rowsFor(snapshot, sellAll, buy))
	end
	GardenState.onChanged(function(snapshot)
		if modal.isOpen() then
			rebuild(snapshot)
		end
	end)

	-- HUD: coins and the Market button, stacked under the Calibrate button.
	local gui = Instance.new("ScreenGui")
	gui.Name = "GardenHud"
	gui.ResetOnSpawn = false
	gui.DisplayOrder = 30

	local coins = Instance.new("TextLabel")
	coins.Position = UDim2.fromOffset(16, 72)
	coins.Size = UDim2.fromOffset(120, 36)
	coins.BackgroundColor3 = Palette.Base.YoruSky
	coins.BackgroundTransparency = 0.25
	coins.TextColor3 = Palette.Hues.Yuzu.Night
	coins.TextScaled = true
	coins.Font = Enum.Font.GothamBold
	coins.Text = "Coins: 0"
	coins.Parent = gui
	local coinsCorner = Instance.new("UICorner")
	coinsCorner.CornerRadius = UDim.new(0, 10)
	coinsCorner.Parent = coins
	local coinsPadding = Instance.new("UIPadding")
	coinsPadding.PaddingTop = UDim.new(0.15, 0)
	coinsPadding.PaddingBottom = UDim.new(0.15, 0)
	coinsPadding.Parent = coins

	local market = Instance.new("TextButton")
	market.Position = UDim2.fromOffset(16, 116)
	market.Size = UDim2.fromOffset(120, 48)
	market.BackgroundColor3 = Palette.Base.Sumi
	market.TextColor3 = Palette.Base.Washi
	market.TextScaled = true
	market.Font = Enum.Font.GothamBold
	market.Text = "Market"
	market.Parent = gui
	local marketCorner = Instance.new("UICorner")
	marketCorner.CornerRadius = UDim.new(0, 12)
	marketCorner.Parent = market
	local marketPadding = Instance.new("UIPadding")
	marketPadding.PaddingTop = UDim.new(0.2, 0)
	marketPadding.PaddingBottom = UDim.new(0.2, 0)
	marketPadding.Parent = market

	gui.Parent = player:WaitForChild("PlayerGui")

	-- The tutorial steps that need the Market light up its button (the one accent colour on screen).
	local function render(snapshot: GardenState.Snapshot)
		coins.Text = `Coins: {snapshot.coins}`
		local needed = snapshot.tutorialStep == Tutorial.Steps.Sell or snapshot.tutorialStep == Tutorial.Steps.Buy
		market.BackgroundColor3 = if needed then Palette.Base.Torii else Palette.Base.Sumi
	end
	GardenState.onChanged(render)
	local first = GardenState.get()
	if first then
		render(first)
	end

	market.Activated:Connect(function()
		local snapshot = GardenState.get()
		if not snapshot then
			Toast.show("Still loading...")
			return
		end
		rebuild(snapshot)
		modal.open()
	end)
end

return MarketUI
