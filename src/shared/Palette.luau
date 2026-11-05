--!strict
-- Beat Garden master palette v1
-- Place in ReplicatedStorage/Shared/Palette (ModuleScript). Every color in the game comes from here.

local hex = Color3.fromHex

local Palette = {}

-- Five shared hues: same hue, day = pastel, night = neon
Palette.Hues = {
	Sakura = { Day = hex("#F7C6D9"), Night = hex("#FF4FA3") },
	Sora = { Day = hex("#BFDDF5"), Night = hex("#3FC8FF") },
	Matcha = { Day = hex("#BFE3C0"), Night = hex("#3DFFB0") },
	Yuzu = { Day = hex("#FBE7A1"), Night = hex("#FFE14D") },
	Fuji = { Day = hex("#D8C8F0"), Night = hex("#A86BFF") },
}

Palette.Base = {
	Washi = hex("#FFF8F0"), -- day ground / night text
	Sumi = hex("#3B3346"), -- day text / plant outline
	YoruSky = hex("#14112B"), -- night sky
	YoruGround = hex("#231E45"), -- night ground
	Torii = hex("#FF5A3C"), -- primary CTA, max one per screen
}

-- Rhythm lanes, left to right. Pair with distinct note shapes, never color alone.
Palette.LaneOrder = { "Sakura", "Sora", "Matcha", "Yuzu" }
Palette.LaneShapes = { "Circle", "Triangle", "Square", "Diamond" }

Palette.Rarity = {
	Common = hex("#B8B3C7"),
	Uncommon = Palette.Hues.Matcha.Day,
	Rare = Palette.Hues.Sora.Day,
	Epic = Palette.Hues.Fuji.Night, -- night version: day Fuji is too close to other pastels
	Legendary = Palette.Hues.Yuzu.Night,
}

Palette.Mutation = {
	Film = { hex("#D9C7A7") },
	Vapor = { hex("#FF71CE"), hex("#01CDFE") },
	GoldenHour = { hex("#FFB347") },
	Neon = { Palette.Hues.Sakura.Night, Palette.Hues.Sora.Night, Palette.Hues.Matcha.Night, Palette.Hues.Yuzu.Night },
	Aurora = { Palette.Hues.Matcha.Night, Palette.Hues.Sora.Night, Palette.Hues.Fuji.Night }, -- cycle in this order
}

export type TimeOfDay = "Day" | "Night"

function Palette.hue(name: string, time: TimeOfDay): Color3
	local h = Palette.Hues[name]
	assert(h, "Unknown hue: " .. name)
	return h[time]
end

function Palette.text(time: TimeOfDay): Color3
	return if time == "Day" then Palette.Base.Sumi else Palette.Base.Washi
end

-- Blend a hue between its day and night versions (alpha 0 = day, 1 = night), for the 5-second transition
function Palette.blend(name: string, alpha: number): Color3
	local h = Palette.Hues[name]
	assert(h, "Unknown hue: " .. name)
	return h.Day:Lerp(h.Night, math.clamp(alpha, 0, 1))
end

return table.freeze(Palette)
