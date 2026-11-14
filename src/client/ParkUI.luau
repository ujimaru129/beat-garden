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
local TipsUI = require(script.Parent.TipsUI)
local Toast = require(script.Parent.Toast)
local UiTheme = require(script.Parent.UiTheme)

local ParkUI = {}

type View = { kind: "main" } | { kind: "goals" } | { kind: "daily" }

local HEADER_HEIGHT = 74 -- the fixed row of lots

local function nameOf(attraction: Park.Attraction): string
	return if Lang.code == "ja" then attraction.name.ja else attraction.name.en
end

local function kindOf(key: string): string
	local attraction = Park.parseKey(key)
	return if attraction then attraction.kind else "ground"
end

-- "Carousel (Sakura)" for an item key.
local function itemText(key: string): string
	local attraction, palette = Park.parseKey(key)
	if not attraction or not palette then
		return key
	end
	return `{nameOf(attraction)} ({palette})`
end

-- Ground lots and things are green, sky lots and things are pink: a colour only fits its own colour.
local function kindColor(kind: string): Color3
	return if kind == "ground" then Palette.Hues.Matcha.Night else Palette.Hues.Sakura.Night
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
	modal.setCompact(true) -- thin rows: the item list is long
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

	-- The empty lot that the next item goes into (tapped in the fixed row at the top).
	local selectedLot: string? = nil
	local header = modal.header
	local tiles: { [string]: TextButton } = {}

	local function lotName(lot: Park.Lot): string
		local _, number = lotLabel(lot)
		return if Lang.code == "ja"
			then `{if lot.kind == "ground" then "\u{5730}\u{4E0A}" else "\u{7A7A}"}{number}`
			else `{if lot.kind == "ground" then "Ground" else "Sky"} {number}`
	end

	local function place(lotId: string, key: string?): boolean
		local result = GardenState.call("parkPlace", { lot = lotId, key = key })
		if not result.ok then
			Toast.show(result.reason or "that did not work")
			return false
		end
		selectedLot = nil
		return true
	end

	-- Puts an item into the lot that was chosen at the top (an empty one of the item's kind).
	local function putItem(snapshot: GardenState.Snapshot, key: string): boolean
		local attraction = Park.parseKey(key)
		local chosen = if selectedLot then Park.lot(selectedLot) else nil
		if not attraction then
			return false
		end
		if not chosen or snapshot.park.placed[chosen.id] then
			Toast.show("Tap an empty lot at the top first")
			return false
		end
		if chosen.kind ~= attraction.kind then
			Toast.show(
				if attraction.kind == "ground" then "That one goes on a ground lot" else "That one goes on a sky lot"
			)
			return false
		end
		return place(chosen.id, key)
	end

	-- The fixed row at the top: every lot, with what stands on it. Tap one to choose where the next item goes.
	local function renderHeader(snapshot: GardenState.Snapshot)
		for _, tile in tiles do
			tile:Destroy()
		end
		table.clear(tiles)
		local theme = UiTheme.get()
		local count = #Park.Lots
		local gap = 6
		for index, lot in Park.Lots do
			local open = snapshot.level.level >= lot.level
			local key = snapshot.park.placed[lot.id]
			local tile = Instance.new("TextButton")
			tile.Name = lot.id
			tile.AnchorPoint = Vector2.new(0, 0)
			tile.Size = UDim2.new(1 / count, -gap, 1, 0)
			tile.Position = UDim2.new((index - 1) / count, gap / 2, 0, 0)
			tile.TextScaled = true
			tile.RichText = false
			tile.Font = theme.body
			local lines = lotName(lot)
			if not open then
				lines ..= `\nLv {lot.level}`
			elseif key then
				local attraction = Park.parseKey(key)
				lines ..= `\n{if attraction then nameOf(attraction) else key}`
			else
				lines ..= "\n-"
			end
			tile.Text = lines
			local limit = Instance.new("UITextSizeConstraint")
			limit.MaxTextSize = 15
			limit.MinTextSize = 8
			limit.Parent = tile
			local pad = Instance.new("UIPadding")
			pad.PaddingLeft = UDim.new(0, 4)
			pad.PaddingRight = UDim.new(0, 4)
			pad.PaddingTop = UDim.new(0, 4)
			pad.PaddingBottom = UDim.new(0, 4)
			pad.Parent = tile
			if open then
				UiTheme.styleButton(tile, theme, if lot.kind == "ground" then "Matcha" else "Sakura", 10, false)
				if theme.night then
					tile.TextColor3 = kindColor(lot.kind)
				end
			else
				tile.BackgroundTransparency = 0.8
				tile.BackgroundColor3 = Color3.new(0.5, 0.5, 0.55)
				tile.TextColor3 = theme.subText
			end
			if selectedLot == lot.id then
				local stroke = Instance.new("UIStroke")
				stroke.Color = Color3.new(1, 1, 1)
				stroke.Thickness = 4
				stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
				stroke.Parent = tile
			end
			tile.Activated:Connect(function()
				if not open then
					Toast.show(`Opens at Lv {lot.level}`)
					return
				end
				if key then
					-- a lot with something on it: tap to empty it, and it is chosen for the next item
					if place(lot.id, nil) then
						selectedLot = lot.id
					end
					return
				end
				selectedLot = if selectedLot == lot.id then nil else lot.id
				local latest = GardenState.get()
				if latest then
					render(latest)
				end
			end)
			tile.Parent = header
			tiles[lot.id] = tile
		end
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
		local missionsDone = 0
		for _, mission in snapshot.daily.missions do
			if mission.claimed then
				missionsDone += 1
			end
		end
		table.insert(rows, {
			text = `Daily Missions  {missionsDone}/{#snapshot.daily.missions}`,
			color = Palette.Hues.Yuzu.Night,
			onTap = function()
				view = { kind = "daily" }
				render(snapshot)
			end,
		})
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

		-- Your items: tap one to put it on the lot you chose above (or the first empty one that fits).
		local chosen = if selectedLot then Park.lot(selectedLot) else nil
		-- With a lot chosen, only the items that fit it are listed (ground = green, sky = pink).
		local keys: { string } = {}
		for key in park.items do
			local attraction = Park.parseKey(key)
			if attraction and (not chosen or attraction.kind == chosen.kind) then
				table.insert(keys, key)
			end
		end
		table.sort(keys)
		local where: { [string]: Park.Lot } = {}
		for _, lot in Park.Lots do
			local key = park.placed[lot.id]
			if key then
				where[key] = lot
			end
		end
		if #keys == 0 then
			table.insert(rows, { note = true, text = "You have nothing to place yet. Open Gift Boxes!" })
		elseif not chosen then
			table.insert(rows, { note = true, text = "1. Tap an empty lot   2. Tap an item" })
		end
		for _, key in keys do
			local lot = where[key]
			table.insert(rows, {
				text = if lot then `{itemText(key)}  \u{2192} {lotName(lot)}` else itemText(key),
				color = kindColor(kindOf(key)),
				onTap = function()
					return putItem(snapshot, key)
				end,
			})
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

	local function dailyRows(snapshot: GardenState.Snapshot): { ListModal.Row }
		local daily = snapshot.daily
		local rows: { ListModal.Row } = { { text = "Back", onTap = goBack, color = Palette.Hues.Fuji.Night } }
		table.insert(rows, {
			note = true,
			text = `Login streak: {daily.streak} days (every 7th day: a Gift Box)`,
		})
		for _, mission in daily.missions do
			if mission.claimed then
				table.insert(rows, { text = `\u{2714} {Lang.t(mission.name)}`, color = Palette.Hues.Matcha.Night })
			else
				table.insert(rows, { text = `{Lang.t(mission.name)}  ({mission.progress}/{mission.target})` })
			end
		end
		table.insert(rows, {
			note = true,
			text = if daily.bonus
				then "All three done: a Gift Box was added!"
				else `Each mission pays {daily.missionCoins} coins. Finish all three for a Gift Box`,
		})
		table.insert(rows, {
			note = true,
			text = `New missions in {math.ceil(daily.secondsLeft / 3600)} hours`,
		})
		return rows
	end

	render = function(snapshot: GardenState.Snapshot)
		local current = view
		if current.kind == "goals" then
			modal.setHeaderHeight(0)
			modal.setTitle("Goals")
			modal.setRows(goalRows(snapshot))
		elseif current.kind == "daily" then
			modal.setHeaderHeight(0)
			modal.setTitle("Daily Missions")
			modal.setRows(dailyRows(snapshot))
		else
			modal.setTitle("Park")
			modal.setHeaderHeight(HEADER_HEIGHT)
			renderHeader(snapshot)
			modal.setRows(mainRows(snapshot))
		end
	end

	local lastBoxes: number? = nil
	local shownNoticeDay = 0
	local lastClaimed: number? = nil
	local lastDay = 0
	GardenState.onChanged(function(snapshot)
		local boxes = snapshot.park.boxes
		-- today's login bonus, once per day and session; then a hint about the missions
		local notice = snapshot.daily.notice
		if notice and notice.day ~= shownNoticeDay then
			shownNoticeDay = notice.day
			Toast.show(
				if notice.box
					then `Daily bonus! Day {notice.streak}: +{notice.coins} coins and a Gift Box!`
					else `Daily bonus! Day {notice.streak}: +{notice.coins} coins`
			)
			TipsUI.show("daily")
		end
		-- a mission that was just finished
		local claimed = 0
		for _, mission in snapshot.daily.missions do
			if mission.claimed then
				claimed += 1
			end
		end
		local dayKey = if notice then notice.day else 0
		if lastClaimed ~= nil and dayKey == lastDay and claimed > lastClaimed then
			Toast.show(`Mission done! +{snapshot.daily.missionCoins} coins`)
		end
		lastClaimed = claimed
		lastDay = dayKey
		if boxes > 0 then
			TipsUI.show("park")
		end
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
		selectedLot = nil
		render(snapshot)
		ProximityPromptService.Enabled = false
		modal.open()
	end)
end

return ParkUI
