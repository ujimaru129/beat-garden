--!strict
-- Player-to-player trading, server side. Flow:
--   request -> the other player accepts -> both edit their offers -> both press Ready ->
--   both Confirm -> the server re-checks everything and swaps the items atomically (Trade.swap).
-- Any change to an offer clears Ready and Confirm, so nobody can be surprised by a last-second
-- swap. The server owns the truth; clients only show state and send intents.
-- Remotes: Trade (RemoteFunction, actions below) and TradeEvent (RemoteEvent, server -> client).

local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Economy = require(ReplicatedStorage.Shared.Garden.Economy)
local PlayerData = require(ReplicatedStorage.Shared.Data.PlayerData)
local PlayerStore = require(script.Parent.PlayerStore)
local Trade = require(ReplicatedStorage.Shared.Garden.Trade)
local Tutorial = require(ReplicatedStorage.Shared.Garden.Tutorial)

local Trading = {}

export type Api = {
	dataOf: (Player) -> PlayerData.Data?,
	persistent: (Player) -> boolean,
	push: (Player) -> (),
}

local REQUEST_RANGE = 40 -- studs between the two characters
local REQUEST_COOLDOWN = 4 -- seconds between requests from one player
local REQUEST_EXPIRE = 30 -- seconds a request stays open

type TradeState = {
	id: string,
	a: Player,
	b: Player,
	offers: { [Player]: Trade.Offer },
	ready: { [Player]: boolean },
	confirmed: { [Player]: boolean },
}

local api: Api
local event: RemoteEvent
local active: { [Player]: TradeState } = {}
local incoming: { [Player]: { from: Player, at: number } } = {}
local lastRequestAt: { [Player]: number } = {}

local function fail(reason: string): any
	return { ok = false, reason = reason }
end

local function other(trade: TradeState, player: Player): Player
	return if trade.a == player then trade.b else trade.a
end

-- What the other player sees of an offer: details of every item with its estimated value.
local function describe(data: PlayerData.Data, offer: Trade.Offer): any
	local fruits = {}
	for _, index in offer.fruits do
		local fruit = data.fruits[index]
		if fruit then
			table.insert(fruits, {
				seedId = fruit.seedId,
				mutation = fruit.mutation,
				weight = fruit.weight,
				value = Economy.fruitValue(fruit.seedId, fruit.mutation, fruit.weight),
			})
		end
	end
	local seeds = {}
	for seedId, count in offer.seeds do
		table.insert(seeds, { seedId = seedId, count = count })
	end
	local spirits = {}
	for _, id in offer.spirits do
		for _, spirit in data.spirits do
			if spirit.id == id then
				table.insert(spirits, { kind = spirit.kind })
			end
		end
	end
	return { fruits = fruits, seeds = seeds, spirits = spirits }
end

local function view(trade: TradeState, me: Player): any
	local partner = other(trade, me)
	local myData = api.dataOf(me)
	local theirData = api.dataOf(partner)
	if not (myData and theirData) then
		return nil
	end
	local mine, theirs = trade.offers[me], trade.offers[partner]
	return {
		type = "update",
		partner = { name = partner.DisplayName, userId = partner.UserId },
		myOffer = mine,
		myItems = describe(myData, mine),
		theirItems = describe(theirData, theirs),
		myValue = Trade.value(myData, mine),
		theirValue = Trade.value(theirData, theirs),
		myReady = trade.ready[me] == true,
		theirReady = trade.ready[partner] == true,
		myConfirmed = trade.confirmed[me] == true,
		theirConfirmed = trade.confirmed[partner] == true,
		stage = if trade.ready[me] and trade.ready[partner] then "confirm" else "edit",
	}
end

local function sendUpdate(trade: TradeState)
	for _, player in { trade.a, trade.b } do
		local v = view(trade, player)
		if v then
			event:FireClient(player, v)
		end
	end
end

local function close(trade: TradeState, reason: string)
	active[trade.a] = nil
	active[trade.b] = nil
	event:FireClient(trade.a, { type = "closed", reason = reason })
	event:FireClient(trade.b, { type = "closed", reason = reason })
end

local function resetApprovals(trade: TradeState)
	trade.ready = {}
	trade.confirmed = {}
end

local function execute(trade: TradeState)
	local da, db = api.dataOf(trade.a), api.dataOf(trade.b)
	if not (da and db) then
		close(trade, "the trade could not finish")
		return
	end
	local offerA, offerB = trade.offers[trade.a], trade.offers[trade.b]
	-- Describe before the swap: afterwards the indices point at different items.
	local entry = {
		at = os.time(),
		a = { userId = trade.a.UserId, gave = describe(da, offerA), value = Trade.value(da, offerA) },
		b = { userId = trade.b.UserId, gave = describe(db, offerB), value = Trade.value(db, offerB) },
	}
	local ok, reason = Trade.swap(da, db, offerA, offerB)
	if not ok then
		close(trade, reason or "the trade could not finish")
		return
	end
	api.push(trade.a)
	api.push(trade.b)
	if api.persistent(trade.a) or api.persistent(trade.b) then
		task.spawn(PlayerStore.logTrade, trade.id, entry)
	end
	print(`[Trading] {trade.a.Name} <-> {trade.b.Name}: done ({entry.a.value} / {entry.b.value} coins)`)
	close(trade, "done")
end

-- ---------------------------------------------------------------------------------------------

local function request(player: Player, payload: unknown): any
	local target = if type(payload) == "number" then Players:GetPlayerByUserId(payload) else nil
	if not target or target == player then
		return fail("no such player")
	end
	local mine, theirs = api.dataOf(player), api.dataOf(target)
	if not (mine and theirs) then
		return fail("not ready")
	end
	if Tutorial.isActive(mine.tutorialStep) then
		return fail("finish the tutorial first")
	end
	if Tutorial.isActive(theirs.tutorialStep) then
		return fail("that player is still in the tutorial")
	end
	if active[player] or active[target] then
		return fail("someone is already trading")
	end
	local now = os.clock()
	if now - (lastRequestAt[player] or -math.huge) < REQUEST_COOLDOWN then
		return fail("wait a moment")
	end
	local pending = incoming[target]
	if pending and now - pending.at < REQUEST_EXPIRE then
		return fail("that player has another request")
	end

	local a = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
	local b = target.Character and target.Character:FindFirstChild("HumanoidRootPart")
	if
		not (a and b and a:IsA("BasePart") and b:IsA("BasePart"))
		or (a.Position - b.Position).Magnitude > REQUEST_RANGE
	then
		return fail("too far away")
	end

	lastRequestAt[player] = now
	incoming[target] = { from = player, at = now }
	event:FireClient(target, { type = "request", from = player.DisplayName, userId = player.UserId })
	return { ok = true }
end

local function respond(player: Player, payload: unknown): any
	local pending = incoming[player]
	incoming[player] = nil
	if not pending or os.clock() - pending.at > REQUEST_EXPIRE or pending.from.Parent == nil then
		return fail("the request has expired")
	end
	local from = pending.from
	if payload ~= true then
		event:FireClient(from, { type = "closed", reason = `{player.DisplayName} declined` })
		return { ok = true }
	end
	if active[player] or active[from] then
		return fail("someone is already trading")
	end
	local trade: TradeState = {
		id = HttpService:GenerateGUID(false),
		a = from,
		b = player,
		offers = { [from] = Trade.emptyOffer(), [player] = Trade.emptyOffer() },
		ready = {},
		confirmed = {},
	}
	active[from] = trade
	active[player] = trade
	sendUpdate(trade)
	return { ok = true }
end

local function setOffer(player: Player, payload: unknown): any
	local trade = active[player]
	local data = api.dataOf(player)
	if not trade or not data then
		return fail("no trade in progress")
	end
	local offer = Trade.sanitizeOffer(payload)
	local ok, reason = Trade.check(data, offer)
	if not ok then
		return fail(reason or "invalid offer")
	end
	trade.offers[player] = offer
	resetApprovals(trade)
	sendUpdate(trade)
	return { ok = true }
end

local function setReady(player: Player, payload: unknown): any
	local trade = active[player]
	if not trade then
		return fail("no trade in progress")
	end
	trade.ready[player] = payload == true
	trade.confirmed = {} -- stepping back (or forward) always restarts the confirm step
	sendUpdate(trade)
	return { ok = true }
end

local function confirm(player: Player): any
	local trade = active[player]
	if not trade then
		return fail("no trade in progress")
	end
	if not (trade.ready[trade.a] and trade.ready[trade.b]) then
		return fail("both players must be ready first")
	end
	trade.confirmed[player] = true
	if trade.confirmed[trade.a] and trade.confirmed[trade.b] then
		execute(trade)
	else
		sendUpdate(trade)
	end
	return { ok = true }
end

local function cancel(player: Player): any
	local trade = active[player]
	if trade then
		close(trade, "cancelled")
	end
	return { ok = true }
end

-- ---------------------------------------------------------------------------------------------

-- A "Trade" button on every player's body: tap another player to ask for a trade.
local function addPrompt(player: Player, character: Model)
	local root = character:WaitForChild("HumanoidRootPart", 10)
	if not (root and root:IsA("BasePart")) then
		return
	end
	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "TradePrompt"
	prompt.ActionText = "Trade"
	prompt.ObjectText = player.DisplayName
	prompt.HoldDuration = 0
	prompt.MaxActivationDistance = 14
	prompt.RequiresLineOfSight = false
	prompt.UIOffset = Vector2.new(0, -90)
	prompt.Parent = root
end

function Trading.start(gardenApi: Api)
	api = gardenApi

	event = Instance.new("RemoteEvent")
	event.Name = "TradeEvent"
	event.Parent = ReplicatedStorage

	local remote = Instance.new("RemoteFunction")
	remote.Name = "Trade"
	remote.Parent = ReplicatedStorage
	remote.OnServerInvoke = function(player: Player, action: unknown, payload: unknown): any
		if action == "request" then
			return request(player, payload)
		elseif action == "respond" then
			return respond(player, payload)
		elseif action == "setOffer" then
			return setOffer(player, payload)
		elseif action == "ready" then
			return setReady(player, payload)
		elseif action == "confirm" then
			return confirm(player)
		elseif action == "cancel" then
			return cancel(player)
		end
		return nil
	end

	local function onPlayerAdded(player: Player)
		player.CharacterAdded:Connect(function(character)
			addPrompt(player, character)
		end)
		if player.Character then
			task.spawn(addPrompt, player, player.Character)
		end
	end
	Players.PlayerAdded:Connect(onPlayerAdded)
	for _, player in Players:GetPlayers() do
		onPlayerAdded(player)
	end

	Players.PlayerRemoving:Connect(function(player)
		local trade = active[player]
		if trade then
			close(trade, "the other player left")
		end
		incoming[player] = nil
		lastRequestAt[player] = nil
	end)
end

return Trading
