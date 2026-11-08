--!strict
-- Day / night look (spec: the same garden turns from pastel day into neon night through grading
-- alone). Roblox cannot load a LUT, so the look is a preset of Lighting, ColorCorrection, Bloom and
-- Atmosphere values, tweened over 5 seconds at dusk and dawn. The clock is shared (DayNight), so
-- every player sees the same time of day. Lighting changes made on the client stay on the client.
--
-- Testing in Studio: set the LocalPlayer attribute "ForceTimeOfDay" to "Day" or "Night" (key N does it).

local Lighting = game:GetService("Lighting")
local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local DayNight = require(game:GetService("ReplicatedStorage").Shared.DayNight)
local Palette = require(game:GetService("ReplicatedStorage").Shared.Palette)

local Atmosphere = {}

local hue = Palette.hue

-- Same five hues by day and night; only the lightness and saturation change.
local PRESETS = {
	Day = {
		lighting = {
			ClockTime = 14,
			Brightness = 3,
			Ambient = hue("Sakura", "Day"):Lerp(Palette.Base.Washi, 0.6),
			OutdoorAmbient = hue("Sora", "Day"):Lerp(Palette.Base.Washi, 0.5),
			ExposureCompensation = 0,
		},
		-- Dreamy candy pastel: pink-white tint, lifted saturation, a soft glow over everything.
		grade = { TintColor = Color3.fromHex("#FFEAF6"), Saturation = 0.3, Contrast = 0.04, Brightness = 0.04 },
		bloom = { Intensity = 0.55, Size = 30, Threshold = 1.0 },
		atmosphere = {
			Density = 0.3,
			Color = hue("Sakura", "Day"),
			Decay = hue("Fuji", "Day"),
			Haze = 1.6,
			Glare = 0.2,
		},
	},
	Night = {
		lighting = {
			ClockTime = 0,
			Brightness = 1.3,
			Ambient = Palette.Base.YoruGround:Lerp(hue("Fuji", "Night"), 0.3),
			OutdoorAmbient = hue("Fuji", "Night"):Lerp(Palette.Base.YoruSky, 0.5),
			ExposureCompensation = 0,
		},
		grade = {
			TintColor = hue("Fuji", "Night"):Lerp(Color3.new(1, 1, 1), 0.5),
			Saturation = 0.6,
			Contrast = 0.2,
			Brightness = -0.03,
		},
		bloom = { Intensity = 1.6, Size = 32, Threshold = 0.75 },
		atmosphere = {
			Density = 0.45,
			Color = Palette.Base.YoruSky,
			Decay = Palette.Base.YoruGround,
			Haze = 2,
			Glare = 0.4,
		},
	},
}

local player = Players.LocalPlayer :: Player

local function ensure(className: string, name: string): Instance
	local existing = Lighting:FindFirstChild(name)
	if existing and existing.ClassName == className then
		return existing
	end
	local inst = Instance.new(className)
	inst.Name = name
	inst.Parent = Lighting
	return inst
end

-- Low graphics quality drops Bloom (and the particle effects ask `isLite` too).
function Atmosphere.isLite(): boolean
	if player:GetAttribute("LiteMode") ~= nil then
		return player:GetAttribute("LiteMode") == true
	end
	local ok, level = pcall(function()
		return UserSettings():GetService("UserGameSettings").SavedQualityLevel.Value
	end)
	-- 0 = automatic. Levels 1..3 are the lowest manual settings.
	return ok and level >= 1 and level <= 3
end

function Atmosphere.timeOfDay(): string
	local forced = player:GetAttribute("ForceTimeOfDay")
	if forced == "Day" or forced == "Night" then
		return forced
	end
	return DayNight.timeOfDay(Workspace:GetServerTimeNow())
end

function Atmosphere.start()
	local grade = ensure("ColorCorrectionEffect", "BeatGardenGrade") :: ColorCorrectionEffect
	local bloom = ensure("BloomEffect", "BeatGardenBloom") :: BloomEffect
	local atmosphere = ensure("Atmosphere", "BeatGardenAtmosphere") :: Atmosphere
	local lite = Atmosphere.isLite()
	bloom.Enabled = not lite
	local current = Atmosphere.timeOfDay()
	-- During a rhythm run there is no bloom and no haze: they smear the notes into blobs.
	local function updateBloom()
		local info = TweenInfo.new(0.3)
		local running = player:GetAttribute("InRhythm") == true
		local preset = (PRESETS :: any)[current]
		TweenService:Create(bloom, info, (if running then { Intensity = 0 } else preset.bloom) :: any):Play()
		TweenService
			:Create(
				atmosphere,
				info,
				(if running then { Density = 0, Haze = 0, Glare = 0 } else preset.atmosphere) :: any
			)
			:Play()
	end
	player:GetAttributeChangedSignal("InRhythm"):Connect(updateBloom)

	local function apply(time: string, seconds: number)
		local preset = (PRESETS :: any)[time]
		local info = TweenInfo.new(seconds, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut)
		TweenService:Create(Lighting, info, preset.lighting :: any):Play()
		TweenService:Create(grade, info, preset.grade :: any):Play()
		TweenService:Create(bloom, info, preset.bloom :: any):Play()
		TweenService:Create(atmosphere, info, preset.atmosphere :: any):Play()
	end

	apply(current, 0.05) -- jump straight to the right look when joining

	task.spawn(function()
		while true do
			task.wait(0.5)
			local now = Atmosphere.timeOfDay()
			if now ~= current then
				current = now
				apply(now, DayNight.TransitionSeconds)
			end
		end
	end)

	-- Studio: N flips between day and night to look at both.
	UserInputService.InputBegan:Connect(function(input, gameProcessed)
		if gameProcessed or input.KeyCode ~= Enum.KeyCode.N or not game:GetService("RunService"):IsStudio() then
			return
		end
		player:SetAttribute("ForceTimeOfDay", if Atmosphere.timeOfDay() == "Day" then "Night" else "Day")
	end)
end

return Atmosphere
