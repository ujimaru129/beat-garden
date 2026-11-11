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
		size = 0.9,
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
		size = 4.2,
		color = function(look)
			return look.color
		end,
	},
}
local STEM_HEIGHT: { [string]: number } = { Seed = 0, Sprout = 2, Sapling = 4.5, Bloom = 7, Fruit = 6 }

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
	local coreCenter = ground + Vector3.new(0, stemHeight + coreSize / 2, 0)
	if stage == "Seed" then
		coreCenter = ground + Vector3.new(0, coreSize / 2, 0)
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

	local key = `{seedId}|{stage}|{stars}|{mutation or ""}`
	if folder:GetAttribute("LookKey") == key then
		return
	end
	folder:ClearAllChildren()
	folder:SetAttribute("LookKey", key)

	local s = scale
	-- stem
	if stemHeight > 0 then
		local width = (if stage == "Sprout" then 0.25 elseif stage == "Fruit" then 0.8 else 0.45) * s
		part(
			folder,
			Vector3.new(width, width, stemHeight),
			CFrame.lookAt(ground + Vector3.new(0, stemHeight / 2, 0), ground + Vector3.new(0, stemHeight, 0)),
			STEM
		)
	end
	-- leaves: pairs along the stem
	local leafPairs = if stage == "Sprout" then 1 elseif stage == "Sapling" then 2 else 3
	if stage ~= "Seed" then
		for i = 1, leafPairs do
			local y = stemHeight * (0.3 + 0.28 * (i - 1)) + 0.2 * s
			local leafSize = (if stage == "Sprout" then 0.9 else 1.5) * s
			for side = -1, 1, 2 do
				local pos = ground + Vector3.new(side * leafSize * 0.55, y, (i % 2 == 0 and 0.2 or -0.2) * s)
				ellipsoid(
					folder,
					Vector3.new(leafSize, leafSize * 0.22, leafSize * 0.55),
					CFrame.new(pos) * CFrame.Angles(0, 0, side * math.rad(-22)),
					LEAF
				)
			end
		end
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
		if look.style == "petal" then
			-- a little leaf cap on top
			for i = 1, 3 do
				local angle = (i - 1) / 3 * math.pi * 2 + 0.5
				ellipsoid(
					folder,
					Vector3.new(1.4 * s, 0.25 * s, 0.7 * s),
					CFrame.new(
						coreCenter + Vector3.new(math.cos(angle) * r * 0.45, r * 0.92, math.sin(angle) * r * 0.45)
					) * CFrame.Angles(0, -angle, math.rad(15)),
					look.accent
				)
			end
		elseif look.style == "leaf" then
			for i = 1, c do
				local angle = (i - 1) / c * math.pi * 2
				ellipsoid(
					folder,
					Vector3.new(2.2 * s, 0.3 * s, 0.8 * s),
					CFrame.new(
						coreCenter + Vector3.new(math.cos(angle) * r * 1.05, -r * 0.3, math.sin(angle) * r * 1.05)
					) * CFrame.Angles(0, -angle, math.rad(25)),
					look.accent
				)
			end
		elseif look.style == "bubble" then
			for i = 1, c do
				local angle = (i - 1) / c * math.pi * 2
				local b = (0.5 + 0.2 * (i % 3)) * s
				ellipsoid(
					folder,
					Vector3.new(b, b, b),
					CFrame.new(
						coreCenter
							+ Vector3.new(
								math.cos(angle) * r * 1.25,
								r * (0.3 + 0.25 * (i % 3)),
								math.sin(angle) * r * 1.25
							)
					),
					look.accent
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
			for i = 1, c do
				local angle = (i - 1) / c * math.pi * 2
				local dir = Vector3.new(math.cos(angle) * 0.8, 0.6, math.sin(angle) * 0.8)
				rod(folder, coreCenter + dir * r * 0.8, coreCenter + dir * r * 1.7, 0.4 * s, look.accent)
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
