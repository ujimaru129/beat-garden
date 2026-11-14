--!strict
-- The spirits as pets.
--   * Every player's spirits except the equipped one wander around that player's territory. The server publishes them
--     in the player attribute "Pets" ("id:kind:bond:nick,...", see Garden.syncPets).
--   * The equipped spirit follows its player around (attribute "Follower", same format).
-- Each client draws them all on its own. Your own can be petted: tap one and its bond grows (the server counts it),
-- hearts pop up and it hops. A spirit with a name wears a small name tag.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local GardenState = require(script.Parent.GardenState)
local Lang = require(script.Parent.Lang)
local SpiritModel = require(script.Parent.SpiritModel)
local Spirits = require(ReplicatedStorage.Shared.Garden.Spirits)
local Toast = require(script.Parent.Toast)

local PetFx = {}

local WANDER_RADIUS = 22 -- studs around the middle of the territory
local WALK_SPEED = 5
local NEAR = 190 -- studs from the camera: pets farther away are not drawn

type Pet = {
	id: string,
	kind: string,
	bond: number,
	nick: number,
	level: number,
	traits: { string },
	sig: string, -- level and traits: when it changes the model is built again
	rainbow: BasePart?,
	model: Model,
	owner: Player,
	follow: boolean,
	position: Vector3,
	target: Vector3?,
	idleUntil: number,
	phase: number,
	hopUntil: number,
	heading: number,
	moving: boolean,
	tag: TextLabel?,
}

local pets: { [Player]: { [string]: Pet } } = {}
local followers: { [Player]: Pet } = {}
local centers: { [number]: Vector3 } = {}
local folder: Folder

-- The middle of a player's territory: the average of their plot soils (they carry the owner in an attribute).
local function centerOf(userId: number): Vector3?
	local cached = centers[userId]
	if cached then
		return cached
	end
	local container = Workspace:FindFirstChild("Garden")
	if not container then
		return nil
	end
	local sum, count = Vector3.zero, 0
	for _, child in container:GetChildren() do
		if child:IsA("BasePart") and child:GetAttribute("OwnerUserId") == userId and child:GetAttribute("PlotKey") then
			-- the base of the soil is the ground
			sum += Vector3.new(child.Position.X, child.Position.Y - child.Size.Y / 2, child.Position.Z)
			count += 1
		end
	end
	if count == 0 then
		return nil
	end
	local center = sum / count
	centers[userId] = center
	return center
end

-- Where the player's feet are.
local function feetOf(player: Player): (Vector3?, CFrame?)
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not (root and root:IsA("BasePart")) then
		return nil, nil
	end
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local drop = (if humanoid then humanoid.HipHeight else 2) + root.Size.Y / 2
	return root.Position - Vector3.new(0, drop, 0), root.CFrame
end

local function displayName(nick: number): string?
	return Spirits.nickname(nick, Lang.code)
end

local function setTag(pet: Pet)
	local name = displayName(pet.nick)
	local anchor = pet.model.PrimaryPart
	if not name then
		if pet.tag then
			(pet.tag.Parent :: Instance):Destroy()
			pet.tag = nil
		end
		return
	end
	if not pet.tag and anchor then
		local gui = Instance.new("BillboardGui")
		gui.Name = "NameTag"
		gui.Size = UDim2.fromOffset(110, 26)
		gui.StudsOffset = Vector3.new(0, 4.4, 0)
		gui.AlwaysOnTop = false
		gui.MaxDistance = 45
		gui.Adornee = anchor
		local label = Instance.new("TextLabel")
		label.BackgroundTransparency = 1
		label.Size = UDim2.fromScale(1, 1)
		label.Font = Enum.Font.GothamBlack
		label.TextSize = 18
		label.TextColor3 = Color3.new(1, 1, 1)
		label.TextStrokeColor3 = Color3.fromRGB(70, 50, 120)
		label.TextStrokeTransparency = 0.2
		label.Parent = gui
		gui.Parent = anchor
		pet.tag = label
	end
	if pet.tag then
		pet.tag.Text = name
	end
end

local function heartsAt(pet: Pet)
	local anchor = pet.model.PrimaryPart
	if not anchor then
		return
	end
	for i = 1, 3 do
		local gui = Instance.new("BillboardGui")
		gui.Size = UDim2.fromOffset(40, 40)
		gui.StudsOffset = Vector3.new((i - 2) * 0.9, 4.2, 0)
		gui.AlwaysOnTop = true
		gui.Adornee = anchor
		local label = Instance.new("TextLabel")
		label.BackgroundTransparency = 1
		label.Size = UDim2.fromScale(1, 1)
		label.Text = "\u{2665}"
		label.TextScaled = true
		label.Font = Enum.Font.GothamBlack
		label.TextColor3 = Color3.fromRGB(255, 90, 150)
		label.TextStrokeColor3 = Color3.new(1, 1, 1)
		label.TextStrokeTransparency = 0.2
		label.Parent = gui
		gui.Parent = anchor
		task.delay(i * 0.08, function()
			TweenService:Create(gui, TweenInfo.new(0.9, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
				StudsOffset = gui.StudsOffset + Vector3.new(0, 3, 0),
			}):Play()
			TweenService:Create(label, TweenInfo.new(0.9), { TextTransparency = 1, TextStrokeTransparency = 1 }):Play()
			task.delay(1, function()
				gui:Destroy()
			end)
		end)
	end
end

local function patPet(pet: Pet)
	pet.hopUntil = os.clock() + 0.55
	pet.idleUntil = os.clock() + 1.5
	if not pet.follow then
		pet.target = nil
	end
	heartsAt(pet)
	task.spawn(function()
		local result = GardenState.call("pat", pet.id)
		if result.ok and result.levelUp then
			local def = Spirits.get(pet.kind)
			local name = displayName(pet.nick)
				or (if def then (if Lang.code == "ja" then def.name.ja else def.name.en) else pet.kind)
			Toast.show(`{name} likes you more!`)
		end
	end)
end

local function signature(entry: Spirits.Entry): string
	return `{entry.kind}:{entry.level}:{table.concat(entry.traits, "+")}`
end

local function createPet(owner: Player, entry: Spirits.Entry, follow: boolean): Pet?
	local id, kind, bond, nick = entry.id, entry.kind, entry.bond, entry.nick
	local start: Vector3
	if follow then
		local feet = feetOf(owner)
		if not feet then
			return nil
		end
		start = feet
	else
		local center = centerOf(owner.UserId)
		if not center then
			return nil
		end
		local rng = Random.new(#id * 31 + bond)
		start = center + Vector3.new(rng:NextNumber(-12, 12), 0, rng:NextNumber(-12, 12))
	end
	local model = SpiritModel.create(kind, entry.traits)
	local own = owner == Players.LocalPlayer
	local hitbox: Part? = nil
	if own then
		-- The spirit's own parts cannot be hit by a click (they are not queried), so a see-through box around it
		-- takes the taps; it is a bit bigger than the pet, which makes it easy to tap on a phone.
		hitbox = Instance.new("Part")
		local box = hitbox :: Part
		box.Name = "PetHitbox"
		box.Anchored = true
		box.CanCollide = false
		box.CanTouch = false
		box.CanQuery = true
		box.CastShadow = false
		box.Transparency = 1
		box.Size = Vector3.new(4.5, 5, 4.5)
		box.CFrame = model:GetPivot() * CFrame.new(0, 2.2, 0)
		box.Parent = model
	end
	model:ScaleTo(0.8 * Spirits.sizeFactor(entry.level, entry.traits))
	local rng = Random.new(#id * 17 + bond)
	local pet: Pet = {
		id = id,
		kind = kind,
		bond = bond,
		nick = nick,
		level = entry.level,
		traits = entry.traits,
		sig = signature(entry),
		rainbow = model:FindFirstChild("RainbowRing") :: BasePart?,
		model = model,
		owner = owner,
		follow = follow,
		position = start,
		target = nil,
		idleUntil = os.clock() + rng:NextNumber(0, 2),
		phase = rng:NextNumber(0, 6),
		hopUntil = 0,
		heading = rng:NextNumber(0, math.pi * 2),
		moving = false,
		tag = nil,
	}
	if hitbox then
		local click = Instance.new("ClickDetector")
		click.MaxActivationDistance = 60
		click.Parent = hitbox
		click.MouseClick:Connect(function()
			patPet(pet)
		end)
	end
	model:PivotTo(CFrame.new(start))
	setTag(pet)
	return pet
end

local function removePet(pet: Pet)
	pet.model:Destroy()
end

-- Reads a player's "Pets" attribute and makes the roaming pets match it.
local function sync(owner: Player)
	local value = owner:GetAttribute("Pets")
	local wanted: { [string]: Spirits.Entry } = {}
	if type(value) == "string" then
		for text in string.gmatch(value, "[^,]+") do
			local entry = Spirits.decode(text)
			if entry then
				wanted[entry.id] = entry
			end
		end
	end
	local mine = pets[owner] or {}
	pets[owner] = mine
	for id, pet in mine do
		if not wanted[id] or signature(wanted[id]) ~= pet.sig then
			removePet(pet)
			mine[id] = nil
		end
	end
	for id, info in wanted do
		local pet = mine[id]
		if pet then
			pet.bond = info.bond
			if pet.nick ~= info.nick then
				pet.nick = info.nick
				setTag(pet)
			end
		else
			local created = createPet(owner, info, false)
			if created then
				mine[id] = created
			end
		end
	end
end

-- Reads "Follower": the equipped spirit.
local function syncFollower(owner: Player)
	local value = owner:GetAttribute("Follower")
	local entry = if type(value) == "string" and value ~= "" then Spirits.decode(value) else nil
	local current = followers[owner]
	if current and (not entry or entry.id ~= current.id or signature(entry) ~= current.sig) then
		removePet(current)
		followers[owner] = nil
		current = nil
	end
	if current and entry then
		current.bond = entry.bond
		if current.nick ~= entry.nick then
			current.nick = entry.nick
			setTag(current)
		end
	elseif entry then
		local created = createPet(owner, entry, true)
		if created then
			followers[owner] = created
		end
	end
end

local function track(player: Player)
	player:GetAttributeChangedSignal("Pets"):Connect(function()
		sync(player)
	end)
	player:GetAttributeChangedSignal("Follower"):Connect(function()
		syncFollower(player)
	end)
	sync(player)
	syncFollower(player)
end

function PetFx.start()
	folder = Instance.new("Folder")
	folder.Name = "PetFx"
	folder.Parent = Workspace

	for _, player in Players:GetPlayers() do
		task.spawn(track, player)
	end
	Players.PlayerAdded:Connect(track)
	Players.PlayerRemoving:Connect(function(player)
		local mine = pets[player]
		if mine then
			for _, pet in mine do
				removePet(pet)
			end
		end
		pets[player] = nil
		local follower = followers[player]
		if follower then
			removePet(follower)
			followers[player] = nil
		end
		centers[player.UserId] = nil
	end)

	-- Hop height of a pet: a big hop after a pat, small hops while it moves, a gentle bob while it rests.
	local function hopOf(pet: Pet, now: number): number
		if now < pet.hopUntil then
			return math.abs(math.sin((pet.hopUntil - now) / 0.55 * math.pi * 2)) * 1.6
		elseif pet.moving then
			return math.abs(math.sin(now * 7 + pet.phase)) * 0.55
		end
		return (math.sin(now * 2 + pet.phase) * 0.5 + 0.5) * 0.12
	end

	-- A rainbow spirit's ring cycles through the colours.
	local function tint(pet: Pet, now: number)
		local ring = pet.rainbow
		if ring then
			local color = Color3.fromHSV((now * 0.25 + pet.phase) % 1, 0.65, 1)
			ring.Color = color
			local light = ring:FindFirstChildOfClass("PointLight")
			if light then
				light.Color = color
			end
		end
	end

	local since = 0
	RunService.RenderStepped:Connect(function(dt: number)
		local camera = Workspace.CurrentCamera
		if not camera then
			return
		end
		local eye = camera.CFrame.Position
		local now = os.clock()
		since += dt
		local retry = since > 2
		if retry then
			since = 0
		end

		for owner, mine in pets do
			-- a territory that was not built yet when the pet appeared: look for its plots again
			if retry then
				sync(owner)
			end
			for _, pet in mine do
				local near = (pet.position - eye).Magnitude < NEAR
				pet.model.Parent = if near then folder else nil
				if not near then
					continue
				end
				local center = centerOf(owner.UserId)
				if not center then
					continue
				end
				-- walk to a random spot, rest, repeat
				pet.moving = pet.target ~= nil
				if pet.target then
					local toTarget = pet.target - pet.position
					local flat = Vector3.new(toTarget.X, 0, toTarget.Z)
					if flat.Magnitude < 0.6 then
						pet.target = nil
						pet.idleUntil = now + 1 + math.random() * 3
					else
						local step = math.min(flat.Magnitude, WALK_SPEED * dt)
						pet.position += flat.Unit * step
						pet.heading = math.atan2(-flat.X, -flat.Z)
					end
				elseif now >= pet.idleUntil then
					local angle = math.random() * math.pi * 2
					local radius = math.sqrt(math.random()) * WANDER_RADIUS
					pet.target = center + Vector3.new(math.cos(angle) * radius, 0, math.sin(angle) * radius)
				end
				pet.model:PivotTo(
					CFrame.new(pet.position + Vector3.new(0, hopOf(pet, now), 0)) * CFrame.Angles(0, pet.heading, 0)
				)
				tint(pet, now)
			end
		end

		-- The equipped spirit keeps close to its player: a little behind and to the side.
		for owner, pet in followers do
			if retry then
				syncFollower(owner)
			end
			local feet, frame = feetOf(owner)
			if not (feet and frame) then
				continue
			end
			local spot = feet + frame.RightVector * 2.6 - frame.LookVector * 2.4
			local offset = spot - pet.position
			local flat = Vector3.new(offset.X, 0, offset.Z)
			if flat.Magnitude > 60 then
				pet.position = spot -- far behind (the player was moved): jump to them
			else
				pet.position += Vector3.new(offset.X, offset.Y, offset.Z) * math.min(1, dt * 5)
			end
			pet.moving = flat.Magnitude > 1.2
			if pet.moving then
				pet.heading = math.atan2(-flat.X, -flat.Z)
			else
				local look = frame.LookVector
				pet.heading = math.atan2(-look.X, -look.Z)
			end
			pet.model.Parent = if (pet.position - eye).Magnitude < NEAR then folder else nil
			pet.model:PivotTo(
				CFrame.new(pet.position + Vector3.new(0, hopOf(pet, now), 0)) * CFrame.Angles(0, pet.heading, 0)
			)
			tint(pet, now)
		end
	end)
end

return PetFx
