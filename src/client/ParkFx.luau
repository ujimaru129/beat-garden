--!strict
-- Moves the park attractions (built by the server, see server/ParkBuilder) on this client only:
--   ParkSpin  - a Model that turns around its pivot (SpinSpeed rad/s, SpinAxis "X"|"Y"|"Z")
--   ParkSwing - a Model that swings like a pendulum around its pivot's X axis (SwingAngle, SwingSpeed, SwingPhase)
--   ParkBob   - a Model that floats up and down (BobAmount, BobSpeed, BobPhase)
--   ParkRainbow - a part whose colour runs through the rainbow
-- Only things near the camera are moved, so a full island stays cheap.

local CollectionService = game:GetService("CollectionService")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local ParkFx = {}

local NEAR = 240 -- studs from the camera; farther things stand still
local RAINBOW_STEP = 0.1 -- seconds between colour updates

type Mover = { model: Model, base: CFrame }

local spinners: { [Model]: Mover } = {}
local swingers: { [Model]: Mover } = {}
local bobbers: { [Model]: Mover } = {}
local rainbows: { [BasePart]: number } = {}

local function register(inst: Instance)
	if inst:IsA("Model") then
		local mover = { model = inst, base = inst:GetPivot() }
		if CollectionService:HasTag(inst, "ParkSpin") then
			spinners[inst] = mover
		elseif CollectionService:HasTag(inst, "ParkSwing") then
			swingers[inst] = mover
		elseif CollectionService:HasTag(inst, "ParkBob") then
			bobbers[inst] = mover
		end
	elseif inst:IsA("BasePart") and CollectionService:HasTag(inst, "ParkRainbow") then
		rainbows[inst] = inst.Position.X * 0.05 + inst.Position.Z * 0.03
	end
end

local function unregister(inst: Instance)
	if inst:IsA("Model") then
		spinners[inst] = nil
		swingers[inst] = nil
		bobbers[inst] = nil
	elseif inst:IsA("BasePart") then
		rainbows[inst] = nil
	end
end

local function axisRotation(axis: string, angle: number): CFrame
	if axis == "X" then
		return CFrame.Angles(angle, 0, 0)
	elseif axis == "Z" then
		return CFrame.Angles(0, 0, angle)
	end
	return CFrame.Angles(0, angle, 0)
end

function ParkFx.start()
	for _, tag in { "ParkSpin", "ParkSwing", "ParkBob", "ParkRainbow" } do
		CollectionService:GetInstanceAddedSignal(tag):Connect(register)
		CollectionService:GetInstanceRemovedSignal(tag):Connect(unregister)
		for _, inst in CollectionService:GetTagged(tag) do
			register(inst)
		end
	end

	local sinceRainbow = 0
	RunService.RenderStepped:Connect(function(dt: number)
		local camera = Workspace.CurrentCamera
		if not camera then
			return
		end
		local eye = camera.CFrame.Position
		local now = os.clock()
		local function near(mover: Mover): boolean
			return (mover.base.Position - eye).Magnitude < NEAR
		end
		for model, mover in spinners do
			if near(mover) then
				local speed = model:GetAttribute("SpinSpeed") or 0.5
				local axis = model:GetAttribute("SpinAxis") or "Y"
				model:PivotTo(mover.base * axisRotation(axis, now * speed))
			end
		end
		for model, mover in swingers do
			if near(mover) then
				local angle = model:GetAttribute("SwingAngle") or 0.5
				local speed = model:GetAttribute("SwingSpeed") or 1.5
				local phase = model:GetAttribute("SwingPhase") or 0
				model:PivotTo(mover.base * CFrame.Angles(math.sin(now * speed + phase) * angle, 0, 0))
			end
		end
		for model, mover in bobbers do
			if near(mover) then
				local amount = model:GetAttribute("BobAmount") or 1
				local speed = model:GetAttribute("BobSpeed") or 1
				local phase = model:GetAttribute("BobPhase") or 0
				model:PivotTo(mover.base * CFrame.new(0, math.sin(now * speed + phase) * amount, 0))
			end
		end
		sinceRainbow += dt
		if sinceRainbow >= RAINBOW_STEP then
			sinceRainbow = 0
			for part, offset in rainbows do
				if (part.Position - eye).Magnitude < NEAR then
					part.Color = Color3.fromHSV((now * 0.15 + offset) % 1, 0.65, 1)
				end
			end
		end
	end)
end

return ParkFx
