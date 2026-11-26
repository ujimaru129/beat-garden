--!strict
-- Trade screens: tap another player's Trade button -> they accept -> both edit offers -> both press
-- Ready -> both Confirm. Every number (values, who owns what) comes from the server; this module only
-- shows the latest state and sends what the player taps. Closing the trade screen cancels the trade.

local Players = game:GetService("Players")
local ProximityPromptService = game:GetService("ProximityPromptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local BoardCells = require(script.Parent.BoardCells)
local GardenState = require(script.Parent.GardenState)
local Lang = require(script.Parent.Lang)
local ListModal = require(script.Parent.ListModal)
local Mutations = require(ReplicatedStorage.Shared.Garden.Mutations)
local Palette = require(ReplicatedStorage.Shared.Palette)
local Seeds = require(ReplicatedStorage.Shared.Garden.Seeds)
local Spirits = require(ReplicatedStorage.Shared.Garden.Spirits)
local Toast = require(script.Parent.Toast)

local TradeUI = {}

type Offer = { fruits: { number }, seeds: { [string]: number }, spirits: { string } }

type View = {
	partner: { name: string, userId: number },
	myOffer: Offer,
	myItems: any,
	theirItems: any,
	myValue: number,
	theirValue: number,
	myReady: boolean,
	theirReady: boolean,
	myConfirmed: boolean,
	theirConfirmed: boolean,
	stage: string,
}

local MAX_DETAIL_ROWS = 6

local function seedName(seedId: string): string
	local seed = Seeds.get(seedId)
	return if seed then seed.name.en else seedId
end

local function fruitLabel(seedId: string, mutation: string?): string
	local name = seedName(seedId)
	return if mutation then `{Mutations.displayName(mutation)} {name}` else name
end

local function spiritName(kind: string): string
	local def = Spirits.get(kind)
	return if def then def.name.en else kind
end

local function copyOffer(offer: Offer): Offer
	return { fruits = table.clone(offer.fruits), seeds = table.clone(offer.seeds), spirits = table.clone(offer.spirits) }
end

-- The items of a trade as table rows: picture | name | count or value | Add / Remove.
local ITEM_COLUMNS: { BoardCells.Column } = {
	{ title = "", width = 50 },
	{ title = "", flex = 1 },
	{ title = "", width = 84, align = "right" },
	{ title = "", width = 96, align = "center" },
}

type ItemCell = { icon: any, name: string, sub: string?, info: string, gold: boolean? }

local function itemRow(item: ItemCell, pill: string?, hue: string?, onTap: (() -> ())?): ListModal.Row
	return {
		text = item.name,
		columns = ITEM_COLUMNS,
		cells = {
			{ icon = item.icon },
			{
				text = item.name,
				sub = item.sub,
				bold = true,
				color = if item.gold then BoardCells.GoldText else nil,
			},
			{ text = item.info, bold = true },
			if pill and hue then { text = Lang.t(pill), pill = BoardCells.pill(hue) } else {},
		},
		onTap = onTap,
	}
end

local function fruitItem(fruit: any, info: string): ItemCell
	return {
		icon = { kind = "plant", id = fruit.seedId, mutation = fruit.mutation },
		name = fruitLabel(fruit.seedId, fruit.mutation),
		info = info,
		gold = fruit.mutation ~= nil,
	}
end

local function seedItem(seedId: string, count: number): ItemCell
	return { icon = { kind = "plant", id = seedId }, name = seedName(seedId), sub = Lang.t("Seed"), info = `x{count}` }
end

local function spiritItem(kind: string): ItemCell
	return { icon = { kind = "spirit", id = kind }, name = spiritName(kind), sub = Lang.t("Spirit"), info = "" }
end

-- One item per thing described by the server ({fruits, seeds, spirits}).
local function itemCells(items: any): { ItemCell }
	local list: { ItemCell } = {}
	for _, fruit in items.fruits do
		table.insert(list, fruitItem(fruit, `{fruit.value}`))
	end
	for _, seed in items.seeds do
		table.insert(list, seedItem(seed.seedId, seed.count))
	end
	for _, spirit in items.spirits do
		table.insert(list, spiritItem(spirit.kind))
	end
	return list
end

function TradeUI.start()
	local player = Players.LocalPlayer :: Player
	local remote = ReplicatedStorage:WaitForChild("Trade", 10) :: RemoteFunction?
	local event = ReplicatedStorage:WaitForChild("TradeEvent", 10) :: RemoteEvent?
	if not (remote and event) then
		warn("[TradeUI] trade remotes not found")
		return
	end
	local tradeRemote: RemoteFunction = remote

	local function call(action: string, payload: any?): any
		local ok, result = pcall(function()
			return tradeRemote:InvokeServer(action, payload)
		end)
		if not ok or type(result) ~= "table" then
			return { ok = false, reason = "no answer" }
		end
		return result
	end

	local view: View? = nil
	local requestPending = false

	local requestModal: ListModal.Modal
	local tradeModal: ListModal.Modal

	local function setOffer(offer: Offer)
		local result = call("setOffer", offer)
		if not result.ok then
			Toast.show(result.reason or "that did not work")
		end
	end

	-- A section label: a dark thin bar like the head row of a table.
	local function section(label: string): ListModal.Row
		return { text = label, head = true, columns = { { title = "", flex = 1 } }, cells = { { text = label } } }
	end

	local function buildRows(v: View): { ListModal.Row }
		BoardCells.refresh()
		local rows: { ListModal.Row } = {}
		local partner = v.partner.name

		table.insert(rows, { text = `{partner} offers ~{v.theirValue} coins   |   you offer ~{v.myValue}` })

		-- The one action that matters now, then Cancel: both stay near the top of a small screen.
		if v.stage == "confirm" then
			if v.myConfirmed then
				table.insert(rows, { text = `Waiting for {partner} to confirm...` })
			else
				table.insert(rows, {
					text = "CONFIRM TRADE",
					color = Palette.Base.Torii,
					onTap = function()
						local result = call("confirm")
						if not result.ok then
							Toast.show(result.reason or "that did not work")
						end
					end,
				})
			end
			table.insert(rows, {
				text = "Back to editing",
				onTap = function()
					call("ready", false)
				end,
			})
		elseif v.myReady then
			table.insert(rows, {
				text = `Waiting for {partner} to be ready... (tap to take back)`,
				onTap = function()
					call("ready", false)
				end,
			})
		else
			table.insert(rows, {
				text = if v.theirReady then `{partner} is ready. Tap when you are` else "I'm ready",
				color = Palette.Hues.Matcha.Night,
				onTap = function()
					call("ready", true)
				end,
			})
		end
		table.insert(rows, {
			text = "Cancel trade",
			color = Palette.Rarity.Common,
			onTap = function()
				call("cancel")
			end,
		})

		-- What they offer (read only).
		table.insert(rows, section(`{partner} offers:`))
		local theirs = itemCells(v.theirItems)
		if #theirs == 0 then
			table.insert(rows, { text = "  (nothing yet)" })
		end
		for i, item in theirs do
			if i > MAX_DETAIL_ROWS then
				table.insert(rows, { text = `  ...and {#theirs - MAX_DETAIL_ROWS} more` })
				break
			end
			table.insert(rows, itemRow(item))
		end

		-- What I offer: tap an item to take it back.
		table.insert(rows, section("You offer (tap to remove):"))
		local offer = v.myOffer
		for i, fruit in v.myItems.fruits do
			table.insert(
				rows,
				itemRow(fruitItem(fruit, `{fruit.value}`), "Remove", "Sakura", function()
					local next = copyOffer(offer)
					table.remove(next.fruits, i)
					setOffer(next)
				end)
			)
		end
		for seedId, count in offer.seeds do
			table.insert(
				rows,
				itemRow(seedItem(seedId, count), "Remove", "Sakura", function()
					local next = copyOffer(offer)
					if count > 1 then
						next.seeds[seedId] = count - 1
					else
						next.seeds[seedId] = nil
					end
					setOffer(next)
				end)
			)
		end
		for i, spirit in v.myItems.spirits do
			table.insert(
				rows,
				itemRow(spiritItem(spirit.kind), "Remove", "Sakura", function()
					local next = copyOffer(offer)
					table.remove(next.spirits, i)
					setOffer(next)
				end)
			)
		end
		if #offer.fruits == 0 and next(offer.seeds) == nil and #offer.spirits == 0 then
			table.insert(rows, { text = "  (nothing yet)" })
		end

		-- My bag: tap to add.
		local mine = GardenState.get()
		if mine then
			table.insert(rows, section("Add from your bag:"))
			for _, seed in Seeds.List do
				local left = (mine.seeds[seed.seedId] or 0) - (offer.seeds[seed.seedId] or 0)
				if left > 0 then
					table.insert(
						rows,
						itemRow(seedItem(seed.seedId, left), "Add", "Sora", function()
							local next = copyOffer(offer)
							next.seeds[seed.seedId] = (next.seeds[seed.seedId] or 0) + 1
							setOffer(next)
						end)
					)
				end
			end

			-- Fruit: grouped; tapping adds the first one of that group that is not offered yet.
			local offered: { [number]: boolean } = {}
			for _, index in offer.fruits do
				offered[index] = true
			end
			local seenGroup: { [string]: boolean } = {}
			for index, fruit in mine.fruits do
				local key = `{fruit.seedId}|{fruit.mutation or ""}`
				if not offered[index] and not seenGroup[key] then
					seenGroup[key] = true
					local available = 0
					for i, other in mine.fruits do
						if not offered[i] and `{other.seedId}|{other.mutation or ""}` == key then
							available += 1
						end
					end
					table.insert(
						rows,
						itemRow(fruitItem(fruit, `x{available}`), "Add", "Sora", function()
							local next = copyOffer(offer)
							table.insert(next.fruits, index)
							setOffer(next)
						end)
					)
				end
			end

			local offeredSpirits: { [string]: boolean } = {}
			for _, id in offer.spirits do
				offeredSpirits[id] = true
			end
			for _, spirit in mine.spirits do
				if not offeredSpirits[spirit.id] then
					table.insert(
						rows,
						itemRow(spiritItem(spirit.kind), "Add", "Fuji", function()
							local next = copyOffer(offer)
							table.insert(next.spirits, spirit.id)
							setOffer(next)
						end)
					)
				end
			end
		end
		return rows
	end

	local function render()
		local v = view
		if not v then
			return
		end
		tradeModal.setTitle(`Trade with {v.partner.name}`)
		tradeModal.setRows(buildRows(v))
	end

	-- Closing the screen (X or tapping outside) cancels the trade. When the server closed it, `view` is
	-- already nil, so this does nothing.
	tradeModal = ListModal.create("Trade", function()
		ProximityPromptService.Enabled = true
		if view then
			view = nil
			call("cancel")
		end
	end)

	requestModal = ListModal.create("Trade request", function()
		ProximityPromptService.Enabled = true
		if requestPending then
			requestPending = false
			call("respond", false) -- closed without answering = decline
		end
	end)

	GardenState.onChanged(function()
		if tradeModal.isOpen() then
			render()
		end
	end)

	event.OnClientEvent:Connect(function(message: any)
		if type(message) ~= "table" then
			return
		end
		if message.type == "request" then
			requestPending = true
			requestModal.setRows({
				{ text = `{message.from} wants to trade with you` },
				{
					text = "Accept",
					color = Palette.Hues.Matcha.Night,
					onTap = function()
						requestPending = false
						requestModal.close()
						local result = call("respond", true)
						if not result.ok then
							Toast.show(result.reason or "that did not work")
						end
					end,
				},
				{
					text = "Decline",
					color = Palette.Rarity.Common,
					onTap = function()
						requestModal.close() -- the close handler sends the decline
					end,
				},
			})
			ProximityPromptService.Enabled = false
			requestModal.open()
		elseif message.type == "update" then
			view = message :: any
			if requestModal.isOpen() then
				requestPending = false
				requestModal.close()
			end
			ProximityPromptService.Enabled = false
			render()
			tradeModal.open()
		elseif message.type == "closed" then
			view = nil
			requestPending = false
			tradeModal.close()
			requestModal.close()
			Toast.show(if message.reason == "done" then "Trade complete!" else tostring(message.reason))
		end
	end)

	ProximityPromptService.PromptTriggered:Connect(function(prompt: ProximityPrompt)
		if prompt.Name ~= "TradePrompt" then
			return
		end
		local character = prompt.Parent and prompt.Parent.Parent
		local target = character and Players:GetPlayerFromCharacter(character)
		if not target or target == player then
			return
		end
		local result = call("request", target.UserId)
		Toast.show(if result.ok then `Asked {target.DisplayName} to trade...` else (result.reason or "could not ask"))
	end)
end

return TradeUI
