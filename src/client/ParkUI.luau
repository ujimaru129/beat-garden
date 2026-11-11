--!strict
-- The Park screen: open Gift Boxes (goal rewards), see the goals, and choose which attraction stands on which lot.
-- Everything is decided by the server (it owns the boxes and the lots); this only shows state and sends intents.

local Players = game:GetService("Players")
local ProximityPromptService = game:GetService("ProximityPromptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GardenState = require(script.Parent.GardenState)
local Lang = require(script.Parent.Lang)
local ListModal = require(script.Parent.ListModal)
local MarketUI = require(script.Parent.MarketUI)
local Palette = require(ReplicatedStorage.Shared.Palette)
local Park = require(ReplicatedStorage.Shared.Garden.Park)
local Toast = require(script.Parent.Toast)
local UiTheme = require(script.Parent.UiTheme)

local ParkUI = {}

type View = { kind: "main" } | { kind: "goals" } | { kind: "pick", lotId: string }

local function nameOf(attraction: Park.Attraction): string
	return if Lang.code == "ja" then attraction.name.ja else attraction.name.en
end

-- "Carousel (Sakura)" for an item key.
local function itemText(key: string): string
	local attraction, palette = Park.parseKey(key)
	if not attraction or not palette then
		return key
	end
	return `{nameOf(attraction)} ({palette})`
end

local function paletteColor(key: string): Color3?
	local _, palette = Park.parseKey(key)
	if palette and Palette.Hues[palette] then
		return Palette.Hues[palette].Night
	end
	return if palette == "Rainbow" then Palette.Hues.Sakura.Night else nil
end

-- "Ground lot 2" / "Sky lot 1": the lot's number counts within its kind.
local function lotLabel(lot: Park.Lot): (string, string)
	local n = 0
	for _, other in Park.Lots do
		if other.kind == lot.kind then
			n += 1
		end
		if other.id == lot.id then
			break
		end
	end
	return if lot.kind == "ground" then "Ground lot" else "Sky lot", tostring(n)
end

function ParkUI.start()
	local player = Players.LocalPlayer :: Player
	local modal = ListModal.create("Park", function()
		ProximityPromptService.Enabled = true
	end)
	local view: View = { kind = "main" }

	local gui = Instance.new("ScreenGui")
	gui.Name = "ParkHud"
	gui.ResetOnSpawn = false
	gui.DisplayOrder = 30
	UiTheme.hideDuringRun(gui)
	local button = MarketUI.makeHudButton(gui, "Park", 254)
	gui.Parent = player:WaitForChild("PlayerGui")

	local render: (GardenState.Snapshot) -> ()

	local function goBack()
		view = { kind = "main" }
		local snapshot = GardenState.get()
		if snapshot then
			render(snapshot)
		end
	end

	local function openBox(): boolean
		local result = GardenState.call("parkOpen")
		if not result.ok then
			Toast.show(result.reason or "that did not work")
			return false
		end
		Toast.show("...")
		task.wait(0.7)
		local _, palette = Park.parseKey(result.key)
		if palette == "Rainbow" then
			Toast.show(`RAINBOW! {itemText(result.key)}`)
		else
			Toast.show(`Gift Box! {itemText(result.key)}`)
		end
		return true
	end

	local function place(lotId: string, key: string?): boolean
		local result = GardenState.call("parkPlace", { lot = lotId, key = key })
		if not result.ok then
			Toast.show(result.reason or "that did not work")
			return false
		end
		goBack()
		return true
	end

	local function mainRows(snapshot: GardenState.Snapshot): { ListModal.Row }
		local park = snapshot.park
		local rows: { ListModal.Row } = {}
		if park.boxes > 0 then
			table.insert(rows, {
				text = `Open a Gift Box  ({park.boxes} left)`,
				color = Palette.Hues.Yuzu.Night,
				onTap = openBox,
			})
		else
			table.insert(rows, { note = true, text = "Gift Boxes come from goals. Reach a goal to get one!" })
		end
		local done = 0
		for _, goal in Park.Goals do
			if park.claimed[goal.id] then
				done += 1
			end
		end
		table.insert(rows, {
			text = `Goals  {done}/{#Park.Goals}`,
			color = Palette.Hues.Sora.Night,
			onTap = function()
				view = { kind = "goals" }
				render(snapshot)
			end,
		})
		for _, lot in Park.Lots do
			local label, number = lotLabel(lot)
			if snapshot.level.level < lot.level then
				table.insert(rows, { text = `{label} {number}: opens at Lv {lot.level}`, note = true })
			else
				local key = park.placed[lot.id]
				table.insert(rows, {
					text = if key
						then `{label} {number}: {itemText(key)}`
						else `{label} {number}: empty - tap to place`,
					color = if key then paletteColor(key) else Palette.Hues.Matcha.Night,
					onTap = function()
						view = { kind = "pick", lotId = lot.id }
						render(snapshot)
					end,
				})
			end
		end
		return rows
	end

	local function goalRows(snapshot: GardenState.Snapshot): { ListModal.Row }
		local park = snapshot.park
		local rows: { ListModal.Row } = { { text = "Back", onTap = goBack, color = Palette.Hues.Fuji.Night } }
		for _, goal in Park.Goals do
			local progress = math.min(Park.progressOf(goal, park.stats), goal.target)
			if park.claimed[goal.id] then
				table.insert(rows, { text = `\u{2714} {Lang.t(goal.name)}`, color = Palette.Hues.Matcha.Night })
			else
				table.insert(rows, { text = `{Lang.t(goal.name)}  ({progress}/{goal.target})` })
			end
		end
		return rows
	end

	local function pickRows(snapshot: GardenState.Snapshot, lotId: string): { ListModal.Row }
		local park = snapshot.park
		local lot = Park.lot(lotId)
		local rows: { ListModal.Row } = { { text = "Back", onTap = goBack, color = Palette.Hues.Fuji.Night } }
		if not lot then
			return rows
		end
		local keys: { string } = {}
		for key in park.items do
			local attraction = Park.parseKey(key)
			if attraction and attraction.kind == lot.kind then
				table.insert(keys, key)
			end
		end
		table.sort(keys)
		if #keys == 0 then
			table.insert(rows, { note = true, text = "You have nothing for this lot yet. Open Gift Boxes!" })
		else
			table.insert(rows, { note = true, text = "Choose for this lot:" })
		end
		for _, key in keys do
			local here = park.placed[lotId] == key
			table.insert(rows, {
				text = `{if here then "\u{2714} " else ""}{itemText(key)}`,
				color = paletteColor(key),
				onTap = function()
					return place(lotId, key)
				end,
			})
		end
		if park.placed[lotId] then
			table.insert(rows, {
				text = "Clear this lot",
				onTap = function()
					return place(lotId, nil)
				end,
			})
		end
		return rows
	end

	render = function(snapshot: GardenState.Snapshot)
		local current = view
		if current.kind == "goals" then
			modal.setTitle("Goals")
			modal.setRows(goalRows(snapshot))
		elseif current.kind == "pick" then
			modal.setTitle("Park")
			modal.setRows(pickRows(snapshot, current.lotId))
		else
			modal.setTitle("Park")
			modal.setRows(mainRows(snapshot))
		end
	end

	local lastBoxes: number? = nil
	GardenState.onChanged(function(snapshot)
		local boxes = snapshot.park.boxes
		button.Text = Lang.t("Park") .. (if boxes > 0 then ` ({boxes})` else "")
		if lastBoxes ~= nil and boxes > lastBoxes then
			Toast.show("New Gift Box! Open it in Park")
		end
		lastBoxes = boxes
		if modal.isOpen() then
			render(snapshot)
		end
	end)

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

return ParkUI
