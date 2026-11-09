--!strict
-- The collection book: a HUD button that opens the list of seeds with the variants (plain fruit and
-- mutations) discovered so far. Discovering a variant happens on the server at harvest.

local Players = game:GetService("Players")
local ProximityPromptService = game:GetService("ProximityPromptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Collection = require(ReplicatedStorage.Shared.Garden.Collection)
local GardenState = require(script.Parent.GardenState)
local ListModal = require(script.Parent.ListModal)
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

local function rows(snapshot: GardenState.Snapshot): { ListModal.Row }
	local list: { ListModal.Row } = {}
	for _, seed in Seeds.List do
		local found, total = Collection.seedProgress(snapshot.collection, seed.seedId)
		local marks: { string } = {}
		for _, variant in Collection.Variants do
			local known = snapshot.collection[`{seed.seedId}|{variant}`]
			table.insert(marks, if known then `\u{25CF} {variantName(variant)}` else "\u{25CB} ???")
		end
		table.insert(list, {
			text = `{seed.name.en}  {found}/{total}   {table.concat(marks, "  ")}`,
			color = if found == total then Palette.Hues.Yuzu.Night else nil,
		})
	end
	table.insert(list, {
		note = true,
		text = `Plain fruit +{Collection.Reward.Normal}, mutations up to +{Collection.Reward.GoldenHour} coins. Complete a seed: +{Collection.CompletionEggs} Spirit Egg`,
	})
	return list
end

function CollectionUI.start()
	local player = Players.LocalPlayer :: Player
	local modal = ListModal.create("Book", function()
		ProximityPromptService.Enabled = true
	end)

	local gui = Instance.new("ScreenGui")
	gui.Name = "BookHud"
	gui.ResetOnSpawn = false
	gui.DisplayOrder = 30
	UiTheme.hideDuringRun(gui)
	local button = MarketUI.makeHudButton(gui, "Book", 228)
	gui.Parent = player:WaitForChild("PlayerGui")

	local function rebuild(snapshot: GardenState.Snapshot)
		local found, total = Collection.progress(snapshot.collection)
		modal.setTitle(`Book  {found}/{total}`)
		modal.setRows(rows(snapshot))
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
