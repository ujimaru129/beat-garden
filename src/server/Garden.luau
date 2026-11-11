--!strict
-- Garden: one plot per player with a plant that grows from time and from tending, plus the
-- economy around it (plant, harvest with a mutation roll, buy seeds, sell fruit) and saving.
--
-- Remotes (both RemoteFunctions, every answer is { ok, ... } and the server decides every number):
--   Tend    "begin", difficulty | "submit", summary      -- the rhythm run
--   Garden  "state" | "plant", seedId | "harvest" | "buy", seedId | "sellAll" | "setLatency", ms
-- After every change the server pushes a snapshot to that player with the GardenUpdate event.

local HttpService = game:GetService("HttpService")
local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Difficulty = require(ReplicatedStorage.Shared.Difficulty)
local Collection = require(ReplicatedStorage.Shared.Garden.Collection)
local Economy = require(ReplicatedStorage.Shared.Garden.Economy)
local Genres = require(ReplicatedStorage.Shared.Garden.Genres)
local Growth = require(ReplicatedStorage.Shared.Garden.Growth)
local Mutations = require(ReplicatedStorage.Shared.Garden.Mutations)
local Npcs = require(script.Parent.Npcs)
local Park = require(ReplicatedStorage.Shared.Garden.Park)
local ParkBuilder = require(script.Parent.ParkBuilder)
local Palette = require(ReplicatedStorage.Shared.Palette)
local PlayerData = require(ReplicatedStorage.Shared.Data.PlayerData)
local PlayerStore = require(script.Parent.PlayerStore)
local RhythmEngine = require(ReplicatedStorage.Shared.RhythmEngine)
local Seeds = require(ReplicatedStorage.Shared.Garden.Seeds)
local Plots = require(ReplicatedStorage.Shared.Garden.Plots)
local Progression = require(ReplicatedStorage.Shared.Garden.Progression)
local Rush = require(ReplicatedStorage.Shared.Garden.Rush)
local Shop = require(ReplicatedStorage.Shared.Garden.Shop)
local Spirits = require(ReplicatedStorage.Shared.Garden.Spirits)
local Leaderboard = require(ReplicatedStorage.Shared.Garden.Leaderboard)
local Leaderboards = require(script.Parent.Leaderboards)
local PlantLook = require(script.Parent.PlantLook)
local Products = require(ReplicatedStorage.Shared.Garden.Products)
local Tips = require(ReplicatedStorage.Shared.Garden.Tips)
local Trading = require(script.Parent.Trading)
local Songs = require(ReplicatedStorage.Shared.Songs)
local Rank = require(ReplicatedStorage.Shared.Rank)
local Tutorial = require(ReplicatedStorage.Shared.Garden.Tutorial)

local Garden = {}

-- The spawn pad is 12 studs wide and players appear anywhere on it, so the prompt must reach from the
-- far corner. The server allows some extra distance on top for lag.
local PROMPT_RANGE = 20
local TEND_RANGE = 32
local AUTOSAVE_SECONDS = 60

-- Short cooldown in Studio so it can be tried repeatedly.
local COOLDOWN_SECONDS = if RunService:IsStudio() then 10 else Growth.TendCooldownSeconds

-- Plants are big, and they get bigger with the seed's mastery: 5 stars is 1.5x. A fully mastered fruit is about as
-- wide as the plot spacing (13 studs), so neighbours just touch.
local PLANT_SCALE = 1.65
local PLANT_SCALE_PER_STAR = 0.1

type Pending = {
	segment: RhythmEngine.Segment,
	startedAt: number,
	difficulty: Difficulty.Name,
	songName: string,
	favorite: boolean, -- the song's genre is the planted seed's favourite
	plotKey: string, -- the plot being tended
}

-- The parts of one plot: the soil (carries the attributes the client reads), the plant and the prompt.
type Node = {
	soil: Part,
	plant: Part,
	prompt: ProximityPrompt,
	decor: { BasePart }, -- the frame, posts and lights of the plot (fancier with the plot number)
}

type Session = {
	player: Player,
	slot: number,
	store: PlayerStore.Session,
	nodes: { [string]: Node }, -- plot key -> parts (all of Plots.Max, locked ones included)
	hasPass: boolean, -- owns the Plot Pass game pass
	hasDoubleGrowth: boolean, -- owns the Double Growth game pass
	pending: Pending?,
	nextAutoCare: number, -- unix seconds: when the equipped spirit tends next
}

local sessions: { [Player]: Session } = {}
local updateEvent: RemoteEvent
local parkContainer: Instance -- where the park attractions are built (set in Garden.start)

local function data(s: Session): PlayerData.Data
	return s.store.data
end

-- The shop's personal restock shift: valid only while the shop slot it was bought in is still the current one.
local function restockShift(d: PlayerData.Data, now: number): number
	return if d.restockSlot == Shop.slotOf(now) then d.restockShift else 0
end

local function plotOf(s: Session, key: string): Growth.Plot?
	return data(s).plots[key]
end

local function hasAnyPlant(s: Session): boolean
	return next(data(s).plots) ~= nil
end

-- Can the player use plot number `index`? Coin plots once bought, pass plots with the game pass.
local function isOpen(s: Session, index: number): boolean
	if Plots.isPass(index) then
		return s.hasPass
	end
	return index <= data(s).plotCount
end

-- A plot key from a request: valid and open to this player. Otherwise nil.
local function ownedKey(s: Session, key: unknown): string?
	local index = Plots.indexOf(key)
	if index and isOpen(s, index) then
		return key :: string
	end
	return nil
end

local function seedOf(plot: Growth.Plot): Seeds.Seed
	return Seeds.get(plot.seedId) :: Seeds.Seed -- sanitize() guarantees the seed exists
end

-- Seconds this plant needs: the seed's time, shortened by its mastery stars (fixed when planted) and by the
-- Double Growth game pass.
local function growSecondsOf(s: Session, plot: Growth.Plot): number
	return seedOf(plot).growSeconds * (plot.growMult or 1) / (if s.hasDoubleGrowth then Products.GrowSpeedMult else 1)
end

local function fractionOf(s: Session, plot: Growth.Plot, now: number): number
	return Growth.fraction(plot, growSecondsOf(s, plot), now)
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

local function freshnessOf(s: Session, plot: Growth.Plot, now: number): number
	local def = equippedSpiritDef(s)
	return Growth.freshness(plot, growSecondsOf(s, plot), now, if def then def.freshMult else nil)
end

-- The mutation is rolled when the fruit ripens (spec), so it can be seen on the plant before it is harvested.
-- The chance uses the care of the whole growth, the equipped spirit, the seed's mastery and a running BPM Rush.
local function ensureRolled(s: Session, plot: Growth.Plot)
	if plot.rolled then
		return
	end
	local spiritDef = equippedSpiritDef(s)
	local stars = Progression.starsFor(data(s).mastery[plot.seedId] or 0)
	local chanceMult = plot.mutationMult
		* (if spiritDef then spiritDef.mutationMult else 1)
		* Progression.mutationMult(stars)
		* Rush.boost(seedOf(plot).favoriteGenre, os.time())
	plot.mutation = Mutations.roll(plot.bestPerfectStreak, chanceMult, math.random)
	plot.rolled = true
end

local function advanceTutorial(s: Session, event: Tutorial.Event)
	local d = data(s)
	d.tutorialStep = Tutorial.advance(d.tutorialStep, event)
end

local cachedSpawn: Vector3? = nil
local function spawnPosition(): Vector3
	if cachedSpawn then
		return cachedSpawn
	end
	local spawn = Workspace:FindFirstChildWhichIsA("SpawnLocation", true)
	if spawn then
		cachedSpawn = spawn.Position
		return spawn.Position
	end
	return Vector3.zero
end

local function groundY(x: number, z: number): number
	local hit = Workspace:Raycast(Vector3.new(x, 200, z), Vector3.new(0, -400, 0))
	return if hit then hit.Position.Y else 0
end

-- What the park goals measure.
local function parkStats(d: PlayerData.Data): Park.Stats
	local found = Collection.progress(d.collection)
	return {
		harvests = d.stats.harvests,
		runs = d.stats.tends,
		maxCombo = d.stats.maxCombo,
		book = found,
		spirits = #d.spirits,
		level = Progression.levelFor(d.xp).level,
		pats = d.stats.pats,
		bond = (function()
			local best = 0
			for _, spirit in d.spirits do
				best = math.max(best, Spirits.bondLevel(spirit.bond))
			end
			return best
		end)(),
	}
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
	local plotInfo = {}
	for key, plot in d.plots do
		local fraction = fractionOf(s, plot, now)
		plotInfo[key] = { seedId = plot.seedId, fraction = fraction, stage = Growth.stageFor(fraction) }
	end
	return {
		coins = d.coins,
		seeds = table.clone(d.seeds),
		fruits = fruits,
		plots = plotInfo,
		plotCount = d.plotCount,
		hasPlotPass = s.hasPass,
		hasDoubleGrowth = s.hasDoubleGrowth,
		instantCredits = d.instantCredits,
		restockSlot = d.restockSlot,
		restockShift = d.restockShift,
		sprinklerLeft = math.max(0, d.sprinklerUntil - now),
		settings = { latencyMs = d.settings.latencyMs },
		persistent = s.store.persistent,
		tutorialStep = d.tutorialStep,
		eggs = d.eggs,
		spirits = table.clone(d.spirits),
		equippedSpirit = d.equippedSpirit,
		collection = table.clone(d.collection),
		sellMult = (function()
			local def = equippedSpiritDef(s)
			return if def then def.sellMult else 1
		end)(),
		xp = d.xp,
		level = Progression.levelFor(d.xp),
		mastery = table.clone(d.mastery),
		park = {
			boxes = d.park.boxes,
			items = table.clone(d.park.items),
			placed = table.clone(d.park.placed),
			claimed = table.clone(d.park.claimed),
			stats = parkStats(d),
		},
	}
end

-- Never leave a player with nothing to play: no plant, no seeds, no fruit and too few coins for the
-- cheapest seed would be a dead end, so the starter seed is given again.
local function rescueIfStuck(s: Session)
	local d = data(s)
	if hasAnyPlant(s) or next(d.seeds) ~= nil or #d.fruits > 0 then
		return
	end
	local cheapest = math.huge
	for _, seed in Seeds.List do
		cheapest = math.min(cheapest, seed.price)
	end
	if d.coins < cheapest then
		d.seeds[Seeds.StarterSeedId] = 1
		print(`[Garden] {s.player.Name}: stuck without seeds or coins, gave a starter seed`)
	end
end

-- Pays the boxes of goals that were reached and draws what stands on the lots (only rebuilds when it changed).
local function syncPark(s: Session)
	local d = data(s)
	local stats = parkStats(d)
	Park.claimGoals(d.park, stats)
	ParkBuilder.sync(parkContainer, s.player, s.slot, d.park, stats.level, spawnPosition(), groundY)
end

-- The pets that roam this player's territory, for every client to draw: up to Spirits.MaxPets spirits that are not
-- the equipped one (that one stays beside the plant), the most petted first. "id:kind:bond,id:kind:bond".
local function syncPets(s: Session)
	local d = data(s)
	local list: { { spirit: PlayerData.SpiritInstance, order: number } } = {}
	for index, spirit in d.spirits do
		if spirit.id ~= d.equippedSpirit then
			table.insert(list, { spirit = spirit, order = index })
		end
	end
	table.sort(list, function(a, b)
		if a.spirit.bond ~= b.spirit.bond then
			return a.spirit.bond > b.spirit.bond
		end
		return a.order < b.order
	end)
	local parts: { string } = {}
	for i = 1, math.min(#list, Spirits.MaxPets) do
		local spirit = list[i].spirit
		table.insert(parts, `{spirit.id}:{spirit.kind}:{spirit.bond}`)
	end
	s.player:SetAttribute("Pets", table.concat(parts, ","))
end

local function push(s: Session)
	rescueIfStuck(s)
	syncPark(s)
	syncPets(s)
	updateEvent:FireClient(s.player, snapshot(s))
end

-- The extra parts of a plant (stem, leaves, petals ...) live in a folder under the soil.
local function lookFolder(soil: Part): Folder
	local folder = soil:FindFirstChild("PlantParts")
	if folder and folder:IsA("Folder") then
		return folder
	end
	local made = Instance.new("Folder")
	made.Name = "PlantParts"
	made.Parent = soil
	return made
end

-- Redraws one plot's plant and prompt from the data.
local function refreshPlot(s: Session, key: string, spiritKind: string?)
	local node = s.nodes[key]
	local index = Plots.indexOf(key) :: number
	local soil, plantPart, prompt = node.soil, node.plant, node.prompt
	soil:SetAttribute("SpiritKind", spiritKind)
	local open = isOpen(s, index)
	for _, part in node.decor do
		part.Transparency = if open then (part:GetAttribute("BaseTransparency") :: number? or 0) else 0.75
	end
	if not open then
		-- not bought yet: a dim, see-through pad with an Unlock prompt
		soil.Transparency = 0.6
		plantPart.Transparency = 1
		PlantLook.clear(lookFolder(soil))
		soil:SetAttribute("Stage", "Locked")
		soil:SetAttribute("Fraction", 0)
		local nextIndex = data(s).plotCount + 1
		soil:SetAttribute("NextUnlock", nextIndex)
		if Plots.isPass(index) then
			soil:SetAttribute("Pass", true)
			soil:SetAttribute("Price", nil)
			prompt.ActionText = "Plot Pass"
			prompt.ObjectText = `Premium plot {index}`
		elseif index == nextIndex then
			soil:SetAttribute("Pass", nil)
			soil:SetAttribute("Price", Plots.Price[index])
			prompt.ActionText = "Unlock"
			prompt.ObjectText = `Plot {index}  -  {Plots.Price[index]} coins`
		else
			soil:SetAttribute("Pass", nil)
			soil:SetAttribute("Price", nil)
			prompt.ActionText = "Locked"
			prompt.ObjectText = `Buy plot {nextIndex} first`
		end
		return
	end
	soil:SetAttribute("Pass", nil)
	soil:SetAttribute("NextUnlock", nil)
	soil.Transparency = 0
	prompt.ObjectText = `{s.player.DisplayName}'s plant`
	local plot = plotOf(s, key)
	if not plot then
		plantPart.Transparency = 1
		PlantLook.clear(lookFolder(soil))
		soil:SetAttribute("Stage", "Empty")
		soil:SetAttribute("Fraction", 0)
		prompt.ActionText = "Plant"
		return
	end
	local fraction = fractionOf(s, plot, os.time())
	local stage = Growth.stageFor(fraction)
	if stage == "Fruit" then
		ensureRolled(s, plot)
	end
	local shownMutation = if stage == "Fruit" then plot.mutation else nil
	PlantLook.apply(
		plantPart,
		lookFolder(soil),
		soil.Position + Vector3.new(0, soil.Size.Y / 2, 0),
		plot.seedId,
		stage,
		freshnessOf(s, plot, os.time()),
		shownMutation,
		Progression.starsFor(data(s).mastery[plot.seedId] or 0),
		PLANT_SCALE * (1 + PLANT_SCALE_PER_STAR * Progression.starsFor(data(s).mastery[plot.seedId] or 0))
	)
	soil:SetAttribute("Stage", stage)
	soil:SetAttribute("Fraction", fraction)
	soil:SetAttribute("Mutation", shownMutation)
	local harvestText = if freshnessOf(s, plot, os.time()) < 1 then "Harvest (overripe)" else "Harvest"
	if shownMutation then
		harvestText ..= ` - {Mutations.displayName(shownMutation)}!`
	end
	prompt.ActionText = if stage == "Fruit" then harvestText else "Tend"
end

-- Redraws every plot of the player.
local function refresh(s: Session)
	local spiritDef = equippedSpiritDef(s)
	local kind = if spiritDef then spiritDef.kind else nil
	-- One spirit per player: it stands at the first planted plot (or the first plot when nothing grows).
	local home = "1"
	local bestIndex = math.huge
	for key in data(s).plots do
		local index = Plots.indexOf(key)
		if index and index < bestIndex then
			bestIndex = index
			home = key
		end
	end
	for key in s.nodes do
		refreshPlot(s, key, if key == home then kind else nil)
	end
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

local TIER_FRAME: { Color3 } = {
	Color3.fromHex("#FFC4DD"), -- 1 candy pink
	Color3.fromHex("#9AD8FF"), -- 2 sky
	Color3.fromHex("#FF4FA3"), -- 3 neon pink (alternates with blue)
	Color3.fromHex("#B07CFF"), -- 4 neon violet
	Color3.fromHex("#FFD84D"), -- 5 gold
}
local NEON_CYCLE: { Color3 } = {
	Color3.fromHex("#FF4FA3"),
	Color3.fromHex("#3FC8FF"),
	Color3.fromHex("#3DFFB0"),
	Color3.fromHex("#FFE14D"),
}

-- The frame, corner posts and lights of a plot. The higher the plot number, the fancier: a candy frame, then
-- posts, then neon, then taller posts, then gold with sparkles (the pass plots).
local function buildDecor(soil: Part, index: number): { BasePart }
	local tier = Plots.tier(index)
	local parts: { BasePart } = {}
	local top = soil.Size.Y / 2
	local half = soil.Size.X / 2
	local function add(part: Part, localOffset: Vector3, glow: boolean?)
		part.Anchored = true
		part.CanCollide = false
		part.CanQuery = false
		part.CanTouch = false
		part.CastShadow = false
		part.CFrame = soil.CFrame * CFrame.new(localOffset)
		if glow then
			part:SetAttribute("PlotGlow", true) -- the client pulses these on the beat
		end
		part.Parent = soil
		table.insert(parts, part)
	end
	local frameColor = TIER_FRAME[tier]
	local neon = tier >= 3
	for _, side in { -1, 1 } do
		local bar = Instance.new("Part")
		bar.Name = "FrameX"
		bar.Size = Vector3.new(soil.Size.X + 0.4, 0.35, 0.4)
		bar.Color = if tier == 3 then NEON_CYCLE[(index + side) % 2 + 1] else frameColor
		bar.Material = if neon then Enum.Material.Neon else Enum.Material.SmoothPlastic
		add(bar, Vector3.new(0, top + 0.1, side * half))
		local bar2 = Instance.new("Part")
		bar2.Name = "FrameZ"
		bar2.Size = Vector3.new(0.4, 0.35, soil.Size.Z + 0.4)
		bar2.Color = bar.Color
		bar2.Material = bar.Material
		add(bar2, Vector3.new(side * half, top + 0.1, 0))
	end
	if tier >= 2 then
		local height = ({ 0, 1.4, 1.8, 2.3, 2.9 })[tier]
		local corner = 0
		for _, sx in { -1, 1 } do
			for _, sz in { -1, 1 } do
				corner += 1
				local post = Instance.new("Part")
				post.Name = "Post"
				post.Shape = Enum.PartType.Cylinder
				post.Size = Vector3.new(height, 0.4, 0.4)
				post.Color = if tier == 2 then Color3.new(1, 1, 1) else Color3.fromHex("#2A1B5C")
				post.Material = Enum.Material.SmoothPlastic
				post.CFrame = soil.CFrame
					* CFrame.new(sx * half, top + height / 2, sz * half)
					* CFrame.Angles(0, 0, math.pi / 2)
				post.Anchored = true
				post.CanCollide = false
				post.CanQuery = false
				post.CanTouch = false
				post.CastShadow = false
				post.Parent = soil
				table.insert(parts, post)
				local ball = Instance.new("Part")
				ball.Name = "PostLight"
				ball.Shape = Enum.PartType.Ball
				ball.Size = Vector3.new(0.9, 0.9, 0.9)
				ball.Color = if tier == 2
					then Color3.fromHex("#FFF3A8")
					elseif tier == 5 then NEON_CYCLE[corner]
					elseif tier == 4 then Color3.fromHex("#FFE14D")
					else NEON_CYCLE[(corner + index) % 4 + 1]
				ball.Material = if tier >= 3 then Enum.Material.Neon else Enum.Material.SmoothPlastic
				add(ball, Vector3.new(sx * half, top + height + 0.3, sz * half), tier >= 3)
				if tier == 5 then
					local sparkles = Instance.new("ParticleEmitter")
					sparkles.Rate = 4
					sparkles.Lifetime = NumberRange.new(1.2, 2)
					sparkles.Speed = NumberRange.new(0.5, 1.5)
					sparkles.SpreadAngle = Vector2.new(180, 180)
					sparkles.LightEmission = 1
					sparkles.Size = NumberSequence.new({
						NumberSequenceKeypoint.new(0, 0.5),
						NumberSequenceKeypoint.new(1, 0),
					})
					sparkles.Color = ColorSequence.new(Color3.fromHex("#FFE9A0"))
					sparkles.Parent = ball
				end
			end
		end
	end
	return parts
end

local function buildPlotNode(player: Player, slot: number, index: number, container: Instance): Node
	local base = spawnPosition()
	local x, z, angle = Plots.place(base.X, base.Z, slot, index)
	local soil = Instance.new("Part")
	soil.Name = `Plot_{player.UserId}_{index}`
	soil.Anchored = true
	soil.Size = Vector3.new(10, 0.6, 10)
	-- Turned so that the top of a SurfaceGui (the marks painted on the plot) points away from the hub: the text
	-- reads upright for a player walking in from the hub.
	soil.CFrame = CFrame.new(x, groundY(x, z) + 0.3, z) * CFrame.Angles(0, -angle - math.pi, 0)
	soil.Color = Palette.Base.YoruGround
	soil.Material = Enum.Material.SmoothPlastic
	soil:SetAttribute("OwnerUserId", player.UserId)
	soil:SetAttribute("PlotKey", Plots.keyOf(index))
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

	return { soil = soil, plant = plant, prompt = prompt, decor = buildDecor(soil, index) }
end

-- Your territory, easy to find: a name sign at its entrance for everyone, and (only on the owner's screen, see
-- PlotVisuals) a tall light beam over it and a glowing path of tiles leading from the hub.
local function buildTerritoryMarker(player: Player, slot: number, container: Instance): CFrame
	local base = spawnPosition()
	local color = Color3.fromHSV(((slot - 1) % Plots.Slots) / Plots.Slots, 0.65, 1)
	local folder = Instance.new("Folder")
	folder.Name = `Territory_{player.UserId}`
	folder:SetAttribute("OwnerUserId", player.UserId)
	folder.Parent = container

	local angle = ((slot - 1) % Plots.Slots) / Plots.Slots * math.pi * 2
	-- A point on the territory's centre line: `radial` studs from the hub centre, `tangent` to the side.
	local function placeAt(radial: number, tangent: number, y: number): Vector3
		local px = base.X + math.cos(angle) * radial - math.sin(angle) * tangent
		local pz = base.Z + math.sin(angle) * radial + math.cos(angle) * tangent
		return Vector3.new(px, groundY(px, pz) + y, pz)
	end
	local function part(props: { [string]: any }): Part
		local p = Instance.new("Part")
		p.Anchored = true
		p.CanCollide = false
		p.CanQuery = false
		p.CanTouch = false
		p.CastShadow = false
		for k, v in props do
			(p :: any)[k] = v
		end
		p.Parent = folder
		return p
	end

	-- Owner-only beacon over the middle of the territory.
	local middle = placeAt(Plots.RingRadius + Plots.Spacing, 0, 0)
	part({
		Name = "Beacon",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(90, 3, 3),
		CFrame = CFrame.new(middle + Vector3.new(0, 45, 0)) * CFrame.Angles(0, 0, math.pi / 2),
		Material = Enum.Material.Neon,
		Color = color,
		Transparency = 0.55,
	}):SetAttribute("OwnerOnly", true)
	-- Owner-only path of glowing tiles from the hub to the entrance.
	local r = 36
	while r < Plots.RingRadius - 12 do
		local at = placeAt(r, 0, 0.2)
		local tile = part({
			Name = "PathTile",
			Size = Vector3.new(4, 0.2, 4),
			CFrame = CFrame.new(at) * CFrame.Angles(0, -angle + math.pi / 4, 0),
			Material = Enum.Material.Neon,
			Color = color,
			Transparency = 0.25,
		})
		tile:SetAttribute("OwnerOnly", true)
		r += 6
	end
	return CFrame.lookAt(placeAt(Plots.RingRadius - 14, 0, 4), placeAt(Plots.RingRadius, 0, 4))
end

local function distanceToPlot(s: Session, key: string): number
	local character = s.player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not (root and root:IsA("BasePart")) then
		return math.huge
	end
	return (root.Position - s.nodes[key].soil.Position).Magnitude
end

local function fail(reason: string): any
	return { ok = false, reason = reason }
end

-- ---------------------------------------------------------------------------------------------
-- Tend (the rhythm run)

local function tendBegin(s: Session, payload: unknown): any
	-- payload = { difficulty = "Easy" | "Normal" | "Hard", songId = "...", plotKey = "1" }
	if type(payload) ~= "table" then
		return fail("bad request")
	end
	local request = payload :: { difficulty: unknown, songId: unknown, plotKey: unknown }
	if type(request.difficulty) ~= "string" or table.find(Difficulty.Names, request.difficulty) == nil then
		return fail("bad difficulty")
	end
	local difficulty: Difficulty.Name = request.difficulty :: any
	if type(request.songId) ~= "string" or Songs.get(request.songId) == nil then
		return fail("unknown song")
	end
	local plotKey = ownedKey(s, request.plotKey)
	if not plotKey then
		return fail("unknown plot")
	end
	local plot = plotOf(s, plotKey)
	if not plot then
		return fail("nothing planted")
	end
	if distanceToPlot(s, plotKey) > TEND_RANGE then
		return fail("too far from the plant")
	end
	local now = os.time()
	if Growth.stageFor(fractionOf(s, plot, now)) == "Fruit" then
		return fail("fully grown")
	end
	local wait = Growth.cooldownLeft(plot, now, COOLDOWN_SECONDS)
	if wait > 0 then
		return { ok = false, reason = `rest a little more ({wait}s)`, cooldown = wait }
	end

	-- The song the player chose; the chart is the whole short edit at the chosen difficulty.
	local picked = Songs.pick(request.songId :: string, difficulty)
	if not picked then
		return fail("unknown song")
	end
	s.pending = {
		segment = picked.segment,
		startedAt = os.clock(),
		difficulty = difficulty,
		songName = picked.name,
		favorite = seedOf(plot).favoriteGenre == picked.genre,
		plotKey = plotKey,
	}
	return {
		ok = true,
		segment = picked.segment,
		bpm = picked.bpm,
		beatsMs = picked.beatsMs,
		songName = picked.name,
		audioAssetId = picked.audioAssetId,
		offsetMs = picked.offsetMs,
		favorite = (s.pending :: Pending).favorite,
		difficulty = difficulty,
	}
end

local function tendSubmit(s: Session, payload: unknown): any
	local pending = s.pending
	s.pending = nil
	if not pending then
		return fail("no run in progress")
	end
	local plot = plotOf(s, pending.plotKey)
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
	local tendSpirit = equippedSpiritDef(s)
	if tendSpirit then
		points = math.round(points * tendSpirit.tendMult)
	end
	local mutationMult = Difficulty.MutationChanceMultiplier[pending.difficulty]
	if pending.favorite then
		-- the plant's favourite genre: grows faster and mutates more easily
		points = math.round(points * Genres.GrowthBonus)
		mutationMult *= Genres.MutationBonus
	end
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
	d.stats.maxCombo = math.max(d.stats.maxCombo, tally.maxCombo)
	local tendProgress = { xp = d.xp, mastery = d.mastery }
	local tendLevelUp, tendUnlocked, tendLevel = Progression.applyTend(tendProgress, tally.accuracy)
	d.xp = tendProgress.xp
	refresh(s)
	push(s)

	local fraction = fractionOf(s, plot, now)
	print(`[Garden] {s.player.Name}: {pending.difficulty} acc {math.floor(tally.accuracy * 100)}% -> +{points} growth`)
	return {
		ok = true,
		points = points,
		difficulty = pending.difficulty,
		stage = Growth.stageFor(fraction),
		fraction = fraction,
		cooldown = COOLDOWN_SECONDS,
		songName = pending.songName,
		favorite = pending.favorite,
		rank = Rank.forAccuracy(tally.accuracy),
		score = Rank.score(tally.accuracy),
		counts = tally.counts,
		maxCombo = tally.maxCombo,
		accuracy = tally.accuracy,
		xpGained = Progression.tendXp(tally.accuracy),
		level = tendLevel,
		leveledUp = tendLevelUp,
		unlocked = tendUnlocked,
	}
end

-- ---------------------------------------------------------------------------------------------
-- Garden actions

local function plant(s: Session, payload: unknown): any
	-- payload = { seedId = "...", plotKey = "1" }
	if type(payload) ~= "table" then
		return fail("bad request")
	end
	local request = payload :: { seedId: unknown, plotKey: unknown }
	local seedId = request.seedId
	if type(seedId) ~= "string" or Seeds.get(seedId) == nil then
		return fail("unknown seed")
	end
	local plotKey = ownedKey(s, request.plotKey)
	if not plotKey then
		return fail("unknown plot")
	end
	if plotOf(s, plotKey) then
		return fail("the plot is not empty")
	end
	if distanceToPlot(s, plotKey) > TEND_RANGE then
		return fail("too far from the plot")
	end
	local d = data(s)
	local count = d.seeds[seedId] or 0
	if count < 1 then
		return fail("you have no such seed")
	end
	if count > 1 then
		d.seeds[seedId] = count - 1
	else
		d.seeds[seedId] = nil
	end
	d.plots[plotKey] =
		Growth.newPlot(seedId, os.time(), Progression.growTimeMult(Progression.starsFor(d.mastery[seedId] or 0)))
	advanceTutorial(s, "plant")
	refresh(s)
	push(s)
	return { ok = true, seedId = seedId }
end

local function harvest(s: Session, payload: unknown): any
	local plotKey = ownedKey(s, payload)
	if not plotKey then
		return fail("unknown plot")
	end
	local plot = plotOf(s, plotKey)
	if not plot then
		return fail("nothing planted")
	end
	if distanceToPlot(s, plotKey) > TEND_RANGE then
		return fail("too far from the plant")
	end
	if Growth.stageFor(fractionOf(s, plot, os.time())) ~= "Fruit" then
		return fail("not ready yet")
	end
	local d = data(s)
	if #d.fruits >= PlayerData.MaxFruits then
		return fail("your bag is full - sell some fruit")
	end

	ensureRolled(s, plot)
	local mutation = plot.mutation
	local freshness = freshnessOf(s, plot, os.time())
	local weight = math.max(0.1, math.round(Economy.rollWeight(math.random) * freshness * 100) / 100)
	table.insert(d.fruits, { seedId = plot.seedId, mutation = mutation, weight = weight })
	d.stats.harvests += 1
	-- The collection book: a first-time variant pays coins; a complete seed pays an egg.
	local discovery = Collection.discover(d.collection, plot.seedId, mutation)
	if discovery.isNew then
		local discoverySpirit = equippedSpiritDef(s)
		if discoverySpirit then
			discovery.coins = math.round(discovery.coins * discoverySpirit.discoveryMult)
		end
		d.coins += discovery.coins
		if discovery.completedSeed then
			d.eggs += Collection.CompletionEggs
		end
	end
	local progress =
		Progression.applyHarvest({ xp = d.xp, mastery = d.mastery }, plot.seedId, mutation, discovery.isNew)
	d.xp += progress.xpGained
	d.plots[plotKey] = nil
	advanceTutorial(s, "harvest")
	refresh(s)
	push(s)

	local value = Economy.fruitValue(plot.seedId, mutation, weight)
	print(`[Garden] {s.player.Name}: harvested {plot.seedId} mutation={mutation} weight={weight} value={value}`)
	return {
		ok = true,
		seedId = plot.seedId,
		mutation = mutation,
		weight = weight,
		value = value,
		discovery = discovery,
		completionEggs = if discovery.isNew and discovery.completedSeed then Collection.CompletionEggs else 0,
		xpGained = progress.xpGained,
		level = progress.level,
		leveledUp = progress.leveledUp,
		unlocked = progress.unlocked,
		stars = progress.stars,
		newStar = progress.newStar,
		harvests = progress.harvests,
		freshness = freshness,
	}
end

-- Buys the next plot. Plots are bought in order, so the key must be the one after the last owned.
local function unlockPlot(s: Session, payload: unknown): any
	local index = Plots.indexOf(payload)
	local d = data(s)
	if not index or Plots.isPass(index) or index ~= d.plotCount + 1 then
		return fail("that plot is not available")
	end
	local price = Plots.Price[index]
	if d.coins < price then
		return fail("not enough coins")
	end
	d.coins -= price
	d.plotCount = index
	refresh(s)
	push(s)
	print(`[Garden] {s.player.Name}: unlocked plot {index} for {price}`)
	return { ok = true, index = index, price = price }
end

local function buy(s: Session, payload: unknown): any
	local seed = if type(payload) == "string" then Seeds.get(payload) else nil
	if not seed then
		return fail("unknown seed")
	end
	if
		not Shop.inStock(
			seed.seedId,
			os.time(),
			Progression.levelFor(data(s).xp).level,
			restockShift(data(s), os.time())
		)
	then
		return fail("not in stock right now")
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
	local spirit = equippedSpiritDef(s)
	total = math.round(total * (if spirit then spirit.sellMult else 1))
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
	table.insert(d.spirits, { id = id, kind = kind, bond = 0 })
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

-- Called every second: an equipped spirit tends every growing plant on its own timer.
-- The Growth Sprinkler (a Robux product): while it works, every plant that is still growing gets extra growth seconds
-- each second. It is only called once a second, so the bonus is a whole number of seconds.
local function applySprinkler(s: Session, now: number)
	local d = data(s)
	if d.sprinklerUntil <= now then
		return
	end
	for _, plot in d.plots do
		if Growth.stageFor(fractionOf(s, plot, now)) ~= "Fruit" then
			plot.careGauge += Products.SprinklerGrowBonus
		end
	end
end

local function autoCare(s: Session, now: number)
	local def = equippedSpiritDef(s)
	if not def or now < s.nextAutoCare then
		return
	end
	s.nextAutoCare = now + def.autoCareSeconds
	local cared = false
	for _, plot in data(s).plots do
		if Growth.stageFor(fractionOf(s, plot, now)) ~= "Fruit" then
			plot.careGauge += def.autoCarePoints
			cared = true
		end
	end
	if cared then
		refresh(s)
		push(s)
	end
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

-- Studio only: switches the Plot Pass on and off so the premium plots can be tried.
local function devPlotPass(s: Session): any
	if not RunService:IsStudio() then
		return fail("not available")
	end
	s.hasPass = not s.hasPass
	print(`[Garden] {s.player.Name}: Plot Pass switched {if s.hasPass then "on" else "off"} (Studio)`)
	refresh(s)
	push(s)
	return { ok = true, hasPass = s.hasPass }
end

-- Studio only: moves every growing plant on to its next stage, so the looks can be checked without waiting.
local function devGrow(s: Session): any
	if not RunService:IsStudio() then
		return fail("not available")
	end
	local d = data(s)
	local now = os.time()
	local grown = 0
	for _, plot in d.plots do
		local total = growSecondsOf(s, plot)
		local fraction = fractionOf(s, plot, now)
		for _, stage in Growth.Stages do
			if stage.from > fraction + 1e-6 then
				plot.careGauge += stage.from * total - Growth.progressSeconds(plot, total, now) + 1
				grown += 1
				break
			end
		end
	end
	refresh(s)
	push(s)
	return { ok = grown > 0, reason = if grown == 0 then "nothing to grow" else nil, grown = grown }
end

-- A one-time tip: the first call for a key says it is new (and the client shows the tip); later calls do not.
local function tip(s: Session, payload: unknown): any
	if not Tips.isKey(payload) then
		return fail("unknown tip")
	end
	local d = data(s)
	local key = payload :: string
	if d.tips[key] then
		return { ok = true, new = false }
	end
	d.tips[key] = true
	return { ok = true, new = true }
end

-- Uses one paid Instant Grow on a plant: it ripens at once.
local function useInstantGrow(s: Session, payload: unknown): any
	local plotKey = ownedKey(s, payload)
	if not plotKey then
		return fail("unknown plot")
	end
	local plot = plotOf(s, plotKey)
	if not plot then
		return fail("nothing planted")
	end
	local d = data(s)
	if d.instantCredits < 1 then
		return fail("no Instant Grow to use")
	end
	if Growth.stageFor(fractionOf(s, plot, os.time())) == "Fruit" then
		return fail("already ripe")
	end
	d.instantCredits -= 1
	plot.careGauge = math.max(plot.careGauge, growSecondsOf(s, plot))
	refresh(s)
	push(s)
	print(`[Garden] {s.player.Name}: Instant Grow on plot {plotKey}`)
	return { ok = true }
end

-- Robux purchases (developer products). Roblox may call this again for the same purchase, so every purchase id is
-- remembered in the player's data and granted once. The data is saved before the purchase is confirmed.
local function processReceipt(info: { [string]: any }): Enum.ProductPurchaseDecision
	local player = Players:GetPlayerByUserId(info.PlayerId)
	local s = if player then sessions[player] else nil
	if not s then
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	local d = data(s)
	local receiptId = tostring(info.PurchaseId)
	if table.find(d.receipts, receiptId) then
		return Enum.ProductPurchaseDecision.PurchaseGranted
	end
	local kind = Products.kindOf(info.ProductId)
	if not kind then
		warn(`[Garden] receipt for an unknown product {info.ProductId}`)
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	local now = os.time()
	if kind == "InstantGrow" then
		d.instantCredits += 1
	elseif kind == "Restock" then
		d.restockShift = restockShift(d, now) + 1
		d.restockSlot = Shop.slotOf(now)
	elseif kind == "Sprinkler" then
		d.sprinklerUntil = math.max(d.sprinklerUntil, now) + Products.SprinklerSeconds
	end
	table.insert(d.receipts, receiptId)
	while #d.receipts > Products.MaxReceipts do
		table.remove(d.receipts, 1)
	end
	refresh(s)
	push(s)
	print(`[Garden] {s.player.Name}: bought {kind}`)
	if s.store.persistent and not PlayerStore.save(s.store, false) then
		return Enum.ProductPurchaseDecision.NotProcessedYet -- saved next time; the receipt id above stops a double grant
	end
	return Enum.ProductPurchaseDecision.PurchaseGranted
end

-- Studio only: jumps to the next garden level so the unlocked seeds can be tried.
local function devLevelUp(s: Session): any
	if not RunService:IsStudio() then
		return fail("not available")
	end
	local d = data(s)
	local level = Progression.levelFor(d.xp).level
	if level >= Progression.MaxLevel then
		return fail("already at the max level")
	end
	d.xp = Progression.xpToReach(level + 1)
	print(`[Garden] {s.player.Name}: garden level {level + 1} (Studio)`)
	push(s)
	return { ok = true, level = level + 1, unlocked = Progression.seedsUnlockedAt(level + 1) }
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

local lastPat: { [string]: number } = {} -- spirit id -> os.clock() of the last pat that counted

-- Petting a spirit: its bond grows a little (at most once per Spirits.PatCooldown seconds per spirit).
local function pat(s: Session, payload: unknown): any
	if type(payload) ~= "string" then
		return fail("bad request")
	end
	local d = data(s)
	for _, spirit in d.spirits do
		if spirit.id == payload then
			local now = os.clock()
			local level = Spirits.bondLevel(spirit.bond)
			if now - (lastPat[spirit.id] or -10) < Spirits.PatCooldown then
				return { ok = true, counted = false, bond = spirit.bond, level = level }
			end
			lastPat[spirit.id] = now
			spirit.bond = math.min(Spirits.MaxBond, spirit.bond + 1)
			d.stats.pats += 1
			push(s)
			local newLevel = Spirits.bondLevel(spirit.bond)
			return {
				ok = true,
				counted = true,
				bond = spirit.bond,
				level = newLevel,
				levelUp = newLevel > level,
				kind = spirit.kind,
			}
		end
	end
	return fail("unknown spirit")
end

-- Studio only: gives 3 gift boxes so the park can be tried without finishing the goals.
local function devBoxes(s: Session): any
	if not RunService:IsStudio() then
		return fail("not available")
	end
	data(s).park.boxes = math.min(Park.MaxBoxes, data(s).park.boxes + 3)
	push(s)
	return { ok = true }
end

-- ---------------------------------------------------------------------------------------------

-- Opens one gift box: the server picks the item, so nothing on the client can change what is inside.
local function parkOpen(s: Session): any
	local d = data(s)
	local key = Park.openBox(d.park, Random.new())
	if not key then
		return fail(if d.park.boxes > 0 then "nothing left to find" else "no gift box")
	end
	push(s)
	return { ok = true, key = key, boxes = d.park.boxes }
end

-- Puts an owned attraction on an open lot (or clears the lot when the key is nil).
local function parkPlace(s: Session, payload: unknown): any
	if type(payload) ~= "table" then
		return fail("bad request")
	end
	local d = data(s)
	local ok, reason = Park.place(d.park, (payload :: any).lot, (payload :: any).key, Progression.levelFor(d.xp).level)
	if not ok then
		return fail(reason or "bad request")
	end
	push(s)
	return { ok = true }
end

local function createSession(player: Player, container: Instance): Session?
	local store = PlayerStore.load(player, function(message)
		player:Kick(message)
	end)
	if player.Parent == nil then
		PlayerStore.save(store, true) -- left while loading: release the lock
		return nil
	end
	local slot = freeSlot()
	if slot > Plots.Slots then
		-- The island has a territory for Plots.Slots players. Set Max Players to the same number in Game Settings;
		-- this is only the safety net so that territories never overlap.
		PlayerStore.save(store, true) -- release the data lock
		player:Kick("This server is full. Please join another one.")
		return nil
	end
	local nodes: { [string]: Node } = {}
	for index = 1, Plots.Max do
		nodes[Plots.keyOf(index)] = buildPlotNode(player, slot, index, container)
	end
	local entrance = buildTerritoryMarker(player, slot, container)
	local s: Session = {
		player = player,
		slot = slot,
		store = store,
		nodes = nodes,
		hasPass = false,
		hasDoubleGrowth = false,
		pending = nil,
		nextAutoCare = 0,
	}
	sessions[player] = s
	-- Every spawn puts the player at the entrance of their own territory, facing the plots.
	local function toEntrance(character: Model)
		task.defer(function()
			if character.Parent then
				character:PivotTo(entrance + Vector3.new(0, 3, 0))
			end
		end)
	end
	player.CharacterAdded:Connect(toEntrance)
	if player.Character then
		toEntrance(player.Character)
	end
	-- The Plot Pass: owned game passes are checked once at join (and again when one is bought).
	if Plots.PassId > 0 then
		local ok, owns = pcall(function()
			return MarketplaceService:UserOwnsGamePassAsync(player.UserId, Plots.PassId)
		end)
		s.hasPass = ok and owns == true
		print(`[Garden] {player.Name}: Plot Pass owned = {s.hasPass}`)
	end
	if Products.DoubleGrowthPassId > 0 then
		local ok, owns = pcall(function()
			return MarketplaceService:UserOwnsGamePassAsync(player.UserId, Products.DoubleGrowthPassId)
		end)
		s.hasDoubleGrowth = ok and owns == true
	end
	refresh(s)
	push(s)
	if not store.persistent then
		print(`[Garden] {player.Name}: progress will NOT be saved (DataStore unavailable)`)
	end
	return s
end

-- A little rate limit on the remotes (a token bucket per player): honest play makes a few calls a second at most, so
-- a client that spams them is simply told to slow down.
local CALLS_PER_SECOND = 10
local CALL_BURST = 30
local buckets: { [Player]: { tokens: number, at: number } } = {}
local function allowCall(player: Player): boolean
	local now = os.clock()
	local bucket = buckets[player]
	if not bucket then
		bucket = { tokens = CALL_BURST, at = now }
		buckets[player] = bucket
	end
	bucket.tokens = math.min(CALL_BURST, bucket.tokens + (now - bucket.at) * CALLS_PER_SECOND)
	bucket.at = now
	if bucket.tokens < 1 then
		return false
	end
	bucket.tokens -= 1
	return true
end

function Garden.start()
	local container = Instance.new("Folder")
	container.Name = "Garden"
	container.Parent = Workspace
	parkContainer = container

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
		if not allowCall(player) then
			return fail("too fast")
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
		if not allowCall(player) then
			return fail("too fast")
		end
		if action == "state" then
			return { ok = true, state = snapshot(s) }
		elseif action == "plant" then
			return plant(s, payload)
		elseif action == "harvest" then
			return harvest(s, payload)
		elseif action == "unlockPlot" then
			return unlockPlot(s, payload)
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
		elseif action == "tip" then
			return tip(s, payload)
		elseif action == "useInstantGrow" then
			return useInstantGrow(s, payload)
		elseif action == "pat" then
			return pat(s, payload)
		elseif action == "parkOpen" then
			return parkOpen(s)
		elseif action == "parkPlace" then
			return parkPlace(s, payload)
		elseif action == "leaderboard" then
			return { ok = true, boards = Leaderboards.snapshot() }
		elseif action == "devGrow" then
			return devGrow(s)
		elseif action == "devLevelUp" then
			return devLevelUp(s)
		elseif action == "devPlotPass" then
			return devPlotPass(s)
		elseif action == "devBoxes" then
			return devBoxes(s)
		elseif action == "devGrant" then
			return devGrant(s, payload)
		end
		return nil
	end

	MarketplaceService.ProcessReceipt = processReceipt

	-- Game passes bought in the game take effect at once.
	MarketplaceService.PromptGamePassPurchaseFinished:Connect(
		function(player: Player, passId: number, purchased: boolean)
			local s = sessions[player]
			if s and purchased and Products.DoubleGrowthPassId > 0 and passId == Products.DoubleGrowthPassId then
				s.hasDoubleGrowth = true
				print(`[Garden] {player.Name}: bought Double Growth`)
				refresh(s)
				push(s)
			end
			if s and purchased and Plots.PassId > 0 and passId == Plots.PassId then
				s.hasPass = true
				print(`[Garden] {player.Name}: bought the Plot Pass`)
				refresh(s)
				push(s)
			end
		end
	)

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
		ParkBuilder.remove(player)
		buckets[player] = nil
		if s then
			PlayerStore.save(s.store, true)
			for _, node in s.nodes do
				node.soil:Destroy()
			end
			local marker = container:FindFirstChild(`Territory_{player.UserId}`)
			if marker then
				marker:Destroy()
			end
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
				applySprinkler(s, now)
				autoCare(s, now)
			end
			if sinceSave >= AUTOSAVE_SECONDS then
				sinceSave = 0
				for _, s in sessions do
					task.spawn(PlayerStore.save, s.store, false)
					if s.store.persistent then
						for _, board in Leaderboard.Boards do
							Leaderboards.submit(
								s.player.UserId,
								board,
								Leaderboard.valueFor(board, data(s).xp, data(s).collection)
							)
						end
					end
				end
			end
		end
	end)
end

return Garden
