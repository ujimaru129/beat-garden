--!strict
-- Beat Spirits screen: hatch eggs, equip one spirit. The equipped spirit tends the plant on its own.
-- The server decides what hatches; the odds are shown in the Shop where eggs are sold.

local Players = game:GetService("Players")
local ProximityPromptService = game:GetService("ProximityPromptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GardenState = require(script.Parent.GardenState)
local ListModal = require(script.Parent.ListModal)
local MarketUI = require(script.Parent.MarketUI)
local Palette = require(ReplicatedStorage.Shared.Palette)
local Spirits = require(ReplicatedStorage.Shared.Garden.Spirits)
local Toast = require(script.Parent.Toast)

local SpiritUI = {}

local function effectText(def: Spirits.Def): string
	local text = `tends the plant every {def.autoCareSeconds}s (+{def.autoCarePoints})`
	if def.mutationMult > 1 then
		text ..= `, mutations x{def.mutationMult}`
	end
	return text
end

local function rowsFor(snapshot: GardenState.Snapshot, hatch: () -> (), equip: (id: string?) -> ()): { ListModal.Row }
	local rows: { ListModal.Row } = {}
	if snapshot.eggs > 0 then
		table.insert(rows, {
			text = `Hatch an egg   (you have {snapshot.eggs})`,
			color = Palette.Hues.Fuji.Night,
			onTap = hatch,
		})
	else
		table.insert(rows, { text = "No eggs. Buy one at the Shop" })
	end

	if #snapshot.spirits == 0 then
		table.insert(rows, { text = "You have no spirits yet" })
	end
	for _, spirit in snapshot.spirits do
		local def = Spirits.get(spirit.kind)
		if def then
			local equipped = spirit.id == snapshot.equippedSpirit
			table.insert(rows, {
				text = `{if equipped then "Equipped: " else "Equip "}{def.name.en} - {effectText(def)}`,
				color = if equipped then Palette.Hues.Yuzu.Night else nil,
				onTap = function()
					equip(if equipped then nil else spirit.id)
				end,
			})
		end
	end
	return rows
end

function SpiritUI.start()
	local player = Players.LocalPlayer :: Player

	local function hatch()
		local result = GardenState.call("hatch")
		if result.ok then
			local def = Spirits.get(result.kind)
			Toast.show(`A {if def then def.name.en else result.kind} hatched!`)
		else
			Toast.show(result.reason or "could not hatch")
		end
	end
	local function equip(id: string?)
		local result = GardenState.call("equip", id)
		if not result.ok then
			Toast.show(result.reason or "could not equip")
		end
	end

	local modal = ListModal.create("Spirits", function()
		ProximityPromptService.Enabled = true
	end)
	local function rebuild(snapshot: GardenState.Snapshot)
		modal.setRows(rowsFor(snapshot, hatch, equip))
	end
	GardenState.onChanged(function(snapshot)
		if modal.isOpen() then
			rebuild(snapshot)
		end
	end)

	local gui = Instance.new("ScreenGui")
	gui.Name = "SpiritHud"
	gui.ResetOnSpawn = false
	gui.DisplayOrder = 30
	local button = MarketUI.makeHudButton(gui, "Spirits", 172)
	gui.Parent = player:WaitForChild("PlayerGui")

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

return SpiritUI
