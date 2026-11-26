--!strict
-- The collection book: a HUD button that opens a ranking-style board (BoardUI) of the seeds and the variants (plain
-- fruit and mutations) discovered so far. Discovering a variant happens on the server at harvest.

local Players = game:GetService("Players")
local ProximityPromptService = game:GetService("ProximityPromptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local BoardCells = require(script.Parent.BoardCells)
local BoardUI = require(script.Parent.BoardUI)
local Collection = require(ReplicatedStorage.Shared.Garden.Collection)
local GardenState = require(script.Parent.GardenState)
local Lang = require(script.Parent.Lang)
local MarketUI = require(script.Parent.MarketUI)
local Mutations = require(ReplicatedStorage.Shared.Garden.Mutations)
local Palette = require(ReplicatedStorage.Shared.Palette)
local Seeds = require(ReplicatedStorage.Shared.Garden.Seeds)
local Toast = require(script.Parent.Toast)
local UiTheme = require(script.Parent.UiTheme)

local CollectionUI = {}

local function variantName(variant: string): string
	return if variant == Collection.Plain then "Plain" else Mutations.displayName(variant)
end

-- The pill of a variant: plain fruit in Sora, a mutation in its own colour (Palette.Mutation).
local function variantColor(variant: string): Color3
	local colors = (Palette.Mutation :: any)[variant]
	return if colors then colors[1] else BoardCells.pill("Sora")
end

local function columns(): { BoardUI.Column }
	local list: { BoardUI.Column } = {
		{ title = "", width = 50 },
		{ title = "SEED", flex = 1 },
		{ title = "FOUND", width = 62, align = "center" },
	}
	for _, variant in Collection.Variants do
		table.insert(list, { title = variantName(variant), width = 76, align = "center" })
	end
	return list
end

-- One row per seed: the fruit, the name, how many of its variants are found, then a pill per variant.
local function rows(snapshot: GardenState.Snapshot): { BoardUI.Row }
	BoardCells.refresh()
	local list: { BoardUI.Row } = {}
	for _, seed in Seeds.List do
		local found, total = Collection.seedProgress(snapshot.collection, seed.seedId)
		local complete = found == total
		local cells: { BoardUI.Cell } = {
			{ icon = { kind = "plant", id = seed.seedId } },
			{
				text = if Lang.code == "ja" then seed.name.ja else seed.name.en,
				bold = true,
				color = if complete then BoardCells.GoldText else nil,
			},
			{
				text = `{found}/{total}`,
				bold = true,
				color = if complete then BoardCells.GoldText else nil,
				dim = found == 0,
			},
		}
		for _, variant in Collection.Variants do
			local known = snapshot.collection[`{seed.seedId}|{variant}`]
			table.insert(cells, {
				text = if known then "\u{2713}" else "???",
				pill = variantColor(variant),
				dim = not known,
			})
		end
		table.insert(list, { cells = cells, lit = complete })
	end
	return list
end

function CollectionUI.start()
	local player = Players.LocalPlayer :: Player
	local modal = BoardUI.create("BookBoard", function()
		ProximityPromptService.Enabled = true
	end)

	local gui = Instance.new("ScreenGui")
	gui.Name = "BookHud"
	gui.ResetOnSpawn = false
	gui.DisplayOrder = 30
	UiTheme.hideDuringRun(gui)
	local button = MarketUI.makeHudButton(gui, "Book", 174)
	gui.Parent = player:WaitForChild("PlayerGui")

	local function rebuild(snapshot: GardenState.Snapshot)
		local found, total = Collection.progress(snapshot.collection)
		modal.setTitle(`Book  {found}/{total}`)
		modal.setBar(
			`Plain fruit +{Collection.Reward.Normal}, mutations up to +{Collection.Reward.GoldenHour} coins. Complete a seed: +{Collection.CompletionEggs} Spirit Egg`
		)
		modal.setTable(columns(), rows(snapshot))
	end

	GardenState.onChanged(function(snapshot)
		if modal.isOpen() then
			rebuild(snapshot)
		end
	end)

	button.Activated:Connect(function()
		local snapshot = GardenState.get()
		if not snapshot then
			Toast.show("Still loading...")
			return
		end
		rebuild(snapshot)
		ProximityPromptService.Enabled = false
		modal.open()
	end)
end

return CollectionUI
