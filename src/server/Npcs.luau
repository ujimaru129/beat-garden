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

	-- The name floats above the figure so it can be found from a distance.
	local sign = Instance.new("BillboardGui")
	sign.Name = "Sign"
	sign.Adornee = body
	sign.Size = UDim2.fromOffset(200, 44)
	sign.StudsOffsetWorldSpace = Vector3.new(0, 6.2, 0)
	sign.AlwaysOnTop = true
	sign.MaxDistance = 80
	sign.Parent = body
	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundColor3 = Palette.Base.YoruSky
	label.BackgroundTransparency = 0.25
	label.TextColor3 = Palette.Base.Washi
	label.TextScaled = true
	label.Font = Enum.Font.GothamBold
	label.Text = title
	label.Parent = sign
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 10)
	corner.Parent = label
	local padding = Instance.new("UIPadding")
	padding.PaddingTop = UDim.new(0.15, 0)
	padding.PaddingBottom = UDim.new(0.15, 0)
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
