--!strict
-- The two shop NPCs standing near the spawn: the Seed Shop and the Market (sells fruit).
-- Prototype figures built from parts (the real models come with the art pass). Each has a
-- ProximityPrompt; the client opens the matching screen when it is triggered. Selling is only
-- allowed near the Market NPC, which the server checks with `distanceTo`.

local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Palette = require(ReplicatedStorage.Shared.Palette)

local Npcs = {}

export type Kind = "shop" | "market"

local PROMPT_RANGE = 16
local SELL_RANGE = 30 -- what the server allows (a little more than the prompt, for lag)

local anchors: { [string]: Part } = {}

local function spawnPosition(): Vector3
	local spawn = Workspace:FindFirstChildWhichIsA("SpawnLocation", true)
	return if spawn then spawn.Position else Vector3.zero
end

local function groundY(x: number, z: number): number
	local hit = Workspace:Raycast(Vector3.new(x, 200, z), Vector3.new(0, -400, 0))
	return if hit then hit.Position.Y else 0
end

local function part(props: { [string]: any }, parent: Instance): Part
	local p = Instance.new("Part")
	p.Anchored = true
	p.CanCollide = false
	p.Material = Enum.Material.SmoothPlastic
	for k, v in props do
		(p :: any)[k] = v
	end
	p.Parent = parent
	return p
end

local function build(
	container: Instance,
	kind: Kind,
	offset: Vector3,
	bodyColor: Color3,
	title: string,
	promptName: string,
	action: string
)
	local base = spawnPosition() + offset
	local y = groundY(base.X, base.Z)

	local model = Instance.new("Model")
	model.Name = `Npc_{kind}`
	model.Parent = container

	-- Body, head and a little hat: enough to read as "a person standing there".
	local body = part({
		Name = "Body",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(4, 3.2, 3.2),
		CFrame = CFrame.new(base.X, y + 2, base.Z) * CFrame.Angles(0, 0, math.rad(90)),
		Color = bodyColor,
	}, model)
	part({
		Name = "Head",
		Shape = Enum.PartType.Ball,
		Size = Vector3.new(2.4, 2.4, 2.4),
		Position = Vector3.new(base.X, y + 5.2, base.Z),
		Color = Palette.Base.Washi,
	}, model)
	part({
		Name = "Hat",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(0.5, 2.8, 2.8),
		CFrame = CFrame.new(base.X, y + 6.7, base.Z) * CFrame.Angles(0, 0, math.rad(90)),
		Color = Palette.Base.Sumi,
	}, model)

	-- A coloured pad under the stall, and a real signboard behind it facing the hub (no floating text, so two
	-- stalls side by side never cover each other).
	part({
		Name = "Pad",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(0.3, 11, 11),
		CFrame = CFrame.new(base.X, y + 0.15, base.Z) * CFrame.Angles(0, 0, math.rad(90)),
		Color = bodyColor,
		CanQuery = false,
	}, model)
	local boardCenter = Vector3.new(base.X - 3.6, y + 7.2, base.Z)
	for _, dz in { -3, 3 } do
		part({
			Name = "Post",
			Size = Vector3.new(0.5, 5.4, 0.5),
			Position = Vector3.new(base.X - 3.6, y + 2.7, base.Z + dz),
			Color = Palette.Base.Washi,
		}, model)
	end
	local board = part({
		Name = "Board",
		Size = Vector3.new(8, 3.4, 0.5),
		CFrame = CFrame.lookAt(boardCenter, boardCenter + Vector3.new(1, 0, 0)), -- the front faces the hub
		Color = bodyColor,
	}, model)
	local surface = Instance.new("SurfaceGui")
	surface.Face = Enum.NormalId.Front
	surface.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	surface.PixelsPerStud = 50
	surface.Parent = board
	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.TextColor3 = Palette.Base.YoruSky
	label.TextScaled = true
	label.Font = Enum.Font.GothamBlack
	label.Text = title
	label.Parent = surface
	local stroke = Instance.new("UIStroke")
	stroke.Color = Color3.new(1, 1, 1)
	stroke.Thickness = 3
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual
	stroke.Parent = label
	local padding = Instance.new("UIPadding")
	padding.PaddingTop = UDim.new(0.12, 0)
	padding.PaddingBottom = UDim.new(0.12, 0)
	padding.PaddingLeft = UDim.new(0.06, 0)
	padding.PaddingRight = UDim.new(0.06, 0)
	padding.Parent = label

	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = promptName
	prompt.ActionText = action
	prompt.ObjectText = title
	prompt.HoldDuration = 0
	prompt.MaxActivationDistance = PROMPT_RANGE
	prompt.RequiresLineOfSight = false
	prompt.UIOffset = Vector2.new(0, -90)
	prompt.Parent = body

	anchors[kind] = body
end

function Npcs.start(container: Instance)
	-- On the opposite side of the spawn from the plots (which run along +X at -Z).
	build(container, "shop", Vector3.new(-16, 0, -4), Palette.Hues.Matcha.Day, "Seed Shop", "ShopPrompt", "Shop")
	build(container, "market", Vector3.new(-16, 0, 8), Palette.Hues.Yuzu.Day, "Market", "MarketPrompt", "Sell")
end

-- Distance from the player's character to an NPC, or math.huge if they have no character.
function Npcs.distanceTo(player: Player, kind: Kind): number
	local anchor = anchors[kind]
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not (anchor and root and root:IsA("BasePart")) then
		return math.huge
	end
	return (root.Position - anchor.Position).Magnitude
end

Npcs.SellRange = SELL_RANGE

return Npcs
