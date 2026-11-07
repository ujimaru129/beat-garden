--!strict
-- Client-only touches on the garden plots, drawn locally so they cost the server nothing:
--   * a glow on every plant that pulses to the beat at night (spec: plants and fruit glow with the beat)
--   * the equipped spirit as a small floating orb next to its owner's plant
-- Both follow attributes the server already sets on each plot (SpiritKind, Stage).

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Atmosphere = require(script.Parent.Atmosphere)
local Palette = require(ReplicatedStorage.Shared.Palette)

local PlotVisuals = {}

local BPM = 120 -- the garden's own pulse (no song is playing in the world)

local SPIRIT_COLORS: { [string]: Color3 } = {
	Mochi = Palette.Base.Washi,
	Kitsune = Palette.Hues.Yuzu.Night,
}

type Entry = { soil: Part, light: PointLight, orb: Part?, orbKind: string? }

function PlotVisuals.start()
	local entries: { [Part]: Entry } = {}
	local localFolder = Instance.new("Folder")
	localFolder.Name = "PlotVisuals"
	localFolder.Parent = Workspace

	local function track(soil: Instance)
		if not soil:IsA("Part") or entries[soil] then
			return
		end
		local plant = soil:WaitForChild("Plant", 10)
		if not (plant and plant:IsA("BasePart")) then
			return
		end
		local light = Instance.new("PointLight")
		light.Name = "NightGlow"
		light.Range = 14
		light.Brightness = 0
		light.Parent = plant
		entries[soil] = { soil = soil, light = light, orb = nil, orbKind = nil }
		soil.Destroying:Connect(function()
			local entry = entries[soil]
			entries[soil] = nil
			if entry and entry.orb then
				entry.orb:Destroy()
			end
		end)
	end

	local container = Workspace:WaitForChild("Garden", 15)
	if not container then
		return
	end
	container.ChildAdded:Connect(track)
	for _, child in container:GetChildren() do
		task.spawn(track, child)
	end

	local lite = Atmosphere.isLite()

	RunService.RenderStepped:Connect(function()
		local now = Workspace:GetServerTimeNow()
		-- 0..1 saw that is highest right on the beat.
		local beat = 1 - ((now * BPM / 60) % 1)
		local night = Atmosphere.timeOfDay() == "Night"

		for soil, entry in entries do
			local plant = soil:FindFirstChild("Plant")
			if plant and plant:IsA("BasePart") then
				entry.light.Color = plant.Color
				local stage = soil:GetAttribute("Stage")
				local glows = night and stage ~= "Empty" and stage ~= "Seed"
				-- Fruit glows a little even by day.
				if glows then
					entry.light.Brightness = 0.8 + 2.2 * beat * beat
				elseif stage == "Fruit" then
					entry.light.Brightness = 0.6
				else
					entry.light.Brightness = 0
				end

				-- Spirit orb
				local kind: any = soil:GetAttribute("SpiritKind")
				if kind ~= entry.orbKind then
					entry.orbKind = kind :: string?
					if entry.orb then
						entry.orb:Destroy()
						entry.orb = nil
					end
					if kind then
						local orb = Instance.new("Part")
						orb.Name = "SpiritOrb"
						orb.Shape = Enum.PartType.Ball
						orb.Size = Vector3.new(1.4, 1.4, 1.4)
						orb.Anchored = true
						orb.CanCollide = false
						orb.CanQuery = false
						orb.CanTouch = false
						orb.CastShadow = false
						orb.Material = Enum.Material.Neon
						orb.Color = SPIRIT_COLORS[kind] or Palette.Base.Washi
						if not lite then
							local glow = Instance.new("PointLight")
							glow.Range = 8
							glow.Brightness = 1.2
							glow.Color = orb.Color
							glow.Parent = orb
						end
						orb.Parent = localFolder
						entry.orb = orb
					end
				end
				local orb = entry.orb
				if orb then
					local t = os.clock()
					orb.Position = soil.Position
						+ Vector3.new(3.6 + math.cos(t) * 0.4, 4.2 + math.sin(t * 2) * 0.5, math.sin(t) * 0.4)
				end
			end
		end
	end)
end

return PlotVisuals
