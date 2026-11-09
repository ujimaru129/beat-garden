--!strict
-- The Beat Spirits as little characters ("Otodama": a round mochi body with a face, short arms and legs, and
-- always headphones; docs/character-direction.md). Built from simple parts so they need no 3D files and cost
-- almost nothing; the real modelled characters replace this later without touching the rest of the game.
--
-- `create(kind)` returns a Model whose pivot is on the ground under the character, facing -Z.

local SpiritModel = {}

local function hex(h: string): Color3
	return Color3.fromHex(h)
end

type Look = {
	body: Color3,
	cheek: Color3,
	phones: Color3, -- headphone cups
}

local LOOKS: { [string]: Look } = {
	Mochi = { body = hex("#FFEFF5"), cheek = hex("#FF9EC4"), phones = hex("#FF4FA3") },
	Kitsune = { body = hex("#FFC98A"), cheek = hex("#FF8F7A"), phones = hex("#A86BFF") },
	Pon = { body = hex("#FFE07A"), cheek = hex("#FFA24D"), phones = hex("#FFB52E") },
	Koke = { body = hex("#9ADBA0"), cheek = hex("#F4A6A0"), phones = hex("#3DAE7A") },
	Ame = { body = hex("#9ADCFF"), cheek = hex("#FF9EC4"), phones = hex("#3FA9FF") },
	Haru = { body = hex("#FFE0C2"), cheek = hex("#FF8FB8"), phones = hex("#FF6FA8") },
	Poko = { body = hex("#D2AE86"), cheek = hex("#F2A28C"), phones = hex("#8A5A33") },
	Mimi = { body = hex("#F6F0FF"), cheek = hex("#FF9EC4"), phones = hex("#B07CFF") },
	Hoshi = { body = hex("#FFEE9A"), cheek = hex("#FFB36B"), phones = hex("#FFC933") },
	Yoru = { body = hex("#7A5FC9"), cheek = hex("#C79BFF"), phones = hex("#3FC8FF") },
}
local DEFAULT_LOOK: Look = LOOKS.Mochi

local INK = hex("#2A2340")
local WHITE = Color3.new(1, 1, 1)
local LANTERN = hex("#FFE14D")

local SCALE = 1.25

local function add(
	model: Model,
	offset: CFrame,
	size: Vector3,
	color: Color3,
	options: { cylinder: boolean?, neon: boolean? }?
): Part
	local p = Instance.new("Part")
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.Material = if options and options.neon then Enum.Material.Neon else Enum.Material.SmoothPlastic
	p.Color = color
	p.Size = size * SCALE
	p.CFrame = offset
	if options and options.cylinder then
		p.Shape = Enum.PartType.Cylinder
	else
		local mesh = Instance.new("SpecialMesh")
		mesh.MeshType = Enum.MeshType.Sphere
		mesh.Parent = p
	end
	p.Parent = model
	return p
end

-- Offsets are given in character units and scaled here; the rotation stays as given.
local function at(x: number, y: number, z: number, rotation: CFrame?): CFrame
	return CFrame.new(x * SCALE, y * SCALE, z * SCALE) * (rotation or CFrame.identity)
end

function SpiritModel.create(kind: string): Model
	local look = LOOKS[kind] or DEFAULT_LOOK
	local model = Instance.new("Model")
	model.Name = `Spirit_{kind}`

	-- The parts are first built around the origin, then moved with the model's pivot.
	local body = add(model, at(0, 1.1, 0), Vector3.new(2, 1.9, 1.8), look.body)
	model.PrimaryPart = body

	-- face
	for _, side in { -1, 1 } do
		add(model, at(side * 0.45, 1.3, -0.86), Vector3.new(0.3, 0.44, 0.12), INK)
		add(model, at(side * 0.5, 1.4, -0.93), Vector3.new(0.1, 0.12, 0.06), WHITE)
		add(model, at(side * 0.78, 0.98, -0.78), Vector3.new(0.34, 0.2, 0.1), look.cheek)
	end
	add(model, at(0, 0.98, -0.9), Vector3.new(0.26, 0.12, 0.08), INK)

	-- short arms and legs
	for _, side in { -1, 1 } do
		add(
			model,
			at(side * 1.05, 0.85, -0.05, CFrame.Angles(0, 0, side * math.rad(-25))),
			Vector3.new(0.5, 0.8, 0.5),
			look.body
		)
		add(model, at(side * 0.5, 0.18, -0.2), Vector3.new(0.6, 0.36, 0.8), look.body)
	end

	-- headphones: a band over the head and a cup over each ear
	local segments = 6
	local radius = 1.12
	local centre = Vector3.new(0, 1.35, 0)
	local previous: Vector3? = nil
	for i = 0, segments do
		local angle = math.pi * i / segments
		local point = centre + Vector3.new(math.cos(angle) * radius, math.sin(angle) * 0.95, 0)
		if previous then
			local mid = (previous + point) / 2
			local length = (point - previous).Magnitude
			add(model, CFrame.lookAt(mid * SCALE, point * SCALE), Vector3.new(0.16, 0.16, length / SCALE + 0.05), INK)
		end
		previous = point
	end
	for _, side in { -1, 1 } do
		add(model, at(side * 1.12, 1.35, 0), Vector3.new(0.5, 0.95, 0.95), look.phones, { cylinder = true })
	end

	-- what makes this spirit this spirit
	if kind == "Kitsune" then
		for _, side in { -1, 1 } do
			add(
				model,
				at(side * 0.62, 2.35, 0, CFrame.Angles(0, 0, side * math.rad(-18))),
				Vector3.new(0.5, 0.95, 0.3),
				look.body
			)
			add(
				model,
				at(side * 0.62, 2.3, -0.1, CFrame.Angles(0, 0, side * math.rad(-18))),
				Vector3.new(0.26, 0.6, 0.12),
				look.cheek
			)
		end
		-- a fluffy tail with a little lantern that glows
		add(model, at(0, 0.85, 1.05, CFrame.Angles(math.rad(35), 0, 0)), Vector3.new(0.8, 0.8, 1.5), look.body)
		local lantern = add(model, at(0, 1.5, 1.8), Vector3.new(0.5, 0.5, 0.5), LANTERN, { neon = true })
		local glow = Instance.new("PointLight")
		glow.Range = 8
		glow.Brightness = 1.2
		glow.Color = LANTERN
		glow.Parent = lantern
	elseif kind == "Pon" then
		-- a little beak, a leaf tuft with a yuzu stem, and stubby wings
		add(model, at(0, 1.12, -1.0), Vector3.new(0.5, 0.26, 0.4), hex("#FF9A3D"))
		add(model, at(0, 2.2, 0, CFrame.Angles(0, 0, math.rad(20))), Vector3.new(0.35, 0.8, 0.2), hex("#7ED957"))
		add(model, at(0.25, 2.15, 0, CFrame.Angles(0, 0, math.rad(-35))), Vector3.new(0.3, 0.65, 0.2), hex("#5FBF6A"))
	elseif kind == "Koke" then
		-- a mossy shell on the back with a tiny bonsai
		add(model, at(0, 1.2, 0.8), Vector3.new(1.7, 1.5, 1.0), hex("#8A6A4A"))
		add(model, at(0, 2.0, 0.85), Vector3.new(0.9, 0.5, 0.7), hex("#5FBF6A"))
		add(model, at(0, 2.5, 0.85), Vector3.new(0.35, 0.5, 0.35), hex("#3DAE7A"))
	elseif kind == "Ame" then
		-- frog eyes on top and a droplet antenna
		for _, side in { -1, 1 } do
			add(model, at(side * 0.5, 2.15, -0.1), Vector3.new(0.7, 0.7, 0.7), WHITE)
			add(model, at(side * 0.5, 2.15, -0.42), Vector3.new(0.3, 0.3, 0.2), INK)
		end
		add(model, at(0, 2.7, 0.2), Vector3.new(0.3, 0.5, 0.3), hex("#3FC8FF"), { neon = true })
	elseif kind == "Haru" then
		-- pointed ears, whiskers and an upright tail
		for _, side in { -1, 1 } do
			add(
				model,
				at(side * 0.6, 2.3, 0, CFrame.Angles(0, 0, side * math.rad(-25))),
				Vector3.new(0.5, 0.7, 0.3),
				look.body
			)
			add(
				model,
				at(side * 0.6, 2.25, -0.08, CFrame.Angles(0, 0, side * math.rad(-25))),
				Vector3.new(0.26, 0.4, 0.12),
				look.cheek
			)
			for _, dy in { 0, -0.14 } do
				add(
					model,
					at(side * 1.0, 1.0 + dy, -0.8, CFrame.Angles(0, side * math.rad(-20), 0)),
					Vector3.new(0.8, 0.04, 0.04),
					INK
				)
			end
		end
		add(model, at(0, 1.5, 1.1, CFrame.Angles(math.rad(-20), 0, 0)), Vector3.new(0.38, 1.5, 0.38), look.body)
	elseif kind == "Poko" then
		-- round ears, dark eye patches and a striped tail
		for _, side in { -1, 1 } do
			add(model, at(side * 0.75, 2.15, 0), Vector3.new(0.55, 0.55, 0.3), hex("#8A5A33"))
			add(model, at(side * 0.45, 1.3, -0.82), Vector3.new(0.6, 0.7, 0.12), hex("#5A3A22"))
		end
		add(model, at(0, 0.95, 1.1, CFrame.Angles(math.rad(25), 0, 0)), Vector3.new(0.7, 0.7, 1.5), look.body)
		add(model, at(0, 1.1, 1.15, CFrame.Angles(math.rad(25), 0, 0)), Vector3.new(0.75, 0.2, 0.5), hex("#5A3A22"))
	elseif kind == "Mimi" then
		-- long ears and a fluffy tail
		for _, side in { -1, 1 } do
			add(
				model,
				at(side * 0.5, 2.9, 0, CFrame.Angles(0, 0, side * math.rad(-10))),
				Vector3.new(0.5, 1.7, 0.3),
				look.body
			)
			add(
				model,
				at(side * 0.5, 2.85, -0.08, CFrame.Angles(0, 0, side * math.rad(-10))),
				Vector3.new(0.26, 1.2, 0.12),
				look.cheek
			)
		end
		add(model, at(0, 0.7, 1.0), Vector3.new(0.55, 0.55, 0.55), WHITE)
	elseif kind == "Hoshi" then
		-- a glowing star on top
		for i = 0, 4 do
			local angle = math.rad(90 + i * 72)
			add(
				model,
				at(math.cos(angle) * 0.55, 2.55 + math.sin(angle) * 0.55, 0),
				Vector3.new(0.4, 0.4, 0.3),
				LANTERN,
				{ neon = true }
			)
		end
		local core = add(model, at(0, 2.55, 0), Vector3.new(0.6, 0.6, 0.3), LANTERN, { neon = true })
		local glow = Instance.new("PointLight")
		glow.Range = 9
		glow.Brightness = 1.4
		glow.Color = LANTERN
		glow.Parent = core
	elseif kind == "Yoru" then
		-- the night fox: dark ears and a tail with two violet lanterns
		for _, side in { -1, 1 } do
			add(
				model,
				at(side * 0.62, 2.35, 0, CFrame.Angles(0, 0, side * math.rad(-18))),
				Vector3.new(0.5, 0.95, 0.3),
				look.body
			)
			add(
				model,
				at(side * 0.62, 2.3, -0.1, CFrame.Angles(0, 0, side * math.rad(-18))),
				Vector3.new(0.26, 0.6, 0.12),
				look.cheek
			)
		end
		add(model, at(0, 0.85, 1.05, CFrame.Angles(math.rad(35), 0, 0)), Vector3.new(0.8, 0.8, 1.5), look.body)
		for _, side in { -1, 1 } do
			local lantern =
				add(model, at(side * 0.4, 1.5, 1.8), Vector3.new(0.4, 0.4, 0.4), hex("#C79BFF"), { neon = true })
			local light = Instance.new("PointLight")
			light.Range = 7
			light.Brightness = 1
			light.Color = hex("#C79BFF")
			light.Parent = lantern
		end
	else
		add(
			model,
			at(0, 2.2, 0.05, CFrame.Angles(math.rad(-15), 0, math.rad(10))),
			Vector3.new(0.7, 0.2, 0.55),
			hex("#FF9EC4")
		)
		add(model, at(0.18, 2.3, 0.05), Vector3.new(0.14, 0.14, 0.14), WHITE)
	end

	model.WorldPivot = CFrame.identity
	return model
end

return SpiritModel
