--!strict
-- The spirits as pets: every player's spirits (except the equipped one, which stays beside the plant) wander around
-- that player's territory. The server publishes them in the player attribute "Pets" ("id:kind:bond,...", see
-- Garden.syncPets); each client draws them, all on its own. Your own pets can be petted: tap one and its bond grows
-- (the server counts it), hearts pop up and it hops.

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
	model: Model,
	owner: Player,
	position: Vector3,
	target: Vector3?,
	idleUntil: number,
	phase: number,
	hopUntil: number,
	heading: number,
}

local pets: { [Player]: { [string]: Pet } } = {}
local centers: { [number]: Vector3 } = {}
local folder: Folder

-- The middle of a player's territory: the average of their plot soils (they are tagged by the server's attributes).
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
	pet.target = nil
	heartsAt(pet)
	task.spawn(function()
		local result = GardenState.call("pat", pet.id)
		if result.ok and result.levelUp then
			local def = Spirits.get(pet.kind)
			local name = if def then (if Lang.code == "ja" then def.name.ja else def.name.en) else pet.kind
			Toast.show(`{name} likes you more!`)
		end
	end)
end

local function createPet(owner: Player, id: string, kind: string, bond: number): Pet?
	local center = centerOf(owner.UserId)
	if not center then
		return nil
	end
	local model = SpiritModel.create(kind)
	local own = owner == Players.LocalPlayer
	local hitbox: Part? = nil
	if own then
		-- The spirit's own parts cannot be hit by a click (they are not queried), so a see-through box around it
		-- takes the taps; it is a bit bigger than the pet, which makes it easy to tap on a phone.
		local pivot = model:GetPivot()
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
		box.CFrame = pivot * CFrame.new(0, 2.2, 0)
		box.Parent = model
	end
	model:ScaleTo(0.8)
	local rng = Random.new(#id * 31 + bond)
	local start = center + Vector3.new(rng:NextNumber(-12, 12), 0, rng:NextNumber(-12, 12))
	local pet: Pet = {
		id = id,
		kind = kind,
		bond = bond,
		model = model,
		owner = owner,
		position = start,
		target = nil,
		idleUntil = os.clock() + rng:NextNumber(0, 2),
		phase = rng:NextNumber(0, 6),
		hopUntil = 0,
		heading = rng:NextNumber(0, math.pi * 2),
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
	return pet
end

local function removePet(pet: Pet)
	pet.model:Destroy()
end

-- Reads a player's "Pets" attribute and makes the pets match it.
local function sync(owner: Player)
	local value = owner:GetAttribute("Pets")
	local wanted: { [string]: { kind: string, bond: number } } = {}
	if type(value) == "string" then
		for entry in string.gmatch(value, "[^,]+") do
			local id, kind, bond = string.match(entry, "^([^:]+):([^:]+):(%d+)$")
			if id and kind and bond and Spirits.get(kind) then
				wanted[id] = { kind = kind, bond = tonumber(bond) :: number }
			end
		end
	end
	local mine = pets[owner] or {}
	pets[owner] = mine
	for id, pet in mine do
		if not wanted[id] or wanted[id].kind ~= pet.kind then
			removePet(pet)
			mine[id] = nil
		end
	end
	for id, info in wanted do
		local pet = mine[id]
		if pet then
			pet.bond = info.bond
		else
			local created = createPet(owner, id, info.kind, info.bond)
			if created then
				mine[id] = created
			end
		end
	end
end

local function track(player: Player)
	player:GetAttributeChangedSignal("Pets"):Connect(function()
		sync(player)
	end)
	sync(player)
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
		centers[player.UserId] = nil
	end)

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
				local walking = pet.target ~= nil
				local hop = 0
				if now < pet.hopUntil then
					hop = math.abs(math.sin((pet.hopUntil - now) / 0.55 * math.pi * 2)) * 1.6
				elseif walking then
					hop = math.abs(math.sin(now * 7 + pet.phase)) * 0.55
				else
					hop = (math.sin(now * 2 + pet.phase) * 0.5 + 0.5) * 0.12
				end
				pet.model:PivotTo(CFrame.new(pet.position + Vector3.new(0, hop, 0)) * CFrame.Angles(0, pet.heading, 0))
			end
		end
	end)
end

return PetFx
