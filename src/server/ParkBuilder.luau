--!strict
-- Builds the park attractions in a player's territory (what stands on each lot) from the player's data.
-- Everything is made of simple parts. Moving parts are Models tagged for the client (see client/ParkFx):
--   ParkSpin  (attributes SpinSpeed rad/s, SpinAxis "X"|"Y"|"Z")  - turns around the model's pivot
--   ParkSwing (SwingAngle rad, SwingSpeed, SwingPhase)             - swings like a pendulum around the pivot (X axis)
--   ParkBob   (BobAmount studs, BobSpeed, BobPhase)                - floats up and down
-- and parts tagged ParkRainbow change colour all the time (the rare Rainbow palette).
-- Nothing here collides: the park is decoration, players can walk through it.

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Palette = require(ReplicatedStorage.Shared.Palette)
local Park = require(ReplicatedStorage.Shared.Garden.Park)
local Plots = require(ReplicatedStorage.Shared.Garden.Plots)

local ParkBuilder = {}

-- Where each lot stands in a territory: studs from the hub centre (radial) and to the side (tangent) on the
-- territory's centre line, and the height above the ground. Ground lots are behind the plots; sky lots float above.
local LOT_PLACE: { [string]: { radial: number, tangent: number, height: number } } = {
	G1 = { radial = 107, tangent = -18, height = 0 },
	G2 = { radial = 107, tangent = 0, height = 0 },
	G3 = { radial = 107, tangent = 18, height = 0 },
	S1 = { radial = 86, tangent = -22, height = 38 },
	S2 = { radial = 86, tangent = 22, height = 42 },
	S3 = { radial = 100, tangent = 0, height = 54 },
}

type Ctx = {
	folder: Instance,
	cf: CFrame, -- the lot: origin on the ground (or the sky spot), -Z faces the plots
	primary: Color3,
	accent: Color3,
	rainbow: boolean,
	seed: number,
}

local WHITE = Color3.fromRGB(255, 255, 255)
local DARK = Color3.fromRGB(60, 50, 90)

local function mark(inst: Instance, ctx: Ctx)
	if ctx.rainbow and inst:IsA("BasePart") then
		CollectionService:AddTag(inst, "ParkRainbow")
	end
end

-- A part at `offset` (in the lot's own space) with its own rotation.
local function part(ctx: Ctx, parent: Instance, props: { [string]: any }, offset: Vector3, rotation: CFrame?): Part
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
	p.CFrame = ctx.cf * CFrame.new(offset) * (rotation or CFrame.identity)
	p.Parent = parent
	return p
end

local function box(ctx: Ctx, parent: Instance, offset: Vector3, size: Vector3, color: Color3, neon: boolean?): Part
	local p = part(ctx, parent, {
		Size = size,
		Color = color,
		Material = if neon then Enum.Material.Neon else Enum.Material.SmoothPlastic,
	}, offset)
	if neon then
		mark(p, ctx)
	end
	return p
end

local function ball(ctx: Ctx, parent: Instance, offset: Vector3, diameter: number, color: Color3, neon: boolean?): Part
	local p = part(ctx, parent, {
		Shape = Enum.PartType.Ball,
		Size = Vector3.new(diameter, diameter, diameter),
		Color = color,
		Material = if neon then Enum.Material.Neon else Enum.Material.SmoothPlastic,
	}, offset)
	mark(p, ctx)
	return p
end

-- A thin bar between two points (lot space).
local function rod(
	ctx: Ctx,
	parent: Instance,
	a: Vector3,
	b: Vector3,
	thickness: number,
	color: Color3,
	neon: boolean?
): Part
	local p = part(ctx, parent, {
		Size = Vector3.new(thickness, thickness, math.max((b - a).Magnitude, 0.05)),
		Color = color,
		Material = if neon then Enum.Material.Neon else Enum.Material.SmoothPlastic,
	}, Vector3.zero)
	p.CFrame = ctx.cf * CFrame.lookAt((a + b) / 2, b)
	if neon then
		mark(p, ctx)
	end
	return p
end

-- A cylinder standing upright: `height` tall, `diameter` wide.
local function post(
	ctx: Ctx,
	parent: Instance,
	offset: Vector3,
	height: number,
	diameter: number,
	color: Color3,
	neon: boolean?
): Part
	local p = part(ctx, parent, {
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(height, diameter, diameter),
		Color = color,
		Material = if neon then Enum.Material.Neon else Enum.Material.SmoothPlastic,
	}, offset, CFrame.Angles(0, 0, math.rad(90)))
	if neon then
		mark(p, ctx)
	end
	return p
end

-- A Model whose pivot is at `pivotOffset` (lot space); the client moves it by its tag.
local function mover(
	ctx: Ctx,
	parent: Instance,
	tag: string,
	pivotOffset: Vector3,
	attributes: { [string]: any }
): Model
	local model = Instance.new("Model")
	model.Name = tag
	model.WorldPivot = ctx.cf * CFrame.new(pivotOffset)
	for k, v in attributes do
		model:SetAttribute(k, v)
	end
	model.Parent = parent
	CollectionService:AddTag(model, tag)
	return model
end

-- White puffs under a sky attraction, so it does not hang in thin air.
local function cloudBase(ctx: Ctx, parent: Instance, radius: number)
	for i = 1, 6 do
		local angle = (i / 6) * math.pi * 2 + ctx.seed
		local r = if i == 1 then 0 else radius * 0.55
		local size = radius * (0.9 + 0.15 * ((i + ctx.seed) % 3))
		local p = part(ctx, parent, {
			Shape = Enum.PartType.Ball,
			Size = Vector3.new(size, size * 0.55, size),
			Color = WHITE,
			Material = Enum.Material.SmoothPlastic,
			Transparency = 0.05,
		}, Vector3.new(math.cos(angle) * r, -1.5 + 0.3 * (i % 2), math.sin(angle) * r))
		p.Name = "SkyCloud"
	end
end

local function light(parent: Instance, color: Color3, brightness: number, range: number)
	local l = Instance.new("PointLight")
	l.Color = color
	l.Brightness = brightness
	l.Range = range
	l.Shadows = false
	l.Parent = parent
end

-- Attractions ---------------------------------------------------------------------------------------------------

local builders: { [string]: (ctx: Ctx, parent: Instance) -> () } = {}

function builders.fountain(ctx, parent)
	post(ctx, parent, Vector3.new(0, 0.5, 0), 1, 13, WHITE)
	post(ctx, parent, Vector3.new(0, 1.2, 0), 1.2, 11, ctx.primary)
	post(ctx, parent, Vector3.new(0, 1.5, 0), 0.6, 10, Color3.fromRGB(120, 210, 255), true) -- the water
	post(ctx, parent, Vector3.new(0, 3.2, 0), 3.4, 1.6, WHITE)
	post(ctx, parent, Vector3.new(0, 5.1, 0), 0.8, 5.5, ctx.accent)
	post(ctx, parent, Vector3.new(0, 5.7, 0), 0.4, 4.6, Color3.fromRGB(150, 225, 255), true)
	local top = part(ctx, parent, { Transparency = 1, Size = Vector3.new(1, 1, 1) }, Vector3.new(0, 6.2, 0))
	local spray = Instance.new("ParticleEmitter")
	spray.Color = ColorSequence.new(Color3.fromRGB(190, 235, 255))
	spray.LightEmission = 0.8
	spray.Rate = 26
	spray.Lifetime = NumberRange.new(1, 1.5)
	spray.Speed = NumberRange.new(7, 10)
	spray.SpreadAngle = Vector2.new(28, 28)
	spray.Acceleration = Vector3.new(0, -16, 0)
	spray.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.55), NumberSequenceKeypoint.new(1, 0.1) })
	spray.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.1), NumberSequenceKeypoint.new(1, 1) })
	spray.EmissionDirection = Enum.NormalId.Top
	spray.Parent = top
	for i = 1, 6 do -- a ring of small lamps round the rim
		local angle = i / 6 * math.pi * 2
		ball(ctx, parent, Vector3.new(math.cos(angle) * 6.2, 1.6, math.sin(angle) * 6.2), 0.9, ctx.accent, true)
	end
end

function builders.carousel(ctx, parent)
	post(ctx, parent, Vector3.new(0, 0.4, 0), 0.8, 14, WHITE)
	local ride = mover(ctx, parent, "ParkSpin", Vector3.new(0, 0, 0), { SpinSpeed = 0.7, SpinAxis = "Y" })
	post(ctx, ride, Vector3.new(0, 1, 0), 0.5, 13, ctx.primary)
	post(ctx, ride, Vector3.new(0, 4.5, 0), 7, 1.2, WHITE)
	for i = 0, 5 do
		local angle = i / 6 * math.pi * 2
		local x, z = math.cos(angle) * 4.6, math.sin(angle) * 4.6
		post(ctx, ride, Vector3.new(x, 3.2, z), 4.6, 0.3, ctx.accent, true)
		-- the horse: a body, a head and a mane
		box(ctx, ride, Vector3.new(x, 3 + (i % 2) * 0.6, z), Vector3.new(0.9, 1.1, 1.8), WHITE)
		box(ctx, ride, Vector3.new(x, 4.1 + (i % 2) * 0.6, z - 0.9), Vector3.new(0.6, 1.1, 0.7), WHITE)
		box(ctx, ride, Vector3.new(x, 4.3 + (i % 2) * 0.6, z), Vector3.new(0.3, 0.9, 1.6), ctx.accent, true)
	end
	post(ctx, ride, Vector3.new(0, 6.4, 0), 0.5, 14, ctx.accent)
	post(ctx, ride, Vector3.new(0, 7.2, 0), 1.2, 9, ctx.primary)
	post(ctx, ride, Vector3.new(0, 8.2, 0), 1, 5, WHITE)
	ball(ctx, ride, Vector3.new(0, 9.2, 0), 1.4, ctx.accent, true)
	light(ride:FindFirstChildWhichIsA("Part") :: Instance, ctx.primary, 1.2, 16)
end

function builders.teacups(ctx, parent)
	post(ctx, parent, Vector3.new(0, 0.3, 0), 0.6, 14, WHITE)
	local floor = parent -- the cups spin on the spot (nested movers would fight over their positions)
	post(ctx, floor, Vector3.new(0, 0.8, 0), 0.4, 13, ctx.primary)
	for i = 0, 2 do
		local angle = i / 3 * math.pi * 2
		local x, z = math.cos(angle) * 3.8, math.sin(angle) * 3.8
		local cup = mover(ctx, floor, "ParkSpin", Vector3.new(x, 0, z), { SpinSpeed = 1.6, SpinAxis = "Y" })
		post(ctx, cup, Vector3.new(x, 1.5, z), 1.8, 3.4, if i == 0 then ctx.accent else ctx.primary)
		post(ctx, cup, Vector3.new(x, 2.5, z), 0.5, 3, WHITE)
		post(ctx, cup, Vector3.new(x, 2.7, z), 0.2, 2.6, Color3.fromRGB(255, 220, 150), true)
		box(ctx, cup, Vector3.new(x + 1.9, 1.6, z), Vector3.new(0.4, 0.4, 1.2), ctx.accent)
	end
	post(ctx, parent, Vector3.new(0, 3, 0), 5, 1, WHITE)
	ball(ctx, parent, Vector3.new(0, 5.8, 0), 2, ctx.accent, true)
end

function builders.ferris(ctx, parent)
	-- two legs and the axle
	for _, side in { -1, 1 } do
		rod(ctx, parent, Vector3.new(side * 5, 0.5, 0), Vector3.new(side * 0.7, 11.5, 0), 0.9, WHITE)
		box(ctx, parent, Vector3.new(side * 5, 0.5, 0), Vector3.new(2.4, 1, 5), ctx.primary)
	end
	box(ctx, parent, Vector3.new(0, 11.5, 0), Vector3.new(6.5, 1, 1), ctx.accent)
	local wheel = mover(ctx, parent, "ParkSpin", Vector3.new(0, 11.5, 0), { SpinSpeed = 0.3, SpinAxis = "Z" })
	local count = 12
	local function rimPoint(i: number): Vector3
		local angle = i / count * math.pi * 2
		return Vector3.new(math.cos(angle) * 8.5, 11.5 + math.sin(angle) * 8.5, 0)
	end
	for i = 0, count - 1 do
		local point = rimPoint(i)
		rod(ctx, wheel, point, rimPoint(i + 1), 0.5, ctx.primary)
		rod(ctx, wheel, Vector3.new(0, 11.5, 0), point, 0.25, WHITE)
		ball(ctx, wheel, point - Vector3.new(0, 0.9, 0), 2, if i % 2 == 0 then ctx.accent else ctx.primary, true)
	end
	ball(ctx, wheel, Vector3.new(0, 11.5, 0), 2.2, WHITE, true)
end

function builders.stage(ctx, parent)
	box(ctx, parent, Vector3.new(0, 0.8, 0), Vector3.new(15, 1.6, 9), ctx.primary)
	box(ctx, parent, Vector3.new(0, 0.4, -4.6), Vector3.new(15.5, 0.5, 0.5), ctx.accent, true)
	box(ctx, parent, Vector3.new(0, 5.5, 4), Vector3.new(15, 8, 0.8), DARK)
	for _, x in { -7.2, 7.2 } do
		box(ctx, parent, Vector3.new(x, 5.2, 3), Vector3.new(0.7, 10.5, 0.7), WHITE)
		box(ctx, parent, Vector3.new(x * 0.7, 2.6, 0), Vector3.new(2.2, 3.4, 2), DARK) -- a speaker
		ball(ctx, parent, Vector3.new(x * 0.7, 3.2, -1.1), 1.2, ctx.accent, true)
	end
	box(ctx, parent, Vector3.new(0, 10.4, 3), Vector3.new(15, 0.7, 0.7), WHITE)
	for i = 0, 2 do
		local x = (i - 1) * 4.5
		box(
			ctx,
			parent,
			Vector3.new(x, 5.5, 3.5),
			Vector3.new(3.4, 4.5, 0.3),
			if i == 1 then ctx.accent else ctx.primary,
			true
		)
	end
	-- lasers: thin neon bars that fan back and forth
	local lasers =
		mover(ctx, parent, "ParkSwing", Vector3.new(0, 10, 2), { SwingAngle = 0.35, SwingSpeed = 1.4, SwingPhase = 0 })
	for i = -2, 2 do
		rod(ctx, lasers, Vector3.new(i * 2.2, 10, 2), Vector3.new(i * 5, 15, -10), 0.18, ctx.accent, true)
	end
	light(parent:FindFirstChildWhichIsA("Part") :: Instance, ctx.accent, 1.5, 22)
end

function builders.fireworks(ctx, parent)
	post(ctx, parent, Vector3.new(0, 0.6, 0), 1.2, 7, ctx.primary)
	post(ctx, parent, Vector3.new(0, 4, 0), 6, 2.2, WHITE)
	post(ctx, parent, Vector3.new(0, 7.4, 0), 1, 3.2, ctx.accent, true)
	for i = 0, 3 do
		local angle = i / 4 * math.pi * 2
		box(
			ctx,
			parent,
			Vector3.new(math.cos(angle) * 1.8, 1.6, math.sin(angle) * 1.8),
			Vector3.new(0.5, 2.6, 0.5),
			ctx.accent
		)
	end
	local top = part(ctx, parent, { Transparency = 1, Size = Vector3.new(1, 1, 1) }, Vector3.new(0, 8, 0))
	for _, color in { ctx.primary, ctx.accent, WHITE } do
		local sparks = Instance.new("ParticleEmitter")
		sparks.Color = ColorSequence.new(color)
		sparks.LightEmission = 1
		sparks.Rate = 14
		sparks.Lifetime = NumberRange.new(1.4, 2.2)
		sparks.Speed = NumberRange.new(16, 26)
		sparks.SpreadAngle = Vector2.new(35, 35)
		sparks.Acceleration = Vector3.new(0, -14, 0)
		sparks.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.7), NumberSequenceKeypoint.new(1, 0) })
		sparks.EmissionDirection = Enum.NormalId.Top
		sparks.Parent = top
	end
	light(top, ctx.accent, 1.5, 20)
end

function builders.swing(ctx, parent)
	cloudBase(ctx, parent, 12)
	for _, x in { -7, 7 } do
		box(ctx, parent, Vector3.new(x, 6, 0), Vector3.new(1, 13, 1), WHITE)
		ball(ctx, parent, Vector3.new(x, 12.8, 0), 1.6, ctx.accent, true)
	end
	box(ctx, parent, Vector3.new(0, 12.5, 0), Vector3.new(15, 0.8, 0.8), ctx.primary)
	for i = 0, 3 do
		local x = (i - 1.5) * 3.2
		local seat = mover(
			ctx,
			parent,
			"ParkSwing",
			Vector3.new(x, 12.5, 0),
			{ SwingAngle = 0.75, SwingSpeed = 1.7, SwingPhase = i * 0.7 }
		)
		box(ctx, seat, Vector3.new(x - 0.6, 6.5, 0), Vector3.new(0.12, 11.5, 0.12), WHITE)
		box(ctx, seat, Vector3.new(x + 0.6, 6.5, 0), Vector3.new(0.12, 11.5, 0.12), WHITE)
		box(
			ctx,
			seat,
			Vector3.new(x, 0.9, 0),
			Vector3.new(2, 0.4, 1.4),
			if i % 2 == 0 then ctx.accent else ctx.primary,
			true
		)
	end
end

function builders.coaster(ctx, parent)
	cloudBase(ctx, parent, 13)
	-- a vertical loop standing on the clouds, with a cart racing round it
	local count = 28
	local radius = 8
	local centerY = radius + 3
	local function loopPoint(i: number): Vector3
		local angle = i / count * math.pi * 2
		return Vector3.new(0, centerY + math.sin(angle) * radius, math.cos(angle) * radius)
	end
	for i = 0, count - 1 do
		rod(ctx, parent, loopPoint(i), loopPoint(i + 1), 0.7, ctx.primary)
		if i % 4 == 0 and loopPoint(i).Y > 2 then
			local top = loopPoint(i)
			rod(ctx, parent, Vector3.new(0, 0, top.Z), top, 0.35, WHITE)
		end
	end
	rod(ctx, parent, Vector3.new(0, 1, radius), Vector3.new(0, 1, radius + 9), 0.8, ctx.accent, true) -- the approach
	local cart = mover(ctx, parent, "ParkSpin", Vector3.new(0, centerY, 0), { SpinSpeed = 1.1, SpinAxis = "X" })
	box(ctx, cart, Vector3.new(0, centerY + radius + 0.9, 0), Vector3.new(1.8, 1.2, 2.6), ctx.accent, true)
	box(ctx, cart, Vector3.new(0, centerY + radius + 1.7, 0), Vector3.new(1.4, 0.6, 1.6), WHITE)
	box(ctx, cart, Vector3.new(0, centerY + radius + 0.9, 3), Vector3.new(1.6, 1, 2.2), ctx.primary, true)
end

function builders.balloons(ctx, parent)
	cloudBase(ctx, parent, 7)
	local cluster =
		mover(ctx, parent, "ParkBob", Vector3.new(0, 0, 0), { BobAmount = 1.2, BobSpeed = 0.9, BobPhase = ctx.seed })
	local colors = { ctx.primary, ctx.accent, WHITE, ctx.primary, ctx.accent, WHITE, ctx.primary }
	for i, color in colors do
		local angle = i / #colors * math.pi * 2
		local x, z = math.cos(angle) * 3.2, math.sin(angle) * 3.2
		local y = 11 + (i % 3) * 1.6
		ball(ctx, cluster, Vector3.new(x, y, z), 5.4, color, true)
		rod(ctx, cluster, Vector3.new(0, 0.5, 0), Vector3.new(x, y - 2.7, z), 0.12, WHITE)
	end
end

function builders.lanterns(ctx, parent)
	cloudBase(ctx, parent, 10)
	for _, x in { -9, 9 } do
		box(ctx, parent, Vector3.new(x, 6, 0), Vector3.new(0.8, 12, 0.8), WHITE)
		ball(ctx, parent, Vector3.new(x, 12.4, 0), 1.4, ctx.accent, true)
	end
	local count = 9
	for i = 0, count - 1 do
		local t = i / (count - 1)
		local x = -9 + 18 * t
		local y = 12 - math.sin(t * math.pi) * 4 -- the garland sags in the middle
		local lantern =
			mover(ctx, parent, "ParkBob", Vector3.new(x, y, 0), { BobAmount = 0.5, BobSpeed = 1.3, BobPhase = i * 0.6 })
		post(ctx, lantern, Vector3.new(x, y - 1.2, 0), 2, 1.9, if i % 2 == 0 then ctx.primary else ctx.accent, true)
		post(ctx, lantern, Vector3.new(x, y - 0.1, 0), 0.3, 1.2, WHITE)
		box(ctx, lantern, Vector3.new(x, y + 0.5, 0), Vector3.new(0.1, 1, 0.1), WHITE)
	end
	box(ctx, parent, Vector3.new(0, 11.6, 0), Vector3.new(18, 0.12, 0.12), WHITE)
end

function builders.pirate(ctx, parent)
	post(ctx, parent, Vector3.new(0, 0.4, 0), 0.8, 15, WHITE)
	-- two A-frames hold the axle the ship swings from
	for _, x in { -4, 4 } do
		rod(ctx, parent, Vector3.new(x, 0.8, -4), Vector3.new(x, 10, 0), 0.7, WHITE)
		rod(ctx, parent, Vector3.new(x, 0.8, 4), Vector3.new(x, 10, 0), 0.7, WHITE)
	end
	box(ctx, parent, Vector3.new(0, 10, 0), Vector3.new(9, 0.8, 0.8), ctx.accent, true)
	local ship =
		mover(ctx, parent, "ParkSwing", Vector3.new(0, 10, 0), { SwingAngle = 0.7, SwingSpeed = 1.1, SwingPhase = 0 })
	for _, x in { -2, 2 } do
		box(ctx, ship, Vector3.new(x, 5.8, 0), Vector3.new(0.2, 8.4, 0.2), WHITE)
	end
	box(ctx, ship, Vector3.new(0, 1.6, 0), Vector3.new(5, 1.6, 12), ctx.primary) -- the hull
	box(ctx, ship, Vector3.new(0, 1.0, 0), Vector3.new(5.4, 0.4, 12.4), WHITE)
	box(ctx, ship, Vector3.new(0, 2.6, -6.4), Vector3.new(4, 1.8, 1.4), ctx.primary) -- the bow and the stern, raised
	box(ctx, ship, Vector3.new(0, 2.6, 6.4), Vector3.new(4, 1.8, 1.4), ctx.primary)
	box(ctx, ship, Vector3.new(0, 3.1, 0), Vector3.new(5.2, 0.3, 12), ctx.accent, true) -- the rail
	post(ctx, ship, Vector3.new(0, 5.2, 0), 6.5, 0.5, DARK) -- the mast
	box(ctx, ship, Vector3.new(0, 6, 0), Vector3.new(0.2, 3.6, 3.4), WHITE) -- the sail
	box(ctx, ship, Vector3.new(0, 8.6, 0), Vector3.new(0.2, 0.9, 1.4), ctx.accent, true)
end

function builders.droptower(ctx, parent)
	post(ctx, parent, Vector3.new(0, 0.4, 0), 0.8, 11, ctx.primary)
	post(ctx, parent, Vector3.new(0, 9, 0), 17, 2.2, WHITE)
	for i = 0, 3 do
		post(ctx, parent, Vector3.new(0, 3 + i * 4.4, 0), 0.5, 3, if i % 2 == 0 then ctx.accent else ctx.primary, true)
	end
	post(ctx, parent, Vector3.new(0, 18.2, 0), 1, 4, ctx.accent)
	ball(ctx, parent, Vector3.new(0, 19.6, 0), 2, ctx.accent, true)
	-- the gondola ring rises and falls on the tower
	local ring =
		mover(ctx, parent, "ParkBob", Vector3.new(0, 9, 0), { BobAmount = 5, BobSpeed = 0.8, BobPhase = ctx.seed })
	post(ctx, ring, Vector3.new(0, 9, 0), 1, 6, ctx.primary)
	post(ctx, ring, Vector3.new(0, 9.7, 0), 0.3, 6.6, WHITE)
	for i = 0, 3 do
		local angle = i / 4 * math.pi * 2
		box(
			ctx,
			ring,
			Vector3.new(math.cos(angle) * 3.4, 8.3, math.sin(angle) * 3.4),
			Vector3.new(1.4, 1.4, 1.4),
			ctx.accent,
			true
		)
	end
	light(parent:FindFirstChildWhichIsA("Part") :: Instance, ctx.accent, 1.2, 18)
end

function builders.rockets(ctx, parent)
	post(ctx, parent, Vector3.new(0, 0.4, 0), 0.8, 14, WHITE)
	post(ctx, parent, Vector3.new(0, 4.5, 0), 8, 1.4, ctx.primary)
	local ride = mover(ctx, parent, "ParkSpin", Vector3.new(0, 0, 0), { SpinSpeed = 1, SpinAxis = "Y" })
	post(ctx, ride, Vector3.new(0, 8.4, 0), 0.8, 3, ctx.accent, true)
	for i = 0, 3 do
		local angle = i / 4 * math.pi * 2
		local x, z = math.cos(angle) * 5.2, math.sin(angle) * 5.2
		local rocket = Vector3.new(x, 5.4, z)
		rod(ctx, ride, Vector3.new(0, 8.4, 0), rocket + Vector3.new(0, 1.2, 0), 0.25, WHITE)
		post(ctx, ride, rocket, 3, 1.3, if i % 2 == 0 then ctx.primary else WHITE) -- the body
		ball(ctx, ride, rocket + Vector3.new(0, 1.9, 0), 1.3, ctx.accent, true) -- the nose
		ball(ctx, ride, rocket + Vector3.new(0, 0.2, 0), 0.7, Color3.fromRGB(150, 225, 255), true) -- the window
		for _, side in { -1, 1 } do
			box(
				ctx,
				ride,
				rocket + Vector3.new(side * 0.8 * math.cos(angle + 1.57), -1.2, side * 0.8 * math.sin(angle + 1.57)),
				Vector3.new(0.4, 1, 0.4),
				ctx.accent
			)
		end
		ball(ctx, ride, rocket + Vector3.new(0, -1.9, 0), 0.9, Color3.fromRGB(255, 200, 90), true) -- the flame
	end
	light(parent:FindFirstChildWhichIsA("Part") :: Instance, ctx.primary, 1.2, 16)
end

function builders.candy(ctx, parent)
	box(ctx, parent, Vector3.new(0, 0.3, 0), Vector3.new(11, 0.6, 7), WHITE) -- the floor
	box(ctx, parent, Vector3.new(0, 1.8, -1.5), Vector3.new(9, 2.4, 2), ctx.primary) -- the counter
	box(ctx, parent, Vector3.new(0, 3.1, -1.5), Vector3.new(9.4, 0.3, 2.4), WHITE)
	for _, x in { -4.4, 4.4 } do
		box(ctx, parent, Vector3.new(x, 4.5, 2.2), Vector3.new(0.5, 8.4, 0.5), WHITE)
	end
	box(ctx, parent, Vector3.new(0, 4, 2.7), Vector3.new(9, 6, 0.4), ctx.accent) -- the back wall
	-- a striped awning
	for i = 0, 5 do
		local x = (i - 2.5) * 1.6
		part(ctx, parent, {
			Size = Vector3.new(1.6, 0.35, 6.6),
			Color = if i % 2 == 0 then ctx.accent else WHITE,
		}, Vector3.new(x, 8.6, 0.6), CFrame.Angles(math.rad(-12), 0, 0))
	end
	-- jars of sweets on the counter
	for i = 0, 3 do
		ball(
			ctx,
			parent,
			Vector3.new((i - 1.5) * 2, 4.2, -1.5),
			1.6,
			if i % 2 == 0 then ctx.accent else ctx.primary,
			true
		)
	end
	-- a big lollipop that turns
	local sign = mover(ctx, parent, "ParkSpin", Vector3.new(6.8, 0, 0), { SpinSpeed = 1.2, SpinAxis = "Y" })
	post(ctx, sign, Vector3.new(6.8, 2.5, 0), 5, 0.4, WHITE)
	post(ctx, sign, Vector3.new(6.8, 6, 0), 0.5, 3.6, ctx.accent, true)
	post(ctx, sign, Vector3.new(6.8, 6.1, 0), 0.5, 2.2, WHITE)
	post(ctx, sign, Vector3.new(6.8, 6.2, 0), 0.5, 0.9, ctx.primary, true)
	light(parent:FindFirstChildWhichIsA("Part") :: Instance, ctx.accent, 1, 14)
end

function builders.hotair(ctx, parent)
	cloudBase(ctx, parent, 8)
	local balloon =
		mover(ctx, parent, "ParkBob", Vector3.new(0, 0, 0), { BobAmount = 1.5, BobSpeed = 0.7, BobPhase = ctx.seed })
	ball(ctx, balloon, Vector3.new(0, 13, 0), 11, ctx.primary)
	ball(ctx, balloon, Vector3.new(0, 13, 0), 11.4, ctx.accent, true).Transparency = 0.55
	for i = 0, 3 do -- stripes down the sides
		local angle = i / 4 * math.pi * 2
		box(
			ctx,
			balloon,
			Vector3.new(math.cos(angle) * 5.3, 13, math.sin(angle) * 5.3),
			Vector3.new(0.4, 8, 0.4),
			WHITE
		)
	end
	ball(ctx, balloon, Vector3.new(0, 7.6, 0), 3.2, ctx.primary) -- the skirt
	box(ctx, balloon, Vector3.new(0, 2.4, 0), Vector3.new(3, 1.6, 3), Color3.fromRGB(190, 140, 90)) -- the basket
	box(ctx, balloon, Vector3.new(0, 3.3, 0), Vector3.new(3.2, 0.3, 3.2), WHITE)
	for _, x in { -1.2, 1.2 } do
		for _, z in { -1.2, 1.2 } do
			rod(ctx, balloon, Vector3.new(x, 3.2, z), Vector3.new(x * 0.5, 8, z * 0.5), 0.12, WHITE)
		end
	end
	light(balloon:FindFirstChildWhichIsA("Part") :: Instance, ctx.primary, 1.2, 16)
end

function builders.stars(ctx, parent)
	cloudBase(ctx, parent, 8)
	post(ctx, parent, Vector3.new(0, 7.5, 0), 15, 0.7, WHITE)
	ball(ctx, parent, Vector3.new(0, 15.2, 0), 1.6, ctx.accent, true)
	local mobile = mover(ctx, parent, "ParkSpin", Vector3.new(0, 14, 0), { SpinSpeed = 0.5, SpinAxis = "Y" })
	for i = 0, 4 do
		local angle = i / 5 * math.pi * 2 + ctx.seed
		local x, z = math.cos(angle) * 5.5, math.sin(angle) * 5.5
		local y = 8 + (i % 3) * 1.6
		rod(ctx, mobile, Vector3.new(0, 14, 0), Vector3.new(x, y + 2.2, z), 0.12, WHITE)
		local color = if i % 2 == 0 then ctx.accent else ctx.primary
		for _, turn in { 0, 60, 120 } do -- a star: three bars crossing
			part(
				ctx,
				mobile,
				{ Size = Vector3.new(0.5, 3.6, 0.5), Color = color, Material = Enum.Material.Neon },
				Vector3.new(x, y, z),
				CFrame.Angles(0, 0, math.rad(turn))
			)
		end
		ball(ctx, mobile, Vector3.new(x, y, z), 1.2, WHITE, true)
	end
end

function builders.cranes(ctx, parent)
	cloudBase(ctx, parent, 9)
	for _, x in { -9, 9 } do
		box(ctx, parent, Vector3.new(x, 7, 0), Vector3.new(0.7, 14, 0.7), WHITE)
		ball(ctx, parent, Vector3.new(x, 14.2, 0), 1.3, ctx.accent, true)
	end
	box(ctx, parent, Vector3.new(0, 13.6, 0), Vector3.new(18, 0.12, 0.12), WHITE)
	for i = 0, 4 do
		local x = -7 + i * 3.5
		local y = 8.5 + (i % 2) * 1.2
		local crane =
			mover(ctx, parent, "ParkBob", Vector3.new(x, y, 0), { BobAmount = 0.7, BobSpeed = 1.1, BobPhase = i * 0.9 })
		local color = if i % 3 == 0 then ctx.accent elseif i % 3 == 1 then ctx.primary else WHITE
		rod(ctx, crane, Vector3.new(x, 13.6, 0), Vector3.new(x, y + 0.6, 0), 0.08, WHITE)
		box(ctx, crane, Vector3.new(x, y, 0), Vector3.new(0.7, 0.7, 2.4), color, true) -- the body
		box(ctx, crane, Vector3.new(x, y + 0.5, -1.5), Vector3.new(0.3, 0.9, 0.3), color, true) -- the neck
		for _, side in { -1, 1 } do
			part(
				ctx,
				crane,
				{ Size = Vector3.new(2.6, 0.12, 1.8), Color = color },
				Vector3.new(x + side * 1.2, y + 0.5, 0),
				CFrame.Angles(0, 0, side * math.rad(-22))
			)
		end
	end
end

-- Placing --------------------------------------------------------------------------------------------------------

local built: { [Player]: { signature: string, folder: Folder } } = {}

-- Where a lot is in the world: on the territory's centre line, facing the plots (the hub).
local function lotCFrame(base: Vector3, slot: number, lotId: string, groundY: (number, number) -> number): CFrame?
	local place = LOT_PLACE[lotId]
	if not place then
		return nil
	end
	local angle = ((slot - 1) % Plots.Slots) / Plots.Slots * math.pi * 2
	local out = Vector3.new(math.cos(angle), 0, math.sin(angle))
	local side = Vector3.new(-math.sin(angle), 0, math.cos(angle))
	local flat = base + out * place.radial + side * place.tangent
	local position = Vector3.new(flat.X, groundY(flat.X, flat.Z) + place.height, flat.Z)
	return CFrame.lookAt(position, position - out)
end

local function paletteColors(palette: string, seed: number): (Color3, Color3, boolean)
	if palette == "Rainbow" then
		return Color3.fromHSV((seed * 0.13) % 1, 0.7, 1), Color3.fromHSV((seed * 0.13 + 0.5) % 1, 0.7, 1), true
	end
	local order = Palette.LaneOrder
	local index = table.find(order, palette) or 1
	return Palette.hue(palette, "Night"), Palette.hue(order[index % #order + 1], "Night"), false
end

-- Draws exactly what the player has placed. It only rebuilds when something changed.
function ParkBuilder.sync(
	container: Instance,
	player: Player,
	slot: number,
	state: Park.State,
	level: number,
	base: Vector3,
	groundY: (number, number) -> number
)
	local entries: { string } = {}
	for _, lot in Park.Lots do
		local key = state.placed[lot.id]
		if key and level >= lot.level then
			table.insert(entries, `{lot.id}={key}`)
		end
	end
	local signature = table.concat(entries, ";")
	local current = built[player]
	if current and current.signature == signature then
		return
	end
	if current then
		current.folder:Destroy()
	end
	local folder = Instance.new("Folder")
	folder.Name = `Park_{player.UserId}`
	folder:SetAttribute("OwnerUserId", player.UserId)
	folder.Parent = container
	built[player] = { signature = signature, folder = folder }

	for index, lot in Park.Lots do
		local key = state.placed[lot.id]
		if not key or level < lot.level then
			continue
		end
		local attraction, palette = Park.parseKey(key)
		local cf = lotCFrame(base, slot, lot.id, groundY)
		local build = if attraction then builders[attraction.id] else nil
		if attraction and palette and cf and build then
			local group = Instance.new("Folder")
			group.Name = `{lot.id}_{attraction.id}`
			group.Parent = folder
			local primary, accent, rainbow = paletteColors(palette, index + slot)
			build(
				{ folder = group, cf = cf, primary = primary, accent = accent, rainbow = rainbow, seed = index },
				group
			)
		end
	end
end

function ParkBuilder.remove(player: Player)
	local current = built[player]
	if current then
		current.folder:Destroy()
		built[player] = nil
	end
end

return ParkBuilder
