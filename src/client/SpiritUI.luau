--!strict
-- Beat Spirits screen, drawn as a ranking-style board (BoardUI): hatch eggs, equip one spirit (tap its row), name
-- them. The equipped spirit tends the plant on its own.
-- The server decides what hatches; the odds are shown in the Shop where eggs are sold.

local Players = game:GetService("Players")
local ProximityPromptService = game:GetService("ProximityPromptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local BoardCells = require(script.Parent.BoardCells)
local BoardUI = require(script.Parent.BoardUI)
local GardenState = require(script.Parent.GardenState)
local MarketUI = require(script.Parent.MarketUI)
local UiTheme = require(script.Parent.UiTheme)
local Spirits = require(ReplicatedStorage.Shared.Garden.Spirits)
local Lang = require(script.Parent.Lang)
local TipsUI = require(script.Parent.TipsUI)
local Toast = require(script.Parent.Toast)

local SpiritUI = {}

-- "♥♥♡♡♡": the bond level of a spirit (how much it has been petted).
local function hearts(bond: number?): string
	local level = Spirits.bondLevel(bond or 0)
	return string.rep("\u{2665}", level) .. string.rep("\u{2661}", Spirits.MaxBondLevel - level)
end

-- The names of the traits a spirit has grown: "Glow, Cloud Ride".
local function traitText(spirit: { traits: { string }? }): string
	local names: { string } = {}
	local owned: { string } = if spirit.traits then spirit.traits else {}
	for _, id in owned do
		local trait = Spirits.trait(id)
		if trait then
			table.insert(names, if Lang.code == "ja" then trait.name.ja else trait.name.en)
		end
	end
	return table.concat(names, ", ")
end

-- Two short lines for the EFFECT column: "Every 60s +6" and "Mutation x1.3  Sell x1.1".
local function effectLines(def: Spirits.Def): (string, string)
	local care = Lang.t(`Every {def.autoCareSeconds}s +{def.autoCarePoints}`)
	local bonuses: { string } = {}
	local function add(mult: number, english: string)
		if mult > 1 then
			table.insert(bonuses, Lang.t(`{english} x{mult}`))
		end
	end
	add(def.mutationMult, "Mutation")
	add(def.tendMult, "Tend")
	add(def.discoveryMult, "Book coins")
	add(def.sellMult, "Sell")
	add(def.freshMult, "Fresh")
	return care, table.concat(bonuses, "  ")
end

local MAIN_COLUMNS: { BoardUI.Column } = {
	{ title = "", width = 50 },
	{ title = "SPIRIT", flex = 1 },
	{ title = "LEVEL", width = 84, align = "center" },
	{ title = "BOND", width = 92, align = "center" },
	{ title = "EFFECT", flex = 1.1 },
	{ title = "", width = 96, align = "center" },
}

-- One row per kind and level ("Koke x3"): the spirits of a kind are shown as the one that counts (the equipped one,
-- else the most grown, else the most petted). The equipped row first, then the most petted, then the Spirits order.
local function rowsFor(snapshot: GardenState.Snapshot, equip: (id: string?) -> boolean): { BoardUI.Row }
	BoardCells.refresh()
	type Group = { kind: string, best: any, count: number, equipped: boolean, order: number, level: number }
	local groups: { [string]: Group } = {}
	local order: { Group } = {}
	local kindOrder: { [string]: number } = {}
	for index, def in Spirits.List do
		kindOrder[def.kind] = index
	end
	for _, spirit in snapshot.spirits do
		-- spirits of one kind AND one level share a row: a new Lv1 is not hidden behind a Lv10 of the same kind
		local level = Spirits.levelOf(spirit.xp or 0)
		local key = `{spirit.kind}:{level}`
		local group = groups[key]
		if not group then
			group = {
				kind = spirit.kind,
				best = spirit,
				count = 0,
				equipped = false,
				order = kindOrder[spirit.kind] or 99,
				level = level,
			}
			groups[key] = group
			table.insert(order, group)
		end
		group.count += 1
		if spirit.id == snapshot.equippedSpirit then
			group.equipped = true
			group.best = spirit
		elseif
			not group.equipped
			and (
				(spirit.xp or 0) > (group.best.xp or 0)
				or ((spirit.xp or 0) == (group.best.xp or 0) and (spirit.bond or 0) > (group.best.bond or 0))
			)
		then
			group.best = spirit
		end
	end
	table.sort(order, function(a, b)
		if a.equipped ~= b.equipped then
			return a.equipped
		end
		local aBond, bBond = a.best.bond or 0, b.best.bond or 0
		if aBond ~= bBond then
			return aBond > bBond
		end
		if a.order ~= b.order then
			return a.order < b.order
		end
		return a.level > b.level
	end)

	local rows: { BoardUI.Row } = {}
	for _, group in order do
		local def = Spirits.get(group.kind)
		if def then
			local spirit = group.best
			local equipped = group.equipped
			local nick = Spirits.nickname(spirit.nick, Lang.code)
			local traits = traitText(spirit)
			local care, bonus = effectLines(def)
			local name = def.name.en .. (if group.count > 1 then `  \u{00D7}{group.count}` else "")
			table.insert(rows, {
				lit = equipped,
				onTap = function()
					equip(if equipped then nil else spirit.id)
				end,
				cells = {
					{ icon = { kind = "spirit", id = group.kind } },
					{
						text = if nick then nick else name,
						sub = if nick then name elseif traits ~= "" then `\u{2728} {traits}` else nil,
						bold = true,
						color = if equipped then BoardCells.GoldText else nil,
					},
					{ text = `Lv {group.level}`, bold = true },
					{ text = hearts(spirit.bond), color = BoardCells.hueText("Sakura") },
					{ text = care, sub = if bonus ~= "" then bonus else nil },
					if equipped
						then { text = Lang.t("Equipped"), pill = BoardCells.Gold }
						else { text = Lang.t("Equip"), pill = BoardCells.pill("Sora") },
				},
			})
		end
	end
	return rows
end

function SpiritUI.start()
	local player = Players.LocalPlayer :: Player

	local function hatch(): boolean
		local result = GardenState.call("hatch")
		if result.ok then
			local def = Spirits.get(result.kind)
			Toast.show(`A {if def then def.name.en else result.kind} hatched!`)
		else
			Toast.show(result.reason or "could not hatch")
		end
		return result.ok == true
	end
	local function equip(id: string?): boolean
		local result = GardenState.call("equip", id)
		if not result.ok then
			Toast.show(result.reason or "could not equip")
			return false
		end
		local snapshot = GardenState.get()
		local name = "spirit"
		if snapshot and id then
			for _, spirit in snapshot.spirits do
				local def = if spirit.id == id then Spirits.get(spirit.kind) else nil
				if def then
					name = def.name.en
				end
			end
		end
		Toast.show(if id then `{name} is now with you!` else "Spirit put away")
		return true
	end

	local modal = BoardUI.create("SpiritBoard", function()
		ProximityPromptService.Enabled = true
	end)
	-- Screens inside the board: the spirits (main), the list to choose whom to name (names), and the names for one
	-- spirit (pick).
	type View = { kind: "main" } | { kind: "names" } | { kind: "pick", id: string }
	local view: View = { kind = "main" }
	local render: (GardenState.Snapshot) -> ()

	local function setView(next: View)
		view = next
		local snapshot = GardenState.get()
		if snapshot then
			render(snapshot)
		end
	end

	local function renderMain(snapshot: GardenState.Snapshot)
		modal.setTitle("Spirits")
		local actions: { BoardUI.Action } = {}
		if #snapshot.spirits > 0 then
			table.insert(actions, {
				label = "Names",
				width = 96,
				hue = "Sora",
				onTap = function()
					setView({ kind = "names" })
				end,
			})
		end
		if snapshot.eggs > 0 then
			table.insert(actions, {
				label = `Hatch Egg ({snapshot.eggs})`,
				width = 150,
				hue = "Fuji",
				onTap = function()
					hatch()
				end,
			})
		end
		local hasEquipped = false
		for _, spirit in snapshot.spirits do
			hasEquipped = hasEquipped or spirit.id == snapshot.equippedSpirit
		end
		local note = if #snapshot.spirits > 0 and not hasEquipped
			then "No spirit is with you. Tap one below to equip it"
			elseif snapshot.eggs == 0 then "No eggs. Buy one at the Shop"
			else "Tap the equipped one again to put it away"
		modal.setBar(note, actions)
		modal.setTable(MAIN_COLUMNS, rowsFor(snapshot, equip), "You have no spirits yet")
	end

	local function back(to: View): BoardUI.Action
		return {
			label = "Back",
			width = 96,
			hue = "Fuji",
			onTap = function()
				setView(to)
			end,
		}
	end

	local function renderNames(snapshot: GardenState.Snapshot)
		modal.setTitle("Names")
		modal.setBar("Tap a spirit to choose its name", { back({ kind = "main" }) })
		local kindOrder: { [string]: number } = {}
		for index, def in Spirits.List do
			kindOrder[def.kind] = index
		end
		local ordered = table.clone(snapshot.spirits)
		table.sort(ordered, function(a, b)
			local aEquipped, bEquipped = a.id == snapshot.equippedSpirit, b.id == snapshot.equippedSpirit
			if aEquipped ~= bEquipped then
				return aEquipped
			end
			if (a.bond or 0) ~= (b.bond or 0) then
				return (a.bond or 0) > (b.bond or 0)
			end
			return (kindOrder[a.kind] or 99) < (kindOrder[b.kind] or 99)
		end)
		BoardCells.refresh()
		local rows: { BoardUI.Row } = {}
		for _, spirit in ordered do
			local def = Spirits.get(spirit.kind)
			if def then
				local called = Spirits.nickname(spirit.nick, Lang.code)
				table.insert(rows, {
					lit = spirit.id == snapshot.equippedSpirit,
					onTap = function()
						setView({ kind = "pick", id = spirit.id })
					end,
					cells = {
						{ icon = { kind = "spirit", id = spirit.kind } },
						{ text = def.name.en, bold = true },
						{ text = `Lv {Spirits.levelOf(spirit.xp or 0)}`, bold = true },
						{ text = hearts(spirit.bond), color = BoardCells.hueText("Sakura") },
						if called
							then { text = called, bold = true, color = BoardCells.GoldText }
							else { text = Lang.t("No name"), dim = true },
					},
				})
			end
		end
		modal.setTable({
			{ title = "", width = 50 },
			{ title = "SPIRIT", flex = 1 },
			{ title = "LEVEL", width = 84, align = "center" },
			{ title = "BOND", width = 92, align = "center" },
			{ title = "NAME", flex = 1 },
		}, rows, "You have no spirits yet")
	end

	local function renderPick(snapshot: GardenState.Snapshot, id: string)
		modal.setTitle("Names")
		modal.setBar("Choose a name:", { back({ kind = "names" }) })
		local current: number? = nil
		for _, spirit in snapshot.spirits do
			if spirit.id == id then
				current = spirit.nick
			end
		end
		local function choose(nick: number?)
			local result = GardenState.call("nameSpirit", { id = id, nick = nick })
			if not result.ok then
				Toast.show(result.reason or "that did not work")
				return
			end
			setView({ kind = "names" })
		end
		-- "No name" first (when it has one), then the fixed names.
		local entries: { { text: string, nick: number? } } = {}
		if current then
			table.insert(entries, { text = Lang.t("No name"), nick = nil })
		end
		for index, entry in Spirits.Nicknames do
			table.insert(entries, { text = if Lang.code == "ja" then entry.ja else entry.en, nick = index })
		end
		-- Four names to a row, so all of them fit on a phone screen; the current one is gold.
		BoardCells.refresh()
		local PER_ROW = 4
		local rows: { BoardUI.Row } = {}
		for i, entry in entries do
			local rowIndex = (i - 1) // PER_ROW + 1
			rows[rowIndex] = rows[rowIndex] or { cells = {} }
			local isCurrent = entry.nick ~= nil and entry.nick == current
			table.insert(rows[rowIndex].cells, {
				text = entry.text,
				pill = if isCurrent then BoardCells.Gold else BoardCells.pill("Sora"),
				onTap = function()
					choose(entry.nick)
				end,
			})
		end
		local columns: { BoardUI.Column } = {}
		for _ = 1, PER_ROW do
			table.insert(columns, { title = "", flex = 1, align = "center" })
		end
		modal.setTable(columns, rows)
	end

	render = function(snapshot: GardenState.Snapshot)
		local current = view
		if current.kind == "names" then
			renderNames(snapshot)
		elseif current.kind == "pick" then
			renderPick(snapshot, current.id)
		else
			renderMain(snapshot)
		end
	end
	GardenState.onChanged(function(snapshot)
		if #snapshot.spirits > 0 then
			TipsUI.show("pet")
		end
		if modal.isOpen() then
			render(snapshot)
		end
	end)

	local gui = Instance.new("ScreenGui")
	gui.Name = "SpiritHud"
	gui.ResetOnSpawn = false
	gui.DisplayOrder = 30
	UiTheme.hideDuringRun(gui)
	local button = MarketUI.makeHudButton(gui, "Spirits", 134)
	gui.Parent = player:WaitForChild("PlayerGui")

	button.Activated:Connect(function()
		local snapshot = GardenState.get()
		if not snapshot then
			Toast.show("Still loading...")
			return
		end
		view = { kind = "main" }
		render(snapshot)
		ProximityPromptService.Enabled = false
		modal.open()
	end)
end

return SpiritUI
