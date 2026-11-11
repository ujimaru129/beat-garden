--!strict
-- What a plant looks like at each growth stage, built from simple parts (balls, ellipsoids, rods) so it needs no
-- 3D files. Every seed has its own colour and a "style" of flower / fruit; a real mesh can replace a seed's look
-- later without touching the growth code.
--
-- The `Plant` part (the soil's child that the client lights up at night) is the core: the bud, the flower's
-- centre and finally the fruit. Everything else lives in a `PlantParts` folder that is rebuilt only when the
-- look changes (seed, stage or mastery stars).

local Palette = require(game:GetService("ReplicatedStorage").Shared.Palette)

local PlantLook = {}

type Style = "petal" | "leaf" | "bubble" | "cloud" | "spike" | "burst"

type Look = {
	color: Color3, -- petals and fruit
	accent: Color3, -- tips, caps and sparkles
	style: Style,
	count: number, -- petals, leaves, bubbles, spikes ...
}

local function hex(h: string): Color3
	return Color3.fromHex(h)
end

local LOOKS: { [string]: Look } = {
	seed_sakura = { color = hex("#FF9EC4"), accent = hex("#FFFFFF"), style = "petal", count = 5 },
	seed_yuzu = { color = hex("#FFD84D"), accent = hex("#7ED957"), style = "petal", count = 6 },
	seed_ramune = { color = hex("#7FD8FF"), accent = hex("#FFFFFF"), style = "bubble", count = 5 },
	seed_matcha = { color = hex("#6FCB7A"), accent = hex("#2E8B57"), style = "leaf", count = 4 },
	seed_momo = { color = hex("#FFB3A7"), accent = hex("#7ED957"), style = "petal", count = 5 },
	seed_sora = { color = hex("#BFE3FF"), accent = hex("#FFFFFF"), style = "cloud", count = 4 },
	seed_fuji = { color = hex("#B07CFF"), accent = hex("#E4D4FF"), style = "spike", count = 8 },
	seed_ichigo = { color = hex("#FF5C7A"), accent = hex("#7ED957"), style = "petal", count = 6 },
	seed_budo = { color = hex("#9B6BFF"), accent = hex("#7ED957"), style = "bubble", count = 7 },
	seed_kiwi = { color = hex("#9BD84A"), accent = hex("#5A3A22"), style = "leaf", count = 5 },
	seed_sumire = { color = hex("#C89BFF"), accent = hex("#FFFFFF"), style = "petal", count = 5 },
	seed_taiyo = { color = hex("#FFA62B"), accent = hex("#FFE14D"), style = "burst", count = 14 },
	seed_niji = { color = hex("#FF9EC4"), accent = hex("#3FC8FF"), style = "burst", count = 16 },
	seed_hanabi = { color = hex("#FF4FA3"), accent = hex("#FFE14D"), style = "burst", count = 12 },
}
local DEFAULT_LOOK: Look = { color = hex("#FFD84D"), accent = hex("#FFFFFF"), style = "petal", count = 5 }

local STEM = hex("#5FBF6A")
local LEAF = hex("#7ED957")
local GOLD = hex("#FFE14D")
local OVERRIPE = hex("#1A1410") -- an overripe fruit darkens: its own colour mixed with black

-- Size of the core part and how far up its centre is, per stage (before the plot scale).
local CORE: { [string]: { size: number, color: (Look) -> Color3 } } = {
	Seed = {
		size = 0.8,
		color = function(_)
			return Palette.Base.Sumi
		end,
	},
	Sprout = {
		size = 0.6,
		color = function(look)
			return look.color
		end,
	},
	Sapling = {
		size = 1.5,
		color = function(look)
			return look.color
		end,
	},
	Bloom = {
		size = 1.7,
		color = function(_)
			return GOLD
		end,
	},
	Fruit = {
		size = 3,
		color = function(look)
			return look.color
		end,
	},
}
local STEM_HEIGHT: { [string]: number } = { Seed = 0, Sprout = 2.2, Sapling = 4.4, Bloom = 6.6, Fruit = 5.6 }
local SOIL = hex("#5B3E2B")
local LOOK_VERSION = 4 -- bump when the shapes change, so plants already in the world are redrawn

local function part(folder: Instance, size: Vector3, cframe: CFrame, color: Color3, neon: boolean?): Part
	local p = Instance.new("Part")
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.Material = if neon then Enum.Material.Neon else Enum.Material.SmoothPlastic
	p.Color = color
	p.Size = size
	p.CFrame = cframe
	p.Parent = folder
	return p
end

local function ellipsoid(folder: Instance, size: Vector3, cframe: CFrame, color: Color3, neon: boolean?): Part
	local p = part(folder, size, cframe, color, neon)
	local mesh = Instance.new("SpecialMesh")
	mesh.MeshType = Enum.MeshType.Sphere
	mesh.Parent = p
	return p
end

-- A thin rod from `from` to `to`.
local function rod(folder: Instance, from: Vector3, to: Vector3, width: number, color: Color3, neon: boolean?): Part
	local length = (to - from).Magnitude
	return part(folder, Vector3.new(width, width, length), CFrame.lookAt((from + to) / 2, to), color, neon)
end

-- A small number from the seed's name: every kind leans and turns its leaves its own way.
local function hashOf(seedId: string): number
	local h = 0
	for i = 1, #seedId do
		h = (h * 31 + string.byte(seedId, i)) % 100003
	end
	return h
end

-- How far the top of the stem leans away from straight up (horizontal offset), so a plant is not a ruler.
local function leanOf(seedId: string, height: number): Vector3
	local h = hashOf(seedId)
	local angle = math.rad((h * 37) % 360)
	local amount = (0.05 + (h % 7) / 100) * height
	return Vector3.new(math.cos(angle) * amount, 0, math.sin(angle) * amount)
end

-- A point on the stem: t = 0 at the soil, 1 at the top. The lean grows towards the top, like a stem bending.
local function stemPoint(ground: Vector3, lean: Vector3, height: number, t: number): Vector3
	return ground + Vector3.new(lean.X * t * t, height * t, lean.Z * t * t)
end

function PlantLook.clear(folder: Instance)
	folder:ClearAllChildren()
	folder:SetAttribute("LookKey", nil)
end

-- Draws the plant of `seedId` at `stage` standing on `ground` (the top centre of the soil). Sets the core part.
-- `scale` is the plot scale; `stars` (0..5) are the seed's mastery stars.
function PlantLook.apply(
	core: Part,
	folder: Instance,
	ground: Vector3,
	seedId: string,
	stage: string,
	freshness: number,
	mutation: string?,
	stars: number,
	scale: number
)
	local look = LOOKS[seedId] or DEFAULT_LOOK
	local coreDef = CORE[stage] or CORE.Seed
	local coreSize = coreDef.size * scale
	local stemHeight = (STEM_HEIGHT[stage] or 0) * scale
	local lean = leanOf(seedId, stemHeight)
	local coreCenter = ground + lean + Vector3.new(0, stemHeight + coreSize / 2, 0)
	if stage == "Seed" then
		coreCenter = ground + Vector3.new(0, coreSize / 2 + 0.1 * scale, 0)
	end

	core.Shape = Enum.PartType.Ball
	core.Size = Vector3.new(coreSize, coreSize, coreSize)
	core.Position = coreCenter
	-- an overripe fruit darkens towards black (its own colour, deeper)
	core.Color = coreDef.color(look):Lerp(OVERRIPE, (1 - freshness) * 1.5)
	core.Material = Enum.Material.SmoothPlastic
	if mutation == "Film" then
		-- faded, like an old photo
		core.Color = core.Color:Lerp(hex("#D9C7A7"), 0.75)
	elseif mutation == "Vapor" then
		core.Color = hex("#FF71CE")
		core.Material = Enum.Material.Neon
	elseif mutation == "GoldenHour" then
		core.Color = hex("#FFB347")
		core.Material = Enum.Material.Neon
	end
	core.Transparency = 0

	-- an overripe fruit gives off dark smoke, more of it the worse it gets
	local smoke = core:FindFirstChild("RotSmoke")
	if not (smoke and smoke:IsA("ParticleEmitter")) then
		local emitter = Instance.new("ParticleEmitter")
		emitter.Name = "RotSmoke"
		emitter.Texture = "rbxasset://textures/particles/smoke_main.dds"
		emitter.Color = ColorSequence.new(hex("#2A2530"))
		emitter.LightEmission = 0
		emitter.Lifetime = NumberRange.new(1.5, 2.6)
		emitter.Speed = NumberRange.new(1.5, 3)
		emitter.SpreadAngle = Vector2.new(35, 35)
		emitter.Acceleration = Vector3.new(0, 2, 0)
		emitter.Rotation = NumberRange.new(0, 360)
		emitter.RotSpeed = NumberRange.new(-30, 30)
		emitter.Rate = 0
		emitter.Enabled = false
		emitter.Parent = core
		smoke = emitter
	end
	local emitter = smoke :: ParticleEmitter
	local rot = if stage == "Fruit" then math.clamp((1 - freshness) / (1 - 0.5), 0, 1) else 0
	-- only touch the emitter when the smoke level changes (a write replicates to every player)
	local level = math.floor(rot * 10 + 0.5)
	local seen = emitter:GetAttribute("Level")
	if seen ~= level or emitter:GetAttribute("Size") ~= coreSize then
		emitter:SetAttribute("Level", level)
		emitter:SetAttribute("Size", coreSize)
		rot = level / 10
		emitter.Enabled = rot > 0
		emitter.Rate = 3 + 12 * rot
		emitter.Size = NumberSequence.new({
			NumberSequenceKeypoint.new(0, coreSize * 0.25),
			NumberSequenceKeypoint.new(1, coreSize * 0.6),
		})
		emitter.Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0.5),
			NumberSequenceKeypoint.new(1, 1),
		})
	end

	local key = `{LOOK_VERSION}|{seedId}|{stage}|{stars}|{mutation or ""}`
	if folder:GetAttribute("LookKey") == key then
		return
	end
	folder:ClearAllChildren()
	folder:SetAttribute("LookKey", key)

	local s = scale
	local seedHash = hashOf(seedId)
	local turn = (seedHash % 100) / 100 * math.pi * 2 -- where the first leaf points

	-- soil heaped round the foot of the plant (and over the seed itself)
	do
		local width = (if stage == "Seed" then 2.0 elseif stage == "Sprout" then 1.7 else 1.4) * s
		ellipsoid(folder, Vector3.new(width, 0.6 * s, width), CFrame.new(ground + Vector3.new(0, 0.05 * s, 0)), SOIL)
	end

	-- the stem: a few rods along a gently bending line, thinner towards the top
	if stemHeight > 0 then
		local segments = if stage == "Sprout" then 2 else 4
		local base = (if stage == "Sprout" then 0.3 elseif stage == "Fruit" then 0.85 else 0.55) * s
		for i = 1, segments do
			local from = stemPoint(ground, lean, stemHeight, (i - 1) / segments)
			local to = stemPoint(ground, lean, stemHeight, i / segments)
			local width = base * (1 - 0.35 * (i - 1) / segments)
			rod(folder, from - Vector3.new(0, 0.05 * s, 0), to + Vector3.new(0, 0.05 * s, 0), width, STEM)
		end
	end

	-- leaves, one by one up the stem and turned round it (lower leaves bigger, they droop; upper ones point up)
	if stage == "Sprout" then
		-- two round seed leaves, opposite each other
		local top = stemPoint(ground, lean, stemHeight, 1)
		for side = 0, 1 do
			local angle = turn + side * math.pi
			local dir = Vector3.new(math.cos(angle), 0, math.sin(angle))
			ellipsoid(
				folder,
				Vector3.new(1.15 * s, 0.16 * s, 0.8 * s),
				CFrame.new(top + dir * 0.6 * s - Vector3.new(0, 0.1 * s, 0))
					* CFrame.Angles(0, -angle, 0)
					* CFrame.Angles(0, 0, math.rad(16)),
				LEAF
			)
		end
	elseif stage ~= "Seed" then
		local count = if stage == "Sapling" then 5 elseif stage == "Bloom" then 6 else 7
		local biggest = (if stage == "Sapling" then 2.4 else 3.2) * s
		for i = 1, count do
			local t = 0.18 + 0.66 * (i - 1) / (count - 1)
			local angle = turn + i * 2.39996 -- the golden angle: leaves never line up
			local dir = Vector3.new(math.cos(angle), 0, math.sin(angle))
			local length = biggest * (1.1 - 0.5 * t)
			-- low leaves droop, high leaves reach up; each is a fat oval that is cupped a little (thick enough to
			-- show from the side)
			local pitch = math.rad(-28 + 62 * t)
			ellipsoid(
				folder,
				Vector3.new(length, 0.42 * s, length * 0.62),
				CFrame.new(stemPoint(ground, lean, stemHeight, t) + dir * length * 0.48)
					* CFrame.Angles(0, -angle, 0)
					* CFrame.Angles(0, 0, pitch),
				if i % 2 == 0 then LEAF else STEM
			)
		end
	end
	-- the bud of a sapling has a green cup of two small leaves round it
	if stage == "Sapling" then
		for side = 0, 1 do
			local angle = turn + side * math.pi
			local dir = Vector3.new(math.cos(angle), 0, math.sin(angle))
			ellipsoid(
				folder,
				Vector3.new(1.1 * s, 0.2 * s, 0.6 * s),
				CFrame.new(coreCenter - Vector3.new(0, coreSize * 0.35, 0) + dir * coreSize * 0.4)
					* CFrame.Angles(0, -angle, 0)
					* CFrame.Angles(0, 0, math.rad(50)),
				LEAF
			)
		end
	elseif stage == "Bloom" then
		-- the flower sits in a green cup
		ellipsoid(
			folder,
			Vector3.new(coreSize * 0.9, coreSize * 0.5, coreSize * 0.9),
			CFrame.new(coreCenter - Vector3.new(0, coreSize * 0.55, 0)),
			LEAF
		)
	end

	local c = look.count
	if stage == "Bloom" then
		-- the flower: petals around the golden centre
		local radius = coreSize * 0.95
		for i = 1, c do
			local angle = (i - 1) / c * math.pi * 2
			local dir = Vector3.new(math.cos(angle), 0, math.sin(angle))
			local pos = coreCenter + dir * radius
			if look.style == "spike" or look.style == "burst" then
				rod(
					folder,
					coreCenter + dir * coreSize * 0.4,
					coreCenter + dir * radius * 1.7 + Vector3.new(0, 0.6 * s, 0),
					0.22 * s,
					look.color,
					look.style == "burst"
				)
			elseif look.style == "bubble" or look.style == "cloud" then
				local b = (if look.style == "cloud" then 1.1 else 0.7) * s
				ellipsoid(folder, Vector3.new(b, b, b), CFrame.new(pos + Vector3.new(0, 0.2 * s, 0)), look.color)
			else
				local long = if look.style == "leaf" then 2.2 else 1.5
				ellipsoid(
					folder,
					Vector3.new(long * s, 0.3 * s, 0.9 * s),
					CFrame.new(pos) * CFrame.Angles(0, -angle, 0),
					look.color
				)
			end
		end
	elseif stage == "Fruit" then
		-- what makes this fruit this fruit
		local r = coreSize / 2
		-- The fruit is the heart of a flower head, which is drawn in the seed's style. Petals take the fruit's colour
		-- (mutation, overripe and all) a little lighter, so a mutated plant looks mutated all over.
		local tint = core.Color:Lerp(Color3.new(1, 1, 1), 0.3)
		local glowy = core.Material == Enum.Material.Neon
		local function petal(angle: number, length: number, width: number, pitchDeg: number, y: number, color: Color3)
			local pitch = math.rad(pitchDeg)
			local dir = Vector3.new(math.cos(angle), 0, math.sin(angle))
			local center = coreCenter
				+ Vector3.new(0, y, 0)
				+ dir * (length / 2 * math.cos(pitch))
				+ Vector3.new(0, length / 2 * math.sin(pitch), 0)
			ellipsoid(
				folder,
				Vector3.new(length, 0.5 * s, width),
				CFrame.new(center) * CFrame.Angles(0, -angle, 0) * CFrame.Angles(0, 0, pitch),
				color,
				glowy
			)
		end
		if look.style == "petal" then
			-- a layered flower: wide low petals under, upright petals in front of them
			for i = 1, 6 do
				petal((i - 1) / 6 * math.pi * 2 + 0.3, 5 * s, 2.7 * s, 18, -r * 0.35, tint)
			end
			for i = 1, 6 do
				petal((i - 1) / 6 * math.pi * 2 + math.pi / 6 + 0.3, 3.6 * s, 2.1 * s, 52, -r * 0.1, look.accent)
			end
		elseif look.style == "leaf" then
			-- a tulip: tall petals curled up into a cup round the fruit
			for i = 1, c do
				petal((i - 1) / c * math.pi * 2, 5 * s, 2.2 * s, 74, -r * 0.6, tint)
			end
			for i = 1, c do
				petal((i - 0.5) / c * math.pi * 2, 3.6 * s, 1.8 * s, 62, -r * 0.5, look.accent)
			end
		elseif look.style == "bubble" then
			-- a hydrangea: a dome of little round blossoms
			local count = 16
			for i = 1, count do
				local y = 1 - (i - 0.5) / count * 1.25 -- from the top down to a little below the middle
				local ring = math.sqrt(math.max(0, 1 - y * y))
				local angle = i * 2.39996
				local b = (0.95 + 0.4 * (i % 3)) * s
				ellipsoid(
					folder,
					Vector3.new(b, b, b),
					CFrame.new(coreCenter + Vector3.new(math.cos(angle) * ring, y, math.sin(angle) * ring) * r * 1.45),
					if i % 2 == 0 then tint else look.accent,
					glowy
				)
			end
		elseif look.style == "cloud" then
			for i = 1, c do
				local angle = (i - 1) / c * math.pi * 2
				local b = 2.2 * s
				ellipsoid(
					folder,
					Vector3.new(b, b * 0.8, b),
					CFrame.new(
						coreCenter + Vector3.new(math.cos(angle) * r * 0.85, -r * 0.25, math.sin(angle) * r * 0.85)
					),
					look.color
				)
			end
		elseif look.style == "spike" then
			-- a dandelion / chrysanthemum: many thin rods with a tip, all the way round the top half
			local count = 18
			for i = 1, count do
				local y = 0.9 - (i - 0.5) / count * 1.3
				local ring = math.sqrt(math.max(0, 1 - y * y))
				local angle = i * 2.39996
				local dir = Vector3.new(math.cos(angle) * ring, y, math.sin(angle) * ring)
				rod(folder, coreCenter + dir * r * 0.7, coreCenter + dir * r * 2.2, 0.22 * s, tint, glowy)
				ellipsoid(
					folder,
					Vector3.new(0.55, 0.55, 0.55) * s,
					CFrame.new(coreCenter + dir * r * 2.25),
					look.accent,
					glowy
				)
			end
		else -- burst: neon rods in every direction, like a firework
			for i = 1, c do
				local angle = (i - 1) / c * math.pi * 2
				local lift = if i % 2 == 0 then 0.45 else -0.15
				local dir = Vector3.new(math.cos(angle), lift, math.sin(angle)).Unit
				rod(folder, coreCenter + dir * r * 0.9, coreCenter + dir * r * 1.6, 0.22 * s, look.accent, true)
				ellipsoid(
					folder,
					Vector3.new(0.5, 0.5, 0.5) * s,
					CFrame.new(coreCenter + dir * r * 1.65),
					look.color,
					true
				)
			end
		end
	end

	-- a mutated fruit shows it: a ring of glowing beads around it
	if stage == "Fruit" and mutation and mutation ~= "Film" then
		local beads = if mutation == "GoldenHour" then 10 else 8
		local ringRadius = coreSize * 0.75
		for i = 1, beads do
			local angle = (i - 1) / beads * math.pi * 2
			local color = if mutation == "GoldenHour" then GOLD elseif i % 2 == 0 then hex("#FF71CE") else hex("#01CDFE")
			ellipsoid(
				folder,
				Vector3.new(0.55, 0.55, 0.55) * s,
				CFrame.new(
					coreCenter
						+ Vector3.new(math.cos(angle) * ringRadius, -coreSize * 0.1, math.sin(angle) * ringRadius)
				),
				color,
				true
			)
		end
	end

	-- mastery: one golden sparkle per star, circling the plant at head height
	if stage ~= "Seed" then
		for i = 1, math.clamp(stars, 0, 5) do
			local angle = (i - 1) / 5 * math.pi * 2
			local radius = coreSize * 1.3 + 1.2 * s
			ellipsoid(
				folder,
				Vector3.new(0.5, 0.5, 0.5) * s,
				CFrame.new(
					coreCenter + Vector3.new(math.cos(angle) * radius, 0.4 * s * (i % 2), math.sin(angle) * radius)
				),
				GOLD,
				true
			)
		end
	end
end

return table.freeze(PlantLook)
