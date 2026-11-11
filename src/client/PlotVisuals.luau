--!strict
-- Client-only touches on the garden plots, drawn locally so they cost the server nothing:
--   * a glow on every plant that pulses to the beat at night (spec: plants and fruit glow with the beat)
--   * the equipped spirit as a little character next to its owner's plant
-- Both follow attributes the server already sets on each plot (SpiritKind, Stage).

local Players = game:GetService("Players")
local ProximityPromptService = game:GetService("ProximityPromptService")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Atmosphere = require(script.Parent.Atmosphere)
local PlotMarks = require(script.Parent.PlotMarks)
local SpiritModel = require(script.Parent.SpiritModel)

local PlotVisuals = {}

local BPM = 120 -- the garden's own pulse (no song is playing in the world)

type Entry = {
	soil: Part,
	light: PointLight,
	orb: Model?,
	orbKind: string?,
	glows: { BasePart },
	marks: PlotMarks.Marks,
}

function PlotVisuals.start()
	local entries: { [Part]: Entry } = {}
	local localFolder = Instance.new("Folder")
	localFolder.Name = "PlotVisuals"
	localFolder.Parent = Workspace

	-- The beacon and path of a territory are for its owner only: hide them on everyone else's screen.
	local function trackMarker(folder: Folder)
		local mine = folder:GetAttribute("OwnerUserId") == (Players.LocalPlayer :: Player).UserId
		local function apply(inst: Instance)
			if inst:IsA("BasePart") and inst:GetAttribute("OwnerOnly") == true then
				inst.LocalTransparencyModifier = if mine then 0 else 1
			end
		end
		folder.DescendantAdded:Connect(apply)
		for _, inst in folder:GetDescendants() do
			apply(inst)
		end
	end

	local function track(soil: Instance)
		if soil:IsA("Folder") and string.sub(soil.Name, 1, 10) == "Territory_" then
			trackMarker(soil)
			return
		end
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
		local glows: { BasePart } = {}
		for _, child in soil:GetChildren() do
			if child:IsA("BasePart") and child:GetAttribute("PlotGlow") == true then
				table.insert(glows, child)
			end
		end
		local mine = soil:GetAttribute("OwnerUserId") == (Players.LocalPlayer :: Player).UserId
		entries[soil] = {
			soil = soil,
			light = light,
			orb = nil,
			orbKind = nil,
			glows = glows,
			marks = PlotMarks.attach(soil, mine),
		}
		-- the decorations may arrive after the plant: pick up the lights that come later too
		soil.ChildAdded:Connect(function(child)
			if child:IsA("BasePart") and child:GetAttribute("PlotGlow") == true then
				table.insert(glows, child)
			end
		end)
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

	-- The plot whose prompt is on screen pops up (its mark grows and bobs).
	ProximityPromptService.PromptShown:Connect(function(prompt: ProximityPrompt)
		local entry = if prompt.Name == "TendPrompt" then entries[prompt.Parent :: any] else nil
		if entry then
			entry.marks.setFocus(true)
		end
	end)
	ProximityPromptService.PromptHidden:Connect(function(prompt: ProximityPrompt)
		local entry = if prompt.Name == "TendPrompt" then entries[prompt.Parent :: any] else nil
		if entry then
			entry.marks.setFocus(false)
		end
	end)

	RunService.RenderStepped:Connect(function()
		local now = Workspace:GetServerTimeNow()
		-- 0..1 saw that is highest right on the beat.
		local beat = 1 - ((now * BPM / 60) % 1)
		local night = Atmosphere.timeOfDay() == "Night"

		for soil, entry in entries do
			entry.marks.update(os.clock())
			-- the neon lights of the fancier plots pulse on the beat
			if soil:GetAttribute("Stage") ~= "Locked" then
				for _, glow in entry.glows do
					glow.Transparency = 0.45 * (1 - beat) * (1 - beat)
				end
			end
			local plant = soil:FindFirstChild("Plant")
			if plant and plant:IsA("BasePart") then
				entry.light.Color = plant.Color
				local stage = soil:GetAttribute("Stage")
				local glows = night and stage ~= "Empty" and stage ~= "Seed"
				-- Fruit glows a little even by day.
				if glows then
					entry.light.Brightness = 0.8 + 2.2 * beat * beat
				elseif stage == "Fruit" and soil:GetAttribute("Mutation") ~= nil then
					-- a mutated fruit shines on the beat, day and night
					entry.light.Brightness = 1.6 + 2.4 * beat * beat
					entry.light.Range = 18
				elseif stage == "Fruit" then
					entry.light.Brightness = 0.6
				else
					entry.light.Brightness = 0
				end

				-- The equipped spirit: a little character that hops on the beat next to the plant
				local kind: any = nil -- the equipped spirit follows its player now (PetFx), no longer stands by the plant
				if kind ~= entry.orbKind then
					entry.orbKind = kind :: string?
					if entry.orb then
						entry.orb:Destroy()
						entry.orb = nil
					end
					if kind then
						local spirit = SpiritModel.create(kind :: string)
						spirit.Parent = localFolder
						entry.orb = spirit
					end
				end
				local spirit = entry.orb
				if spirit then
					local t = os.clock()
					local hop = math.abs(math.sin(math.pi * ((t * BPM / 60) % 1))) * 0.9
					local ground = soil.Position
						+ Vector3.new(4.5 + math.cos(t * 0.5) * 0.4, soil.Size.Y / 2, math.sin(t * 0.5) * 0.4)
					local spot = ground + Vector3.new(0, hop, 0)
					local lookAt = Vector3.new(soil.Position.X, spot.Y, soil.Position.Z)
					spirit:PivotTo(CFrame.lookAt(spot, lookAt))
				end
			end
		end
	end)
end

return PlotVisuals
