--!strict
-- Garden: one plot per player with a plant that grows from time and from tending, plus the
-- economy around it (plant, harvest with a mutation roll, buy seeds, sell fruit) and saving.
--
-- Remotes (both RemoteFunctions, every answer is { ok, ... } and the server decides every number):
--   Tend    "begin", difficulty | "submit", summary      -- the rhythm run
--   Garden  "state" | "plant", seedId | "harvest" | "buy", seedId | "sellAll" | "setLatency", ms
-- After every change the server pushes a snapshot to that player with the GardenUpdate event.

local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Difficulty = require(ReplicatedStorage.Shared.Difficulty)
local Economy = require(ReplicatedStorage.Shared.Garden.Economy)
local Growth = require(ReplicatedStorage.Shared.Garden.Growth)
local Mutations = require(ReplicatedStorage.Shared.Garden.Mutations)
local Npcs = require(script.Parent.Npcs)
local Palette = require(ReplicatedStorage.Shared.Palette)
local PlayerData = require(ReplicatedStorage.Shared.Data.PlayerData)
local PlayerStore = require(script.Parent.PlayerStore)
local RhythmEngine = require(ReplicatedStorage.Shared.RhythmEngine)
local Seeds = require(ReplicatedStorage.Shared.Garden.Seeds)
local Spirits = require(ReplicatedStorage.Shared.Garden.Spirits)
local Trading = require(script.Parent.Trading)
local TestCharts = require(ReplicatedStorage.Shared.Dev.TestCharts)
local Tutorial = require(ReplicatedStorage.Shared.Garden.Tutorial)

local Garden = {}

local PLOT_KEY = "1" -- one plot for now (Extra Plot adds more keys)
local PLOT_SPACING = 14 -- studs between neighbouring plots
local PLOT_DISTANCE = 10 -- studs from the spawn
-- The spawn pad is 12 studs wide and players appear anywhere on it, so the prompt must reach from the
-- far corner. The server allows some extra distance on top for lag.
local PROMPT_RANGE = 20
local TEND_RANGE = 32
local AUTOSAVE_SECONDS = 60

-- Short cooldown in Studio so it can be tried repeatedly.
local COOLDOWN_SECONDS = if RunService:IsStudio() then 10 else Growth.TendCooldownSeconds

local STAGE_LOOK: { [string]: { size: number, color: Color3 } } = {
	Seed = { size = 0.8, color = Palette.Base.Sumi },
	Sprout = { size = 1.8, color = Palette.Hues.Matcha.Day },
	Sapling = { size = 3.2, color = Palette.Hues.Matcha.Night },
	Bloom = { size = 4.4, color = Palette.Hues.Sakura.Day },
	Fruit = { size = 5, color = Palette.Hues.Yuzu.Night },
}

type Pending = { segment: RhythmEngine.Segment, startedAt: number, difficulty: Difficulty.Name }

type Session = {
	player: Player,
	slot: number,
	store: PlayerStore.Session,
	soil: Part,
	plant: Part,
	prompt: ProximityPrompt,
	pending: Pending?,
	nextAutoCare: number, -- unix seconds: when the equipped spirit tends next
}

local sessions: { [Player]: Session } = {}
local updateEvent: RemoteEvent

local function data(s: Session): PlayerData.Data
	return s.store.data
end

local function plotOf(s: Session): Growth.Plot?
	return data(s).plots[PLOT_KEY]
end

local function seedOf(plot: Growth.Plot): Seeds.Seed
	return Seeds.get(plot.seedId) :: Seeds.Seed -- sanitize() guarantees the seed exists
end

local function fractionOf(plot: Growth.Plot, now: number): number
	return Growth.fraction(plot, seedOf(plot).growSeconds, now)
end

local function equippedSpiritDef(s: Session): Spirits.Def?
	local d = data(s)
	if not d.equippedSpirit then
		return nil
	end
	for _, spirit in d.spirits do
		if spirit.id == d.equippedSpirit then
			return Spirits.get(spirit.kind)
		end
	end
	return nil
end

local function advanceTutorial(s: Session, event: Tutorial.Event)
	local d = data(s)
	d.tutorialStep = Tutorial.advance(d.tutorialStep, event)
end

-- What the owner's client needs to draw the HUD and the market.
local function snapshot(s: Session): any
	local d = data(s)
	local now = os.time()
	local fruits = {}
	for _, fruit in d.fruits do
		table.insert(fruits, {
			seedId = fruit.seedId,
			mutation = fruit.mutation,
			weight = fruit.weight,
			value = Economy.fruitValue(fruit.seedId, fruit.mutation, fruit.weight),
		})
	end
	local plotInfo = nil
	local plot = plotOf(s)
	if plot then
		local fraction = fractionOf(plot, now)
		plotInfo = { seedId = plot.seedId, fraction = fraction, stage = Growth.stageFor(fraction) }
	end
	return {
		coins = d.coins,
		seeds = table.clone(d.seeds),
		fruits = fruits,
		plot = plotInfo,
		settings = { latencyMs = d.settings.latencyMs },
		persistent = s.store.persistent,
		tutorialStep = d.tutorialStep,
		eggs = d.eggs,
		spirits = table.clone(d.spirits),
		equippedSpirit = d.equippedSpirit,
	}
end

local function push(s: Session)
	updateEvent:FireClient(s.player, snapshot(s))
end

-- Redraws the plant and the prompt from the data.
local function refresh(s: Session)
	local spiritDef = equippedSpiritDef(s)
	s.soil:SetAttribute("SpiritKind", if spiritDef then spiritDef.kind else nil)
	local plot = plotOf(s)
	if not plot then
		s.plant.Transparency = 1
		s.soil:SetAttribute("Stage", "Empty")
		s.soil:SetAttribute("Fraction", 0)
		s.prompt.ActionText = "Plant"
		return
	end
	local fraction = fractionOf(plot, os.time())
	local stage = Growth.stageFor(fraction)
	local look = STAGE_LOOK[stage]
	s.plant.Transparency = 0
	s.plant.Size = Vector3.new(look.size, look.size, look.size)
	s.plant.Color = look.color
	s.plant.Position = s.soil.Position + Vector3.new(0, s.soil.Size.Y / 2 + look.size / 2, 0)
	s.soil:SetAttribute("Stage", stage)
	s.soil:SetAttribute("Fraction", fraction)
	s.prompt.ActionText = if stage == "Fruit" then "Harvest" else "Tend"
end

local function spawnPosition(): Vector3
	local spawn = Workspace:FindFirstChildWhichIsA("SpawnLocation", true)
	return if spawn then spawn.Position else Vector3.zero
end

local function groundY(x: number, z: number): number
	local hit = Workspace:Raycast(Vector3.new(x, 200, z), Vector3.new(0, -400, 0))
	return if hit then hit.Position.Y else 0
end

local function freeSlot(): number
	local used: { [number]: boolean } = {}
	for _, s in sessions do
		used[s.slot] = true
	end
	local slot = 1
	while used[slot] do
		slot += 1
	end
	return slot
end

local function buildPlotParts(player: Player, slot: number, container: Instance): (Part, Part, ProximityPrompt)
	local base = spawnPosition()
	local x = base.X + (slot - 1) * PLOT_SPACING
	local z = base.Z - PLOT_DISTANCE

	local soil = Instance.new("Part")
	soil.Name = `Plot_{player.UserId}`
	soil.Anchored = true
	soil.Size = Vector3.new(7, 0.6, 7)
	soil.Position = Vector3.new(x, groundY(x, z) + 0.3, z)
	soil.Color = Palette.Base.YoruGround
	soil.Material = Enum.Material.SmoothPlastic
	soil:SetAttribute("OwnerUserId", player.UserId)
	soil.Parent = container

	local plant = Instance.new("Part")
	plant.Name = "Plant"
	plant.Shape = Enum.PartType.Ball
	plant.Anchored = true
	plant.CanCollide = false
	plant.Material = Enum.Material.SmoothPlastic
	plant.Parent = soil

	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "TendPrompt"
	prompt.ActionText = "Tend"
	prompt.ObjectText = `{player.DisplayName}'s plant`
	prompt.HoldDuration = 0
	prompt.MaxActivationDistance = PROMPT_RANGE
	prompt.RequiresLineOfSight = false
	prompt.KeyboardKeyCode = Enum.KeyCode.E
	prompt.UIOffset = Vector2.new(0, -90) -- lift the button off the bottom edge of a phone screen
	prompt.Parent = soil

	return soil, plant, prompt
end

local function distanceToPlot(s: Session): number
	local character = s.player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not (root and root:IsA("BasePart")) then
		return math.huge
	end
	return (root.Position - s.soil.Position).Magnitude
end

local function fail(reason: string): any
	return { ok = false, reason = reason }
end

-- ---------------------------------------------------------------------------------------------
-- Tend (the rhythm run)

local function tendBegin(s: Session, payload: unknown): any
	if type(payload) ~= "string" or table.find(Difficulty.Names, payload) == nil then
		return fail("bad difficulty")
	end
	local difficulty = payload :: Difficulty.Name
	local plot = plotOf(s)
	if not plot then
		return fail("nothing planted")
	end
	if distanceToPlot(s) > TEND_RANGE then
		return fail("too far from the plant")
	end
	local now = os.time()
	if Growth.stageFor(fractionOf(plot, now)) == "Fruit" then
		return fail("fully grown")
	end
	local wait = Growth.cooldownLeft(plot, now, COOLDOWN_SECONDS)
	if wait > 0 then
		return { ok = false, reason = `rest a little more ({wait}s)`, cooldown = wait }
	end

	-- Prototype: the test charts stand in for a real song's tend segments.
	local segment = (TestCharts :: any)[difficulty] :: RhythmEngine.Segment
	local pending = (
		{ segment = segment, startedAt = os.clock(), difficulty = difficulty :: Difficulty.Name } :: any
	) :: Pending
	s.pending = pending
	return { ok = true, segment = segment, bpm = TestCharts.Bpm[difficulty], difficulty = difficulty }
end

local function tendSubmit(s: Session, payload: unknown): any
	local pending = s.pending
	s.pending = nil
	if not pending then
		return fail("no run in progress")
	end
	local plot = plotOf(s)
	if not plot then
		return fail("nothing planted")
	end
	local elapsedMs = (os.clock() - pending.startedAt) * 1000
	local result = RhythmEngine.Validator.validate(pending.segment, payload, { elapsedMs = elapsedMs })
	if not result.ok or not result.tally then
		print(`[Garden] {s.player.Name}: run rejected ({result.reason})`)
		return fail(result.reason or "rejected")
	end

	local tally = result.tally
	local points = Growth.tendPoints(tally.accuracy, pending.difficulty)
	local mutationMult = Difficulty.MutationChanceMultiplier[pending.difficulty]
	local now = os.time()
	Growth.applyTend(plot, points, tally.maxPerfectStreak, mutationMult, now)
	local d = data(s)
	if d.tutorialStep == Tutorial.Steps.Tend then
		-- Tutorial: the first tend always finishes the plant, so the player can harvest right away.
		plot.careGauge = math.max(plot.careGauge, seedOf(plot).growSeconds)
	end
	advanceTutorial(s, "tend")
	d.stats.tends += 1
	d.stats.perfects += tally.counts.Perfect
	refresh(s)
	push(s)

	local fraction = fractionOf(plot, now)
	print(`[Garden] {s.player.Name}: {pending.difficulty} acc {math.floor(tally.accuracy * 100)}% -> +{points} growth`)
	return {
		ok = true,
		points = points,
		difficulty = pending.difficulty,
		stage = Growth.stageFor(fraction),
		fraction = fraction,
		cooldown = COOLDOWN_SECONDS,
		counts = tally.counts,
		maxCombo = tally.maxCombo,
		accuracy = tally.accuracy,
	}
end

-- ---------------------------------------------------------------------------------------------
-- Garden actions

local function plant(s: Session, payload: unknown): any
	if type(payload) ~= "string" or Seeds.get(payload) == nil then
		return fail("unknown seed")
	end
	if plotOf(s) then
		return fail("the plot is not empty")
	end
	if distanceToPlot(s) > TEND_RANGE then
		return fail("too far from the plot")
	end
	local d = data(s)
	local count = d.seeds[payload] or 0
	if count < 1 then
		return fail("you have no such seed")
	end
	if count > 1 then
		d.seeds[payload] = count - 1
	else
		d.seeds[payload] = nil
	end
	d.plots[PLOT_KEY] = Growth.newPlot(payload, os.time())
	advanceTutorial(s, "plant")
	refresh(s)
	push(s)
	return { ok = true, seedId = payload }
end

local function harvest(s: Session): any
	local plot = plotOf(s)
	if not plot then
		return fail("nothing planted")
	end
	if distanceToPlot(s) > TEND_RANGE then
		return fail("too far from the plant")
	end
	if Growth.stageFor(fractionOf(plot, os.time())) ~= "Fruit" then
		return fail("not ready yet")
	end
	local d = data(s)
	if #d.fruits >= PlayerData.MaxFruits then
		return fail("your bag is full - sell some fruit")
	end

	local spiritDef = equippedSpiritDef(s)
	local chanceMult = plot.mutationMult * (if spiritDef then spiritDef.mutationMult else 1)
	local mutation = Mutations.roll(plot.bestPerfectStreak, chanceMult, math.random)
	local weight = Economy.rollWeight(math.random)
	table.insert(d.fruits, { seedId = plot.seedId, mutation = mutation, weight = weight })
	d.stats.harvests += 1
	d.plots[PLOT_KEY] = nil
	advanceTutorial(s, "harvest")
	refresh(s)
	push(s)

	local value = Economy.fruitValue(plot.seedId, mutation, weight)
	print(`[Garden] {s.player.Name}: harvested {plot.seedId} mutation={mutation} weight={weight} value={value}`)
	return { ok = true, seedId = plot.seedId, mutation = mutation, weight = weight, value = value }
end

local function buy(s: Session, payload: unknown): any
	local seed = if type(payload) == "string" then Seeds.get(payload) else nil
	if not seed then
		return fail("unknown seed")
	end
	local d = data(s)
	if d.coins < seed.price then
		return fail("not enough coins")
	end
	d.coins -= seed.price
	d.seeds[seed.seedId] = (d.seeds[seed.seedId] or 0) + 1
	advanceTutorial(s, "buy")
	push(s)
	return { ok = true, seedId = seed.seedId, price = seed.price }
end

local function sellAll(s: Session): any
	if Npcs.distanceTo(s.player, "market") > Npcs.SellRange then
		return fail("walk to the Market to sell")
	end
	local d = data(s)
	if #d.fruits == 0 then
		return fail("no fruit to sell")
	end
	local total = 0
	for _, fruit in d.fruits do
		total += Economy.fruitValue(fruit.seedId, fruit.mutation, fruit.weight)
	end
	local count = #d.fruits
	d.fruits = {}
	d.coins += total
	advanceTutorial(s, "sell")
	push(s)
	return { ok = true, total = total, count = count }
end

local function setLatency(s: Session, payload: unknown): any
	if type(payload) ~= "number" or payload ~= payload then
		return fail("bad value")
	end
	data(s).settings.latencyMs =
		math.round(math.clamp(payload, PlayerData.LatencyRange.min, PlayerData.LatencyRange.max))
	return { ok = true }
end

local function buyEgg(s: Session): any
	local d = data(s)
	if d.coins < Spirits.EggPrice then
		return fail("not enough coins")
	end
	d.coins -= Spirits.EggPrice
	d.eggs += 1
	push(s)
	return { ok = true, price = Spirits.EggPrice }
end

local function hatch(s: Session): any
	local d = data(s)
	if d.eggs < 1 then
		return fail("you have no egg")
	end
	if #d.spirits >= Spirits.MaxOwned then
		return fail("too many spirits")
	end
	d.eggs -= 1
	local kind = Spirits.hatch(math.random)
	local id = HttpService:GenerateGUID(false)
	table.insert(d.spirits, { id = id, kind = kind })
	push(s)
	print(`[Garden] {s.player.Name}: hatched {kind}`)
	return { ok = true, kind = kind, id = id }
end

-- Equips the spirit with this id, or unequips when `payload` is nil / the one already equipped.
local function equip(s: Session, payload: unknown): any
	local d = data(s)
	if payload == nil or payload == d.equippedSpirit then
		d.equippedSpirit = nil
	else
		local found = false
		for _, spirit in d.spirits do
			if spirit.id == payload then
				found = true
			end
		end
		if not found then
			return fail("unknown spirit")
		end
		d.equippedSpirit = payload :: string
		s.nextAutoCare = os.time() + 5 -- first tend shortly after equipping
	end
	refresh(s)
	push(s)
	return { ok = true }
end

-- Called every second: an equipped spirit tends a growing plant on its own timer.
local function autoCare(s: Session, now: number)
	local def = equippedSpiritDef(s)
	local plot = plotOf(s)
	if not def or not plot or now < s.nextAutoCare then
		return
	end
	s.nextAutoCare = now + def.autoCareSeconds
	if Growth.stageFor(fractionOf(plot, now)) == "Fruit" then
		return
	end
	plot.careGauge += def.autoCarePoints
	refresh(s)
	push(s)
end

local function skipTutorial(s: Session): any
	data(s).tutorialStep = Tutorial.Done
	push(s)
	return { ok = true }
end

-- Studio only: wipes the saved data of the calling player so the tutorial can be replayed.
local function devReset(s: Session): any
	if not RunService:IsStudio() then
		return fail("not available")
	end
	s.store.data = PlayerData.new()
	s.pending = nil
	refresh(s)
	push(s)
	print(`[Garden] {s.player.Name}: data reset (Studio)`)
	return { ok = true }
end

-- Studio only: gives coins so the shop, eggs and trading can be tried without waiting.
local function devGrant(s: Session, payload: unknown): any
	if not RunService:IsStudio() then
		return fail("not available")
	end
	local amount = if type(payload) == "number" then math.clamp(payload, 0, 100000) else 500
	data(s).coins += math.floor(amount)
	push(s)
	return { ok = true }
end

-- ---------------------------------------------------------------------------------------------

local function createSession(player: Player, container: Instance): Session?
	local store = PlayerStore.load(player, function(message)
		player:Kick(message)
	end)
	if player.Parent == nil then
		PlayerStore.save(store, true) -- left while loading: release the lock
		return nil
	end
	local slot = freeSlot()
	local soil, plantPart, prompt = buildPlotParts(player, slot, container)
	local s: Session = {
		player = player,
		slot = slot,
		store = store,
		soil = soil,
		plant = plantPart,
		prompt = prompt,
		pending = nil,
		nextAutoCare = 0,
	}
	sessions[player] = s
	refresh(s)
	push(s)
	if not store.persistent then
		print(`[Garden] {player.Name}: progress will NOT be saved (DataStore unavailable)`)
	end
	return s
end

function Garden.start()
	local container = Instance.new("Folder")
	container.Name = "Garden"
	container.Parent = Workspace

	Npcs.start(container)

	Trading.start({
		dataOf = function(player: Player): PlayerData.Data?
			local s = sessions[player]
			return if s then data(s) else nil
		end,
		persistent = function(player: Player): boolean
			local s = sessions[player]
			return s ~= nil and s.store.persistent
		end,
		push = function(player: Player)
			local s = sessions[player]
			if s then
				push(s)
			end
		end,
	})

	updateEvent = Instance.new("RemoteEvent")
	updateEvent.Name = "GardenUpdate"
	updateEvent.Parent = ReplicatedStorage

	local tendRemote = Instance.new("RemoteFunction")
	tendRemote.Name = "Tend"
	tendRemote.Parent = ReplicatedStorage
	tendRemote.OnServerInvoke = function(player: Player, action: unknown, payload: unknown): any
		local s = sessions[player]
		if not s then
			return fail("not ready")
		end
		if action == "begin" then
			return tendBegin(s, payload)
		elseif action == "submit" then
			return tendSubmit(s, payload)
		end
		return nil
	end

	local gardenRemote = Instance.new("RemoteFunction")
	gardenRemote.Name = "Garden"
	gardenRemote.Parent = ReplicatedStorage
	gardenRemote.OnServerInvoke = function(player: Player, action: unknown, payload: unknown): any
		local s = sessions[player]
		if not s then
			return fail("not ready")
		end
		if action == "state" then
			return { ok = true, state = snapshot(s) }
		elseif action == "plant" then
			return plant(s, payload)
		elseif action == "harvest" then
			return harvest(s)
		elseif action == "buy" then
			return buy(s, payload)
		elseif action == "sellAll" then
			return sellAll(s)
		elseif action == "setLatency" then
			return setLatency(s, payload)
		elseif action == "buyEgg" then
			return buyEgg(s)
		elseif action == "hatch" then
			return hatch(s)
		elseif action == "equip" then
			return equip(s, payload)
		elseif action == "skipTutorial" then
			return skipTutorial(s)
		elseif action == "devReset" then
			return devReset(s)
		elseif action == "devGrant" then
			return devGrant(s, payload)
		end
		return nil
	end

	local function onPlayerAdded(player: Player)
		if sessions[player] == nil then
			createSession(player, container)
		end
	end
	Players.PlayerAdded:Connect(onPlayerAdded)
	for _, player in Players:GetPlayers() do
		task.spawn(onPlayerAdded, player)
	end

	Players.PlayerRemoving:Connect(function(player)
		local s = sessions[player]
		sessions[player] = nil
		if s then
			PlayerStore.save(s.store, true)
			s.soil:Destroy()
		end
	end)

	-- Server shutting down: save everyone and release their locks (Studio waits for this too).
	game:BindToClose(function()
		local remaining = 0
		for player, s in sessions do
			sessions[player] = nil
			remaining += 1
			task.spawn(function()
				PlayerStore.save(s.store, true)
				remaining -= 1
			end)
		end
		local deadline = os.clock() + 25
		while remaining > 0 and os.clock() < deadline do
			task.wait(0.1)
		end
	end)

	-- Plants keep growing with time, so redraw them once a second; autosave every minute.
	task.spawn(function()
		local sinceSave = 0
		while true do
			task.wait(1)
			sinceSave += 1
			local now = os.time()
			for _, s in sessions do
				refresh(s)
				autoCare(s, now)
			end
			if sinceSave >= AUTOSAVE_SECONDS then
				sinceSave = 0
				for _, s in sessions do
					task.spawn(PlayerStore.save, s.store, false)
				end
			end
		end
	end)
end

return Garden
