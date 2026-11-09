--!strict
-- Candy Disco Island: the garden's world. A floating island of sweets: a candy-swirl floor, candy-cane
-- fence, lollipops, cupcakes, macarons, gumdrops, balloons, clouds, a rainbow and a disco ball.
-- Built from plain parts at start-up, so it replicates to everyone. The look changes with the time of day
-- on each client (see client/WorldFx): every part that has a DayColor attribute swaps to its NightColor
-- (and to the Neon material when it has Glow = true) at night.
--
-- The floor top is the new ground: build this BEFORE the plots and NPCs, which place themselves by
-- raycasting down onto it.

local CollectionService = game:GetService("CollectionService")
local Workspace = game:GetService("Workspace")

local World = {}

local hex = Color3.fromHex

export type Tint = { day: Color3, night: Color3, glow: boolean? }

local ISLAND_RADIUS = 90
local WALL_HEIGHT = 40

-- Pastel candy colours by day. By night the big bodies turn deep and dark: a large Neon surface blows up into
-- a blurry blob, so neon is only used for thin "tubes" (rims, rings, rails, strings) - see `tube`.
export type Candy = { day: Color3, night: Color3, glow: boolean?, neon: Color3 }
local function candy(day: string, neon: string): Candy
	local n = hex(neon)
	return { day = hex(day), night = n:Lerp(Color3.new(0.05, 0.02, 0.15), 0.62), glow = false, neon = n }
end
local C = {
	pink = candy("#FF9CCB", "#FF4FA3"),
	sky = candy("#8FD3FF", "#3FC8FF"),
	mint = candy("#8CEBC3", "#3DFFB0"),
	lemon = candy("#FFE27A", "#FFE14D"),
	grape = candy("#C3A1FF", "#A86BFF"),
	-- "white" is a soft cream-pink by day: pure white blows out in the sun
	white = candy("#FFD9EA", "#F4EEFF"),
	peach = candy("#FFB88A", "#FF9A4D"),
}

-- The thin glowing version of a colour: the same by day, neon by night.
local function tube(c: Candy): Tint
	return { day = c.day, night = c.neon, glow = true }
end

local FLOOR_NIGHT = { hex("#33207A"), hex("#241868"), hex("#1B2A6B"), hex("#3A2480"), hex("#2B1B6E"), hex("#33207A") }

-- Where the player lives: around the spawn, the two shops and the row of plots no prop may stand
-- (a cupcake on the spawn put the camera inside its frosting).
local playSpot = Vector3.zero
local function blocked(x: number, z: number): boolean
	local dx, dz = x - playSpot.X, z - playSpot.Z
	if dx * dx + dz * dz < 30 * 30 then
		return true
	end
	-- the strip the plots stand on (they run along +X, 10 studs behind the spawn)
	return dz > -26 and dz < 10 and dx > -34 and dx < 125
end

-- An angle around `center` at `radius` whose spot is free; tries the given angle first.
local function freeAngle(center: Vector3, angle: number, radius: number, rng: Random): number
	local a = angle
	for _ = 1, 60 do
		if not blocked(center.X + math.cos(a) * radius, center.Z + math.sin(a) * radius) then
			return a
		end
		a = rng:NextNumber(0, math.pi * 2)
	end
	return a
end

local function newPart(props: { [string]: any }, parent: Instance, tint: Tint?): Part
	local p = Instance.new("Part")
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.Material = Enum.Material.SmoothPlastic
	for k, v in props do
		(p :: any)[k] = v
	end
	if tint then
		p.Color = tint.day
		p:SetAttribute("DayColor", tint.day)
		p:SetAttribute("NightColor", tint.night)
		p:SetAttribute("Glow", tint.glow == true)
		CollectionService:AddTag(p, "WorldTint")
	end
	p.Parent = parent
	return p
end

-- A flat disc lying on the ground: its top is at `top`, `thickness` thick.
local function disc(
	parent: Instance,
	center: Vector3,
	radius: number,
	top: number,
	thickness: number,
	tint: Tint?,
	collide: boolean?
): Part
	return newPart({
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(thickness, radius * 2, radius * 2),
		CFrame = CFrame.new(center.X, top - thickness / 2, center.Z) * CFrame.Angles(0, 0, math.rad(90)),
		CanCollide = collide == true,
		CanQuery = collide == true,
	}, parent, tint)
end

local function ball(parent: Instance, position: Vector3, radius: number, tint: Tint): Part
	return newPart({
		Shape = Enum.PartType.Ball,
		Size = Vector3.new(radius * 2, radius * 2, radius * 2),
		Position = position,
	}, parent, tint)
end

-- An upright cylinder standing on `base`.
local function column(parent: Instance, base: Vector3, radius: number, height: number, tint: Tint): Part
	return newPart({
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(height, radius * 2, radius * 2),
		CFrame = CFrame.new(base.X, base.Y + height / 2, base.Z) * CFrame.Angles(0, 0, math.rad(90)),
	}, parent, tint)
end

local function tag(inst: Instance, name: string, attributes: { [string]: any }?)
	CollectionService:AddTag(inst, name)
	if attributes then
		for k, v in attributes do
			inst:SetAttribute(k, v)
		end
	end
end

local function groundTop(): number
	local base = Workspace:FindFirstChild("Baseplate")
	if base and base:IsA("BasePart") then
		return base.Position.Y + base.Size.Y / 2
	end
	local spawn = Workspace:FindFirstChildWhichIsA("SpawnLocation", true)
	if spawn then
		return spawn.Position.Y - spawn.Size.Y / 2
	end
	return 0
end

local function spawnPosition(): Vector3
	local spawn = Workspace:FindFirstChildWhichIsA("SpawnLocation", true)
	return if spawn then spawn.Position else Vector3.zero
end

-- The floor: concentric candy-swirl bands, a cake of layers underneath, and a glowing rim at night.
local function buildFloor(root: Folder, center: Vector3, top: number)
	local bands = {
		{ radius = ISLAND_RADIUS, tint = C.pink },
		{ radius = ISLAND_RADIUS * 0.8, tint = C.sky },
		{ radius = ISLAND_RADIUS * 0.62, tint = C.mint },
		{ radius = ISLAND_RADIUS * 0.46, tint = C.grape },
		{ radius = ISLAND_RADIUS * 0.3, tint = C.lemon },
		{ radius = ISLAND_RADIUS * 0.15, tint = C.peach },
	}
	for i, band in bands do
		local level = top + 0.04 * i
		-- A slightly larger disc under each band: invisible by day (same colour), a neon edge at night.
		disc(root, center, band.radius + 0.5, level - 0.02, 0.2, tube(band.tint))
		-- The band itself: by day the pastel colour, at night a deep colour.
		local d = disc(root, center, band.radius, level, if i == 1 then 4 else 0.4, {
			day = band.tint.day,
			night = FLOOR_NIGHT[i],
			glow = false,
		}, i == 1)
		d.Name = `Floor{i}`
		CollectionService:AddTag(d, "WorldFloor") -- stays visible during a rhythm run; everything else hides
		d.Material = Enum.Material.SmoothPlastic
	end
	-- Cake layers under the island, so it reads as a floating cake from the side.
	local layers = {
		{ radius = ISLAND_RADIUS * 0.97, thick = 6, tint = C.white },
		{ radius = ISLAND_RADIUS * 0.9, thick = 8, tint = C.pink },
		{ radius = ISLAND_RADIUS * 0.7, thick = 8, tint = C.grape },
		{ radius = ISLAND_RADIUS * 0.45, thick = 8, tint = C.sky },
	}
	local y = top - 0.4
	for _, layer in layers do
		disc(root, center, layer.radius, y, layer.thick, layer.tint)
		y -= layer.thick
	end
end

-- Candy-cane fence along the rim, with an invisible wall so nobody walks off the island.
local function buildFence(root: Folder, center: Vector3, top: number)
	local count = 36
	local radius = ISLAND_RADIUS - 2
	for i = 0, count - 1 do
		local angle = i / count * math.pi * 2
		local pos = center + Vector3.new(math.cos(angle) * radius, 0, math.sin(angle) * radius)
		local base = Vector3.new(pos.X, top + 0.4, pos.Z)
		local red = if i % 2 == 0 then C.pink else C.sky
		column(root, base, 0.7, 6, C.white)
		local band = column(root, base + Vector3.new(0, 1.2, 0), 0.75, 1.1, tube(red))
		band.Name = "FenceBand"
		local band2 = column(root, base + Vector3.new(0, 3.6, 0), 0.75, 1.1, tube(red))
		band2.Name = "FenceBand"
		ball(root, base + Vector3.new(0, 6.3, 0), 0.9, tube(red))
		-- invisible wall segment between this post and the next
		local nextAngle = (i + 0.5) / count * math.pi * 2
		local wallPos = center
			+ Vector3.new(math.cos(nextAngle) * radius, WALL_HEIGHT / 2, math.sin(nextAngle) * radius)
		local wall = newPart({
			Name = "Wall",
			Size = Vector3.new(radius * math.pi * 2 / count + 1, WALL_HEIGHT, 2),
			CFrame = CFrame.lookAt(wallPos, Vector3.new(center.X, wallPos.Y, center.Z)),
			Transparency = 1,
			CanCollide = true,
			CanQuery = false,
		}, root)
		wall.Name = "Wall"
	end
end

-- Giant lollipops: a stick and a swirl head that faces the middle of the island.
local function buildLollipops(root: Folder, center: Vector3, top: number, rng: Random)
	local colors = { C.pink, C.sky, C.mint, C.lemon, C.grape, C.peach }
	local count = 10
	for i = 1, count do
		local angle = (i / count) * math.pi * 2 + rng:NextNumber(-0.15, 0.15)
		local radius = ISLAND_RADIUS * rng:NextNumber(0.62, 0.84)
		angle = freeAngle(center, angle, radius, rng)
		local base = Vector3.new(center.X + math.cos(angle) * radius, top + 0.4, center.Z + math.sin(angle) * radius)
		local height = rng:NextNumber(14, 22)
		local headRadius = rng:NextNumber(5.5, 8)
		local a = colors[(i - 1) % #colors + 1]
		local b = colors[(i + 2) % #colors + 1]
		column(root, base, 0.6, height, C.white)
		local headCenter = base + Vector3.new(0, height + headRadius * 0.7, 0)
		local facing = CFrame.lookAt(headCenter, Vector3.new(center.X, headCenter.Y, center.Z))
		-- three discs stacked towards the viewer: outer ring, inner ring, dot
		local function head(r: number, offset: number, tint: Tint)
			local p = newPart({
				Shape = Enum.PartType.Cylinder,
				Size = Vector3.new(1, r * 2, r * 2),
				CFrame = facing * CFrame.new(0, 0, -offset) * CFrame.Angles(0, math.rad(90), 0),
			}, root, tint)
			p.Name = "LollipopHead"
			tag(p, "Pulse", { PulseAmount = 0.08 })
			return p
		end
		-- a thin neon rim around the head (the body itself goes dark at night)
		local rim = newPart({
			Shape = Enum.PartType.Cylinder,
			Size = Vector3.new(0.5, headRadius * 2 + 1.2, headRadius * 2 + 1.2),
			CFrame = facing * CFrame.new(0, 0, 0.3) * CFrame.Angles(0, math.rad(90), 0),
		}, root, tube(a))
		rim.Name = "LollipopRim"
		head(headRadius, 0, a)
		head(headRadius * 0.72, 0.4, C.white)
		head(headRadius * 0.5, 0.8, b)
		head(headRadius * 0.22, 1.2, a)
	end
end

-- Cupcakes: a cup, a swirl of frosting and a glowing cherry.
local function buildCupcakes(root: Folder, center: Vector3, top: number, rng: Random)
	local frosting = { C.pink, C.sky, C.mint, C.lemon, C.grape }
	local count = 8
	for i = 1, count do
		local angle = (i / count) * math.pi * 2 + math.pi / count
		local radius = ISLAND_RADIUS * rng:NextNumber(0.4, 0.55)
		angle = freeAngle(center, angle, radius, rng)
		local base = Vector3.new(center.X + math.cos(angle) * radius, top + 0.4, center.Z + math.sin(angle) * radius)
		local size = rng:NextNumber(0.9, 1.3)
		column(root, base, 4.4 * size, 5 * size, C.peach)
		local top1 = ball(root, base + Vector3.new(0, 6.2 * size, 0), 5.2 * size, frosting[i % #frosting + 1])
		local top2 = ball(root, base + Vector3.new(0, 9.4 * size, 0), 3.4 * size, frosting[(i + 1) % #frosting + 1])
		local cherry = ball(root, base + Vector3.new(0, 12.2 * size, 0), 1.3 * size, tube(C.pink))
		disc(root, base, 4.9 * size, base.Y + 0.1, 0.2, tube(frosting[i % #frosting + 1]))
		tag(top1, "Pulse", { PulseAmount = 0.06 })
		tag(top2, "Pulse", { PulseAmount = 0.1 })
		tag(cherry, "Pulse", { PulseAmount = 0.2 })
	end
end

-- Macarons: two shells with cream between them, standing like wheels.
local function buildMacarons(root: Folder, center: Vector3, top: number, rng: Random)
	local shells = { C.pink, C.mint, C.lemon, C.sky }
	for i = 1, 5 do
		local angle = (i / 5) * math.pi * 2 + 0.4
		local radius = ISLAND_RADIUS * rng:NextNumber(0.25, 0.36)
		angle = freeAngle(center, angle, radius, rng)
		local radiusM = rng:NextNumber(4.5, 6)
		local base =
			Vector3.new(center.X + math.cos(angle) * radius, top + 0.4 + radiusM, center.Z + math.sin(angle) * radius)
		local face = CFrame.lookAt(base, Vector3.new(center.X, base.Y, center.Z))
		local tint = shells[(i - 1) % #shells + 1]
		for _, offset in { -1.4, 1.4 } do
			newPart({
				Shape = Enum.PartType.Cylinder,
				Size = Vector3.new(1.6, radiusM * 2, radiusM * 2),
				CFrame = face * CFrame.new(0, 0, offset) * CFrame.Angles(0, math.rad(90), 0),
			}, root, tint)
		end
		newPart({
			Shape = Enum.PartType.Cylinder,
			Size = Vector3.new(1.4, radiusM * 1.85, radiusM * 1.85),
			CFrame = face * CFrame.Angles(0, math.rad(90), 0),
		}, root, tube(C.white))
	end
end

-- Gumdrops: half-buried balls scattered over the floor.
local function buildGumdrops(root: Folder, center: Vector3, top: number, rng: Random)
	local colors = { C.pink, C.sky, C.mint, C.lemon, C.grape, C.peach }
	for i = 1, 22 do
		local angle = rng:NextNumber(0, math.pi * 2)
		local radius = ISLAND_RADIUS * math.sqrt(rng:NextNumber(0.04, 0.9))
		angle = freeAngle(center, angle, radius, rng)
		local r = rng:NextNumber(1.8, 4.2)
		local p = ball(
			root,
			Vector3.new(center.X + math.cos(angle) * radius, top + 0.2, center.Z + math.sin(angle) * radius),
			r,
			colors[i % #colors + 1]
		)
		tag(p, "Pulse", { PulseAmount = 0.12 })
		disc(root, Vector3.new(p.Position.X, 0, p.Position.Z), r + 0.5, top + 0.45, 0.1, tube(colors[i % #colors + 1]))
	end
end

-- Balloons: floating balls on a string; they bob and sway.
local function buildBalloons(root: Folder, center: Vector3, top: number, rng: Random)
	local colors = { C.pink, C.sky, C.mint, C.lemon, C.grape }
	for i = 1, 44 do
		local angle = rng:NextNumber(0, math.pi * 2)
		local radius = ISLAND_RADIUS * rng:NextNumber(0.25, 0.94)
		angle = freeAngle(center, angle, radius, rng)
		local x, z = center.X + math.cos(angle) * radius, center.Z + math.sin(angle) * radius
		local height = rng:NextNumber(14, 52)
		local r = rng:NextNumber(2.8, 4)
		local b = ball(root, Vector3.new(x, top + height, z), r, colors[i % #colors + 1])
		b.Name = "Balloon"
		tag(
			b,
			"Bob",
			{ BobAmount = rng:NextNumber(1, 2.2), BobSpeed = rng:NextNumber(0.6, 1.2), BobPhase = rng:NextNumber(0, 6) }
		)
		-- the string
		local string_ = newPart({
			Size = Vector3.new(0.12, height - r, 0.12),
			Position = Vector3.new(x, top + (height - r) / 2, z),
			Transparency = 0.3,
		}, root, tube(colors[i % #colors + 1]))
		string_.Name = "BalloonString"
	end
end

-- Clouds under and around the island (puffy clusters of balls).
local function buildClouds(root: Folder, center: Vector3, top: number, rng: Random)
	local count = 18
	for i = 1, count do
		local angle = (i / count) * math.pi * 2 + rng:NextNumber(-0.2, 0.2)
		local radius = ISLAND_RADIUS * rng:NextNumber(1.2, 2.3)
		local y = top + rng:NextNumber(-70, -25)
		local cx, cz = center.X + math.cos(angle) * radius, center.Z + math.sin(angle) * radius
		for k = 1, 4 do
			local r = rng:NextNumber(10, 20)
			local puff = ball(
				root,
				Vector3.new(cx + rng:NextNumber(-16, 16), y + rng:NextNumber(-4, 4), cz + rng:NextNumber(-16, 16)),
				r,
				if k % 2 == 0 then C.white else C.pink
			)
			puff.Name = "Cloud"
		end
	end
end

-- A rainbow arch of beams behind the plots, and a disco ball hanging above them.
local function buildSky(root: Folder, center: Vector3, top: number)
	local archZ = center.Z - ISLAND_RADIUS * 0.6
	local colors = {
		hex("#FF4F4F"),
		hex("#FF9A3D"),
		hex("#FFE14D"),
		hex("#4DE68A"),
		hex("#3FC8FF"),
		hex("#A86BFF"),
	}
	local halfWidth = 62
	for i, color in colors do
		local inset = (i - 1) * 3.6
		local left = newPart(
			{ Name = "RainbowEnd", Transparency = 1, Position = Vector3.new(center.X - halfWidth + inset, top, archZ) },
			root
		)
		local right = newPart(
			{ Name = "RainbowEnd", Transparency = 1, Position = Vector3.new(center.X + halfWidth - inset, top, archZ) },
			root
		)
		-- attachments with their X axis pointing up: the curve bulges upwards
		local a0 = Instance.new("Attachment")
		a0.CFrame = CFrame.Angles(0, 0, math.rad(90))
		a0.Parent = left
		local a1 = Instance.new("Attachment")
		a1.CFrame = CFrame.Angles(0, 0, math.rad(90))
		a1.Parent = right
		local beam = Instance.new("Beam")
		beam.Name = "Rainbow"
		beam.Attachment0 = a0
		beam.Attachment1 = a1
		beam.Color = ColorSequence.new(color)
		beam.Width0 = 3.8
		beam.Width1 = 3.8
		beam.CurveSize0 = 70 - inset * 2.2
		beam.CurveSize1 = -(70 - inset * 2.2)
		beam.Segments = 40
		beam.FaceCamera = true
		beam.LightEmission = 0.5
		beam.Transparency = NumberSequence.new(0.1)
		beam.Parent = left
		-- By day a fat pastel arch; by night thin bright tubes (the client swaps the widths).
		tag(beam, "RainbowBeam", { DayWidth = 3.8, NightWidth = 0.7 })
	end

	-- Disco ball: hangs over the plot row; spins; at night it throws light beams (see WorldFx).
	local ballPos = Vector3.new(center.X + 8, top + 52, center.Z - 14)
	local discoBall = ball(root, ballPos, 6, { day = hex("#E8E4FF"), night = hex("#FFFFFF"), glow = false })
	discoBall.Name = "DiscoBall"
	discoBall.Material = Enum.Material.Metal
	discoBall.Reflectance = 0.35
	tag(discoBall, "Spin", { SpinSpeed = 25 })
	newPart({
		Name = "DiscoString",
		Size = Vector3.new(0.2, 40, 0.2),
		Position = ballPos + Vector3.new(0, 26, 0),
	}, root, { day = hex("#FFFFFF"), night = hex("#FFFFFF"), glow = true })
	-- Light shafts from the ball down to the floor, each ending in an orbiting point.
	for i = 1, 12 do
		local color = ({ C.pink, C.sky, C.mint, C.lemon, C.grape, C.white })[(i - 1) % 6 + 1]
		local target = newPart({
			Name = "ShaftEnd",
			Transparency = 1,
			Position = Vector3.new(ballPos.X + 22, top + 0.6, ballPos.Z),
		}, root)
		tag(target, "Orbit", {
			OrbitCenter = Vector3.new(ballPos.X, top + 0.6, ballPos.Z),
			OrbitRadius = 10 + (i % 4) * 11,
			OrbitSpeed = (if i % 2 == 0 then 1 else -1) * (0.35 + i * 0.06),
			OrbitPhase = i / 12 * math.pi * 2,
		})
		local top0 = newPart({ Name = "ShaftStart", Transparency = 1, Position = ballPos }, root)
		local s0 = Instance.new("Attachment")
		s0.Parent = top0
		local s1 = Instance.new("Attachment")
		s1.Parent = target
		local beam = Instance.new("Beam")
		beam.Name = "Shaft"
		beam.Attachment0 = s0
		beam.Attachment1 = s1
		beam.Color = ColorSequence.new(color.neon)
		beam.Width0 = 0.15
		beam.Width1 = 0.35
		beam.FaceCamera = true
		beam.LightEmission = 1
		beam.Transparency = NumberSequence.new(0.05)
		beam.Enabled = false
		beam.Parent = top0
		tag(beam, "NightOnly")
	end
end

function World.start()
	local root = Instance.new("Folder")
	root.Name = "World"
	root.Parent = Workspace

	local spawn = spawnPosition()
	playSpot = spawn
	local top = groundTop()
	-- Centred on the plot row (plots run along +X at -Z from the spawn) and the shops on the other side.
	local center = Vector3.new(spawn.X + 35, top, spawn.Z - 5)
	local rng = Random.new(20261108)

	-- The default baseplate is replaced by the island; keep it as an invisible safety net far below.
	local base = Workspace:FindFirstChild("Baseplate")
	if base and base:IsA("BasePart") then
		base.Transparency = 1
		base.CanCollide = false
		base.CanQuery = false
		base.Position = Vector3.new(base.Position.X, top - 200, base.Position.Z)
	end

	root:SetAttribute("Center", center)
	buildFloor(root, center, top)
	buildFence(root, center, top)
	buildLollipops(root, center, top, rng)
	buildCupcakes(root, center, top, rng)
	buildMacarons(root, center, top, rng)
	buildGumdrops(root, center, top, rng)
	buildBalloons(root, center, top, rng)
	buildClouds(root, center, top, rng)
	buildSky(root, center, top)
end

return World
