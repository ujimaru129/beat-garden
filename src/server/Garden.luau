--!strict
-- Garden: one plot per player (prototype) with a plant that grows from time and from tending.
--
-- Tend flow (server side of the "Tend" RemoteFunction):
--   "begin", difficulty  -> checks range / cooldown, hands out a chart, starts the server clock
--   "submit", summary    -> validates the run, turns accuracy into growth points, updates the plant
-- The client shows the difficulty picker and plays the chart; the server decides every number.
-- State is in memory only for now (saving comes with the player data work).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Difficulty = require(ReplicatedStorage.Shared.Difficulty)
local Growth = require(ReplicatedStorage.Shared.Garden.Growth)
local Palette = require(ReplicatedStorage.Shared.Palette)
local RhythmEngine = require(ReplicatedStorage.Shared.RhythmEngine)
local TestCharts = require(ReplicatedStorage.Shared.Dev.TestCharts)

local Garden = {}

-- Prototype seed; the real ones come from Master_Seeds.
local TEST_SEED = { seedId = "seed_test", growSeconds = 180 }
local PLOT_SPACING = 14 -- studs between neighbouring plots
local PLOT_DISTANCE = 10 -- studs from the spawn
local TEND_RANGE = 24 -- the prompt works within ~12 studs; the server allows some lag on top

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

type PlotState = {
	slot: number,
	plot: Growth.Plot,
	soil: Part,
	plant: Part,
	pending: Pending?,
}

local plots: { [Player]: PlotState } = {}

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
	for _, state in plots do
		used[state.slot] = true
	end
	local slot = 1
	while used[slot] do
		slot += 1
	end
	return slot
end

local function refresh(state: PlotState)
	local now = os.time()
	local fraction = Growth.fraction(state.plot, TEST_SEED.growSeconds, now)
	local stage = Growth.stageFor(fraction)
	local look = STAGE_LOOK[stage]
	state.plant.Size = Vector3.new(look.size, look.size, look.size)
	state.plant.Color = look.color
	state.plant.Position = state.soil.Position + Vector3.new(0, state.soil.Size.Y / 2 + look.size / 2, 0)
	state.soil:SetAttribute("Stage", stage)
	state.soil:SetAttribute("Fraction", fraction)
end

local function createPlot(player: Player, container: Instance): PlotState
	local slot = freeSlot()
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
	prompt.MaxActivationDistance = 12
	prompt.RequiresLineOfSight = false
	prompt.KeyboardKeyCode = Enum.KeyCode.E
	prompt.UIOffset = Vector2.new(0, -90) -- lift the button off the bottom edge of a phone screen
	prompt.Parent = soil

	local state: PlotState = {
		slot = slot,
		plot = { seedId = TEST_SEED.seedId, plantedAt = os.time(), careGauge = 0, lastTendAt = 0 },
		soil = soil,
		plant = plant,
		pending = nil,
	}
	refresh(state)
	return state
end

local function distanceToPlot(player: Player, state: PlotState): number
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not (root and root:IsA("BasePart")) then
		return math.huge
	end
	return (root.Position - state.soil.Position).Magnitude
end

local function begin(player: Player, state: PlotState, payload: unknown): any
	if type(payload) ~= "string" or table.find(Difficulty.Names, payload) == nil then
		return { ok = false, reason = "bad difficulty" }
	end
	local difficulty = payload :: Difficulty.Name
	if distanceToPlot(player, state) > TEND_RANGE then
		return { ok = false, reason = "too far from the plant" }
	end
	local now = os.time()
	if Growth.stageFor(Growth.fraction(state.plot, TEST_SEED.growSeconds, now)) == "Fruit" then
		return { ok = false, reason = "fully grown" }
	end
	local wait = Growth.cooldownLeft(state.plot, now, COOLDOWN_SECONDS)
	if wait > 0 then
		return { ok = false, reason = `rest a little more ({wait}s)`, cooldown = wait }
	end

	-- Prototype: the test charts stand in for a real song's tend segments.
	local segment = (TestCharts :: any)[difficulty] :: RhythmEngine.Segment
	local pending = (
		{ segment = segment, startedAt = os.clock(), difficulty = difficulty :: Difficulty.Name } :: any
	) :: Pending
	state.pending = pending
	return { ok = true, segment = segment, bpm = TestCharts.Bpm[difficulty], difficulty = difficulty }
end

local function submit(player: Player, state: PlotState, payload: unknown): any
	local pending = state.pending
	state.pending = nil
	if not pending then
		return { ok = false, reason = "no run in progress" }
	end
	local elapsedMs = (os.clock() - pending.startedAt) * 1000
	local result = RhythmEngine.Validator.validate(pending.segment, payload, { elapsedMs = elapsedMs })
	if not result.ok or not result.tally then
		print(`[Garden] {player.Name}: run rejected ({result.reason})`)
		return { ok = false, reason = result.reason or "rejected" }
	end

	local tally = result.tally
	local points = Growth.tendPoints(tally.accuracy, pending.difficulty)
	local now = os.time()
	state.plot.careGauge += points
	state.plot.lastTendAt = now
	refresh(state)

	local fraction = Growth.fraction(state.plot, TEST_SEED.growSeconds, now)
	print(`[Garden] {player.Name}: {pending.difficulty} acc {math.floor(tally.accuracy * 100)}% -> +{points} growth`)
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

function Garden.start()
	local container = Instance.new("Folder")
	container.Name = "Garden"
	container.Parent = Workspace

	local remote = Instance.new("RemoteFunction")
	remote.Name = "Tend"
	remote.Parent = ReplicatedStorage

	remote.OnServerInvoke = function(player: Player, action: unknown, payload: unknown): any
		local state = plots[player]
		if not state then
			return { ok = false, reason = "no plot" }
		end
		if action == "begin" then
			return begin(player, state, payload)
		elseif action == "submit" then
			return submit(player, state, payload)
		end
		return nil
	end

	local function onPlayerAdded(player: Player)
		if plots[player] == nil then
			plots[player] = createPlot(player, container)
		end
	end
	Players.PlayerAdded:Connect(onPlayerAdded)
	for _, player in Players:GetPlayers() do
		onPlayerAdded(player)
	end

	Players.PlayerRemoving:Connect(function(player)
		local state = plots[player]
		plots[player] = nil
		if state then
			state.soil:Destroy()
		end
	end)

	-- Plants keep growing with time, so refresh their look once a second.
	task.spawn(function()
		while true do
			task.wait(1)
			for _, state in plots do
				refresh(state)
			end
		end
	end)
end

return Garden
