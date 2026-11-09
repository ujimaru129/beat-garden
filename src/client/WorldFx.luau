--!strict
-- Brings the island (server/World) to life on this client:
--   * day / night: every part tagged WorldTint swaps between its DayColor and NightColor (and to Neon
--     at night when Glow is set). At dusk the neon switches on as a ripple from the middle of the island.
--   * motion: Spin (disco ball), Bob (balloons), Orbit (light-shaft ends), Pulse (props bounce on the beat).
--   * NightOnly beams (the disco ball's light shafts) are only on at night.
-- Nothing here is gameplay: it is all local and cosmetic.

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Atmosphere = require(script.Parent.Atmosphere)

local WorldFx = {}

local BPM = 120 -- the idle groove of the island
local RIPPLE_SPEED = 90 -- studs per second at which the dusk switch-on spreads

function WorldFx.start()
	local root = Workspace:WaitForChild("World", 20)
	if not root then
		return
	end
	local centerAttr = root:GetAttribute("Center")
	local center: Vector3 = if typeof(centerAttr) == "Vector3" then centerAttr else Vector3.zero

	local player = Players.LocalPlayer :: Player
	local night = Atmosphere.timeOfDay() == "Night"
	local running = player:GetAttribute("InRhythm") == true
	local tinted: { Part } = {}
	local beams: { Beam } = {}
	local rainbow: { Beam } = {}
	local spinners: { { part: Part, base: CFrame, speed: number } } = {}
	local bobbers: { { part: Part, base: Vector3, amount: number, speed: number, phase: number } } = {}
	local orbiters: { { part: Part, center: Vector3, radius: number, speed: number, phase: number } } = {}
	local pulsers: { { part: Part, size: Vector3, amount: number } } = {}

	local function setTint(part: Part, animate: boolean)
		local day = part:GetAttribute("DayColor")
		local nightColor = part:GetAttribute("NightColor")
		if typeof(day) ~= "Color3" or typeof(nightColor) ~= "Color3" then
			return
		end
		local target = if night then nightColor else day
		local material = if night and part:GetAttribute("Glow") == true
			then Enum.Material.Neon
			else Enum.Material.SmoothPlastic
		if not animate then
			part.Color = target
			part.Material = material
			return
		end
		local delay = (part.Position - center).Magnitude / RIPPLE_SPEED
		task.delay(delay, function()
			if not part.Parent then
				return
			end
			part.Material = material
			TweenService:Create(part, TweenInfo.new(0.7), { Color = target }):Play()
		end)
	end

	local function setRainbowWidth(beam: Beam)
		local dayWidth, nightWidth = beam:GetAttribute("DayWidth"), beam:GetAttribute("NightWidth")
		local width = if night then nightWidth else dayWidth
		if type(width) == "number" then
			beam.Width0 = width
			beam.Width1 = width
		end
		beam.LightEmission = if night then 1 else 0.5
	end

	-- During a rhythm run the floor stays, and so does the scenery up in the sky (balloons, clouds, the rainbow): it
	-- keeps the picture from going bare and sits well above the lane. The props on the ground and the neon rims
	-- hide, because they would clutter the lane.
	local KEEP_IN_RUN: { [string]: boolean } = {
		Balloon = true,
		BalloonString = true,
		Cloud = true,
		SkyCloud = true,
		SkyIsland = true,
		Star = true,
		RimSpire = true,
	}
	local function applyRun(inst: Instance)
		if inst:IsA("BasePart") and not CollectionService:HasTag(inst, "WorldFloor") then
			inst.LocalTransparencyModifier = if running and not KEEP_IN_RUN[inst.Name] then 1 else 0
		elseif inst:IsA("Beam") then
			if CollectionService:HasTag(inst, "RainbowBeam") then
				inst.Enabled = true
			elseif CollectionService:HasTag(inst, "KeepInRun") then
				inst.Enabled = night -- lasers: on all night, also during a run
			else
				inst.Enabled = not running and (night or not CollectionService:HasTag(inst, "NightOnly"))
			end
		end
	end

	local function track(inst: Instance)
		applyRun(inst)
		if inst:IsA("Beam") and CollectionService:HasTag(inst, "RainbowBeam") then
			table.insert(rainbow, inst)
			setRainbowWidth(inst)
			return
		end
		if inst:IsA("Beam") and CollectionService:HasTag(inst, "NightOnly") then
			inst.Enabled = night
			table.insert(beams, inst)
			return
		end
		if not inst:IsA("Part") then
			return
		end
		if CollectionService:HasTag(inst, "WorldTint") then
			table.insert(tinted, inst)
			setTint(inst, false)
		end
		if CollectionService:HasTag(inst, "Spin") then
			local speed = inst:GetAttribute("SpinSpeed")
			table.insert(
				spinners,
				{ part = inst, base = inst.CFrame, speed = if type(speed) == "number" then speed else 20 }
			)
		end
		if CollectionService:HasTag(inst, "Bob") then
			local amount, speed, phase =
				inst:GetAttribute("BobAmount"), inst:GetAttribute("BobSpeed"), inst:GetAttribute("BobPhase")
			table.insert(bobbers, {
				part = inst,
				base = inst.Position,
				amount = if type(amount) == "number" then amount else 1,
				speed = if type(speed) == "number" then speed else 1,
				phase = if type(phase) == "number" then phase else 0,
			})
		end
		if CollectionService:HasTag(inst, "Orbit") then
			local c, r, sp, ph =
				inst:GetAttribute("OrbitCenter"),
				inst:GetAttribute("OrbitRadius"),
				inst:GetAttribute("OrbitSpeed"),
				inst:GetAttribute("OrbitPhase")
			if typeof(c) == "Vector3" and type(r) == "number" and type(sp) == "number" and type(ph) == "number" then
				table.insert(orbiters, { part = inst, center = c, radius = r, speed = sp, phase = ph })
			end
		end
		if CollectionService:HasTag(inst, "Pulse") then
			local amount = inst:GetAttribute("PulseAmount")
			table.insert(
				pulsers,
				{ part = inst, size = inst.Size, amount = if type(amount) == "number" then amount else 0.08 }
			)
		end
	end

	for _, inst in root:GetDescendants() do
		track(inst)
	end
	root.DescendantAdded:Connect(track)

	player:GetAttributeChangedSignal("InRhythm"):Connect(function()
		running = player:GetAttribute("InRhythm") == true
		for _, inst in root:GetDescendants() do
			applyRun(inst)
		end
	end)

	-- Day <-> night: the neon switches on (or off) as a ripple from the middle of the island.
	task.spawn(function()
		while true do
			task.wait(0.5)
			local now = Atmosphere.timeOfDay() == "Night"
			if now ~= night then
				night = now
				for _, part in tinted do
					setTint(part, true)
				end
				for _, beam in beams do
					beam.Enabled = night and (not running or CollectionService:HasTag(beam, "KeepInRun"))
				end
				for _, beam in rainbow do
					setRainbowWidth(beam)
				end
			end
		end
	end)

	-- Motion
	RunService.Heartbeat:Connect(function()
		local t = Workspace:GetServerTimeNow()
		local beat = t * BPM / 60
		local frac = beat - math.floor(beat)
		-- a quick punch on the beat that settles back
		local punch = (1 - frac) ^ 4

		for _, s in spinners do
			s.part.CFrame = s.base * CFrame.Angles(0, math.rad(t * s.speed), 0)
		end
		for _, b in bobbers do
			b.part.Position = b.base + Vector3.new(0, math.sin(t * b.speed + b.phase) * b.amount, 0)
		end
		for _, o in orbiters do
			local a = o.phase + t * o.speed
			o.part.Position = o.center + Vector3.new(math.cos(a) * o.radius, 0, math.sin(a) * o.radius)
		end
		for _, p in pulsers do
			p.part.Size = p.size * (1 + p.amount * punch)
		end
	end)
end

return WorldFx
