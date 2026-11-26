--!strict
-- A small 3D picture for a list row: a spirit (id = its kind) or a plant's fruit (id = the seed, with the mutation if
-- there is one). A ViewportFrame is the costly kind of picture, so lists only show the ones that are on screen.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local PlantLook = require(ReplicatedStorage.Shared.Garden.PlantLook)
local SpiritModel = require(script.Parent.SpiritModel)

export type Icon = { kind: "spirit" | "plant", id: string, mutation: string? }

local RowIcon = {}

-- `size` pixels, centred in its parent.
function RowIcon.create(icon: Icon, lit: boolean, size: number): ViewportFrame
	local viewport = Instance.new("ViewportFrame")
	viewport.Name = "RowIcon"
	viewport.AnchorPoint = Vector2.new(0.5, 0.5)
	viewport.Position = UDim2.fromScale(0.5, 0.5)
	viewport.Size = UDim2.fromOffset(size, size)
	viewport.BackgroundTransparency = if lit then 0.55 else 0.8
	viewport.BackgroundColor3 = Color3.new(1, 1, 1)
	viewport.Ambient = Color3.fromRGB(190, 190, 205)
	viewport.LightColor = Color3.new(1, 1, 1)
	viewport.LightDirection = Vector3.new(-0.4, -1, -0.6)
	viewport.ZIndex = 6
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0.5, 0)
	corner.Parent = viewport
	local camera = Instance.new("Camera")
	camera.FieldOfView = 30
	if icon.kind == "plant" then
		-- the grown fruit, drawn with the same code as the plants in the garden
		local model = Instance.new("Model")
		model.Parent = viewport
		local core = Instance.new("Part")
		core.Anchored = true
		core.CanCollide = false
		core.Parent = model
		local parts = Instance.new("Folder")
		parts.Parent = model
		PlantLook.apply(core, parts, Vector3.zero, icon.id, "Fruit", 1, icon.mutation, 0, 0.3)
		camera.CFrame = CFrame.lookAt(Vector3.new(0, 1.5, -7.5), Vector3.new(0, 1.35, 0))
	else
		SpiritModel.create(icon.id).Parent = viewport
		camera.CFrame = CFrame.lookAt(Vector3.new(0, 1.9, -7.2), Vector3.new(0, 1.65, 0))
	end
	camera.Parent = viewport
	viewport.CurrentCamera = camera
	return viewport
end

return RowIcon
