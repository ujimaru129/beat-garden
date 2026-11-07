--!strict
-- The little show when a fruit is harvested. A mutated fruit gets its look (colour, glow, sparkles)
-- so the mutation is clearly *seen*, not only read in a message. Drawn locally; low graphics quality
-- keeps the glow but drops the sparkles.

local Debris = game:GetService("Debris")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Atmosphere = require(script.Parent.Atmosphere)
local Palette = require(ReplicatedStorage.Shared.Palette)

local HarvestFx = {}

local SPARKLE_TEXTURE = "rbxasset://textures/particles/sparkles_main.dds"

-- Colours for a mutation's look; an unmutated fruit gets the plain fruit yellow.
local function colorsFor(mutation: string?): { Color3 }
	if mutation and Palette.Mutation[mutation] then
		return Palette.Mutation[mutation]
	end
	return { Palette.Hues.Yuzu.Night }
end

function HarvestFx.play(origin: Vector3, mutation: string?)
	local colors = colorsFor(mutation)
	local lite = Atmosphere.isLite()

	local fruit = Instance.new("Part")
	fruit.Name = "HarvestFx"
	fruit.Shape = Enum.PartType.Ball
	fruit.Size = Vector3.new(2.2, 2.2, 2.2)
	fruit.Anchored = true
	fruit.CanCollide = false
	fruit.CanQuery = false
	fruit.CanTouch = false
	fruit.CastShadow = false
	fruit.Material = Enum.Material.Neon
	fruit.Color = colors[1]
	fruit.Position = origin + Vector3.new(0, 4, 0)
	fruit.Parent = Workspace

	local light = Instance.new("PointLight")
	light.Color = colors[1]
	light.Range = if mutation then 18 else 10
	light.Brightness = if mutation then 4 else 1.5
	light.Parent = fruit

	if not lite then
		local sparkles = Instance.new("ParticleEmitter")
		sparkles.Texture = SPARKLE_TEXTURE
		sparkles.Rate = 0
		sparkles.Lifetime = NumberRange.new(0.8, 1.4)
		sparkles.Speed = NumberRange.new(6, 14)
		sparkles.SpreadAngle = Vector2.new(180, 180)
		sparkles.Size = NumberSequence.new(0.7, 0)
		sparkles.LightEmission = 1
		local keypoints = {}
		for i, color in colors do
			table.insert(keypoints, ColorSequenceKeypoint.new((i - 1) / math.max(#colors - 1, 1), color))
		end
		if #keypoints == 1 then
			table.insert(keypoints, ColorSequenceKeypoint.new(1, colors[1]))
		end
		sparkles.Color = ColorSequence.new(keypoints)
		sparkles.Parent = fruit
		sparkles:Emit(if mutation then 40 else 10)
	end

	-- Float up, shine, then shrink away.
	local rise = TweenService:Create(
		fruit,
		TweenInfo.new(1.6, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{ Position = fruit.Position + Vector3.new(0, 6, 0) }
	)
	rise:Play()
	task.delay(1.2, function()
		if fruit.Parent then
			TweenService:Create(fruit, TweenInfo.new(0.5), { Size = Vector3.new(0.1, 0.1, 0.1) }):Play()
		end
	end)
	Debris:AddItem(fruit, 2.2)
end

return HarvestFx
