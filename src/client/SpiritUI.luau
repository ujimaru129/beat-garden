--!strict
-- Beat Spirits screen: hatch eggs, equip one spirit. The equipped spirit tends the plant on its own.
-- The server decides what hatches; the odds are shown in the Shop where eggs are sold.

local Players = game:GetService("Players")
local ProximityPromptService = game:GetService("ProximityPromptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GardenState = require(script.Parent.GardenState)
local ListModal = require(script.Parent.ListModal)
local MarketUI = require(script.Parent.MarketUI)
local UiTheme = require(script.Parent.UiTheme)
local Palette = require(ReplicatedStorage.Shared.Palette)
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

-- "Spirit Lv 3": named so it is not taken for the garden level.
local function levelLabel(level: number): string
	return if Lang.code == "ja" then `\u{30B9}\u{30D4}\u{30EA}\u{30C3}\u{30C8} Lv {level}` else `Spirit Lv {level}`
end

-- "Spirit Lv 3" and, when it has grown any, the names of its traits: "Glow, Cloud Ride".
local function growthText(spirit: { xp: number?, traits: { string }? }): (string, string)
	local level = Spirits.levelOf(spirit.xp or 0)
	local names: { string } = {}
	local owned: { string } = if spirit.traits then spirit.traits else {}
	for _, id in owned do
		local trait = Spirits.trait(id)
		if trait then
			table.insert(names, if Lang.code == "ja" then trait.name.ja else trait.name.en)
		end
	end
	return levelLabel(level), table.concat(names, ", ")
end

-- One short line: "Tends every 60s (+6) / mutations x1.3".
local function effectText(def: Spirits.Def): string
	local text = Lang.t(`Tends every {def.autoCareSeconds}s (+{def.autoCarePoints})`)
	if def.mutationMult > 1 then
		text ..= Lang.t(` / mutations x{def.mutationMult}`)
	end
	if def.tendMult > 1 then
		text ..= Lang.t(` / your tends grow x{def.tendMult}`)
	end
	if def.discoveryMult > 1 then
		text ..= Lang.t(` / book coins x{def.discoveryMult}`)
	end
	if def.sellMult > 1 then
		text ..= Lang.t(` / sells x{def.sellMult}`)
	end
	if def.freshMult > 1 then
		text ..= Lang.t(` / fruit stays fresh x{def.freshMult}`)
	end
	return text
end

local function rowsFor(
	snapshot: GardenState.Snapshot,
	hatch: () -> boolean,
	equip: (id: string?) -> boolean,
	openNames: () -> ()
): { ListModal.Row }
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
	else
		table.insert(rows, { text = "Give your spirits names", color = Palette.Hues.Sora.Night, onTap = openNames })
	end
	-- One row per kind ("Koke x3"): the spirits of a kind are shown as the one that counts (the equipped one, else the
	-- most petted, else the first hatched). Rows: the equipped kind first, then the most petted, then the kind in the
	-- order of the Spirits list.
	type Group = { kind: string, best: any, count: number, equipped: boolean, order: number }
	local groups: { [string]: Group } = {}
	local order: { Group } = {}
	local kindOrder: { [string]: number } = {}
	for index, def in Spirits.List do
		kindOrder[def.kind] = index
	end
	for _, spirit in snapshot.spirits do
		local group = groups[spirit.kind]
		if not group then
			group =
				{ kind = spirit.kind, best = spirit, count = 0, equipped = false, order = kindOrder[spirit.kind] or 99 }
			groups[spirit.kind] = group
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
		return a.order < b.order
	end)
	for _, group in order do
		local def = Spirits.get(group.kind)
		if def then
			local spirit = group.best
			local equipped = group.equipped
			local called = Spirits.nickname(spirit.nick, Lang.code) or def.name.en
			local title = Lang.t(if equipped then `Equipped: {called}` else `Equip {called}`)
			local levelText, traitText = growthText(spirit)
			table.insert(rows, {
				text = `{hearts(spirit.bond)}  {title}  {levelText}{if group.count > 1
					then `  \u{00D7}{group.count}`
					else ""}\n{effectText(def)}{if traitText ~= "" then `\n\u{2728} {traitText}` else ""}`,
				color = if equipped then Palette.Hues.Yuzu.Night else nil,
				selected = equipped,
				icon = { kind = "spirit", id = group.kind },
				onTap = function()
					return equip(if equipped then nil else spirit.id)
				end,
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

	local modal = ListModal.create("Spirits", function()
		ProximityPromptService.Enabled = true
	end)
	-- Screens inside the modal: the spirits (main), the list to choose whom to name (names), and the names for one
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

	local function namesRows(snapshot: GardenState.Snapshot): { ListModal.Row }
		local rows: { ListModal.Row } = {
			{
				text = "Back",
				color = Palette.Hues.Fuji.Night,
				onTap = function()
					setView({ kind = "main" })
				end,
			},
			{ note = true, text = "Tap a spirit to choose its name" },
		}
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
		for _, spirit in ordered do
			local def = Spirits.get(spirit.kind)
			if def then
				local called = Spirits.nickname(spirit.nick, Lang.code)
				table.insert(rows, {
					text = `{hearts(spirit.bond)}  {def.name.en}  {levelLabel(Spirits.levelOf(spirit.xp or 0))}{if called
						then `  \u{300C}{called}\u{300D}`
						else ""}`,
					selected = spirit.id == snapshot.equippedSpirit,
					icon = { kind = "spirit", id = spirit.kind },
					onTap = function()
						setView({ kind = "pick", id = spirit.id })
					end,
				})
			end
		end
		return rows
	end

	local function pickRows(snapshot: GardenState.Snapshot, id: string): { ListModal.Row }
		local rows: { ListModal.Row } = {
			{
				text = "Back",
				color = Palette.Hues.Fuji.Night,
				onTap = function()
					setView({ kind = "names" })
				end,
			},
		}
		local current: number? = nil
		for _, spirit in snapshot.spirits do
			if spirit.id == id then
				current = spirit.nick
			end
		end
		table.insert(rows, { note = true, text = "Choose a name:" })
		local function choose(nick: number?): boolean
			local result = GardenState.call("nameSpirit", { id = id, nick = nick })
			if not result.ok then
				Toast.show(result.reason or "that did not work")
				return false
			end
			setView({ kind = "names" })
			return true
		end
		if current then
			table.insert(rows, {
				text = "No name",
				onTap = function()
					return choose(nil)
				end,
			})
		end
		for index, entry in Spirits.Nicknames do
			table.insert(rows, {
				text = if Lang.code == "ja" then entry.ja else entry.en,
				selected = current == index,
				onTap = function()
					return choose(index)
				end,
			})
		end
		return rows
	end

	render = function(snapshot: GardenState.Snapshot)
		local current = view
		if current.kind == "names" then
			modal.setTitle("Names")
			modal.setRows(namesRows(snapshot))
		elseif current.kind == "pick" then
			modal.setTitle("Names")
			modal.setRows(pickRows(snapshot, current.id))
		else
			modal.setTitle("Spirits")
			modal.setRows(rowsFor(snapshot, hatch, equip, function()
				setView({ kind = "names" })
			end))
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
