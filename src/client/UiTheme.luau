--!strict
-- One look for the UI, following the time of day (spec: pastel day, neon night, same five hues).
-- UiTheme.Style picks the look:
--   "Glass" (default): frosted glass. See-through panels and buttons with a bright rim, a tinted glow
--     at the bottom, and the 3D scene blurred behind them while a menu is open (setBlur).
--   "Pop": Night = near-black panels with glowing neon outlines, techno font;
--          Day = candy pastel panels with thick white outlines, round cute font.
-- Screens that are rebuilt each time (result, lists) read `get()` when they open; the ones that stay
-- on screen call `restyle` again when they are shown.

local Lighting = game:GetService("Lighting")
local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Atmosphere = require(script.Parent.Atmosphere)
local Palette = require(ReplicatedStorage.Shared.Palette)

local UiTheme = {}

UiTheme.Style = "Glass" -- "Glass" | "Pop"

export type Theme = {
	night: boolean,
	panel: Color3, -- panel fill
	panelEdge: Color3, -- panel outline
	text: Color3,
	subText: Color3,
	head: Enum.Font, -- titles, score, rank
	body: Enum.Font,
	hue: (name: string) -> Color3,
}

local NIGHT_PANEL = Color3.fromHex("#0B0820")
local DAY_PANEL = Color3.fromHex("#FFF1F8")

function UiTheme.get(): Theme
	local glass = UiTheme.Style == "Glass"
	local night = Atmosphere.timeOfDay() == "Night"
	local time: Palette.TimeOfDay = if night then "Night" else "Day"
	return {
		night = night,
		panel = if night then NIGHT_PANEL else DAY_PANEL,
		panelEdge = if night then Palette.Hues.Sora.Night else Color3.new(1, 1, 1),
		text = if glass
			then (if night then Color3.fromHex("#FFFFFF") else Color3.fromHex("#1F2A44"))
			elseif night then Color3.fromHex("#F4EEFF")
			else Palette.Base.Sumi,
		subText = if night then Palette.Hues.Sora.Night else Palette.Hues.Fuji.Night:Lerp(Palette.Base.Sumi, 0.4),
		head = if glass then Enum.Font.GothamBlack elseif night then Enum.Font.Michroma else Enum.Font.FredokaOne,
		body = if glass then Enum.Font.GothamBold elseif night then Enum.Font.GothamBold else Enum.Font.FredokaOne,
		hue = function(name: string): Color3
			return Palette.hue(name, time)
		end,
	}
end

local function child(parent: Instance, className: string, props: { [string]: any }): any
	local inst = Instance.new(className)
	for k, v in props do
		(inst :: any)[k] = v
	end
	inst.Parent = parent
	return inst
end

-- A glow: a wide, faint outline around the object, under a sharp one.
local function neonEdge(obj: GuiObject, color: Color3, corner: UDim)
	local old = obj:FindFirstChild("ThemeGlow")
	if old then
		old:Destroy()
	end
	local glow = child(obj, "Frame", {
		Name = "ThemeGlow",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		ZIndex = obj.ZIndex,
	})
	child(glow, "UICorner", { CornerRadius = corner })
	child(glow, "UIStroke", { Color = color, Thickness = 9, Transparency = 0.82 })
	child(glow, "UIStroke", { Color = color, Thickness = 4, Transparency = 0.6 })
end

local function setStroke(obj: GuiObject, color: Color3, thickness: number)
	local stroke = obj:FindFirstChild("ThemeStroke") :: UIStroke?
	if not stroke then
		stroke = child(obj, "UIStroke", { Name = "ThemeStroke", ApplyStrokeMode = Enum.ApplyStrokeMode.Border })
	end
	local s = stroke :: UIStroke
	s.Color = color
	s.Thickness = thickness
	s:SetAttribute("BaseColor", color)
	s:SetAttribute("BaseThickness", thickness)
end

local function setGradient(obj: GuiObject, top: Color3, bottom: Color3)
	local g = obj:FindFirstChild("ThemeGradient") :: UIGradient?
	if not g then
		g = child(obj, "UIGradient", { Name = "ThemeGradient", Rotation = 90 })
	end
	(g :: UIGradient).Color = ColorSequence.new(top, bottom)
end

local function setGradientTransparency(obj: GuiObject, top: number, bottom: number)
	local g = obj:FindFirstChild("ThemeGradient") :: UIGradient?
	if g then
		g.Transparency = NumberSequence.new(top, bottom)
	end
end

-- The bright rim of a glass edge: a thin white outline that fades from the top left to the bottom right.
local function glassRim(obj: GuiObject, thickness: number, strength: number)
	setStroke(obj, Color3.new(1, 1, 1), thickness)
	local stroke = obj:FindFirstChild("ThemeStroke") :: UIStroke
	stroke.Transparency = 0
	local rim = stroke:FindFirstChild("RimGradient") :: UIGradient?
	if not rim then
		rim = child(stroke, "UIGradient", { Name = "RimGradient", Rotation = 35 })
	end
	(rim :: UIGradient).Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 1 - strength),
		NumberSequenceKeypoint.new(0.5, 1 - strength * 0.35),
		NumberSequenceKeypoint.new(1, 1 - strength * 0.7),
	})
end

-- A UIGradient also tints a label's or button's own text, so for those the glass is drawn on a child
-- frame that sits *behind* the text (ZIndex 1, the text object itself 2). That needs the ScreenGui to
-- order by ZIndex across parents and children ("Global").
local function ensureGlobalZ(obj: GuiObject)
	local function apply(): boolean
		local gui = obj:FindFirstAncestorOfClass("ScreenGui")
		if gui then
			gui.ZIndexBehavior = Enum.ZIndexBehavior.Global
			return true
		end
		return false
	end
	if apply() then
		return
	end
	local connection: RBXScriptConnection
	connection = obj.AncestryChanged:Connect(function()
		if apply() then
			connection:Disconnect()
		end
	end)
end

-- The object the glass look is drawn on: the object itself, or for text objects a frame behind the text.
local function glassHost(obj: GuiObject, radius: number): GuiObject
	if not (obj:IsA("TextLabel") or obj:IsA("TextButton")) then
		if not obj:FindFirstChildOfClass("UICorner") then
			child(obj, "UICorner", { CornerRadius = UDim.new(0, radius) })
		end
		return obj
	end
	local textObj = obj :: any
	local frame = obj:FindFirstChild("ThemeBg") :: Frame?
	if not frame then
		local created =
			child(obj, "Frame", { Name = "ThemeBg", BorderSizePixel = 0, Active = false, ZIndex = 1 }) :: Frame
		child(created, "UICorner", { CornerRadius = UDim.new(0, radius) })
		textObj.ZIndex = 2
		ensureGlobalZ(obj)
		frame = created
	end
	local bg = frame :: Frame
	bg.BackgroundColor3 = Color3.new(1, 1, 1)
	bg.BackgroundTransparency = 0
	-- A UIPadding on the text object would inset the frame: stretch it back out to the full size.
	local pad = obj:FindFirstChildOfClass("UIPadding")
	if pad then
		local sL, sR, sT, sB =
			pad.PaddingLeft.Scale, pad.PaddingRight.Scale, pad.PaddingTop.Scale, pad.PaddingBottom.Scale
		local oL, oR, oT, oB =
			pad.PaddingLeft.Offset, pad.PaddingRight.Offset, pad.PaddingTop.Offset, pad.PaddingBottom.Offset
		local kx, ky = 1 / (1 - sL - sR), 1 / (1 - sT - sB)
		bg.Position = UDim2.new(-sL * kx, -sL * kx * (oL + oR) - oL, -sT * ky, -sT * ky * (oT + oB) - oT)
		bg.Size = UDim2.new(kx, (oL + oR) * kx, ky, (oT + oB) * ky)
	else
		bg.Position = UDim2.fromScale(0, 0)
		bg.Size = UDim2.fromScale(1, 1)
	end
	textObj.BackgroundTransparency = 1
	return bg
end

local function panelGlass(obj: GuiObject, theme: Theme, radius: number?)
	local host = glassHost(obj, radius or 16)
	host.BackgroundColor3 = Color3.new(1, 1, 1)
	host.BackgroundTransparency = 0
	if theme.night then
		setGradient(host, Color3.fromHex("#5A4DD0"), Color3.fromHex("#0E0A2E"))
		setGradientTransparency(host, 0.45, 0.25)
	else
		setGradient(host, Color3.fromHex("#FFFFFF"), Color3.fromHex("#BFD3FF"))
		setGradientTransparency(host, 0.25, 0.45)
	end
	glassRim(host, 1.6, 0.9)
end

local function buttonGlass(button: TextButton, theme: Theme, hueName: string, radius: number?)
	local host = glassHost(button, radius or 14)
	local strong = Palette.hue(hueName, "Night")
	button.Font = theme.head
	if theme.night then
		-- dark glass, the hue glowing up from the bottom edge
		setGradient(host, strong:Lerp(Color3.new(0, 0, 0), 0.8), strong)
		setGradientTransparency(host, 0.5, 0.2)
		button.TextColor3 = Color3.new(1, 1, 1)
		button.TextStrokeColor3 = Color3.new(0, 0, 0)
		button.TextStrokeTransparency = 0.55
	else
		-- bright glass, the hue glowing up from the bottom edge
		setGradient(host, strong:Lerp(Color3.new(1, 1, 1), 0.6), strong:Lerp(Color3.new(1, 1, 1), 0.1))
		setGradientTransparency(host, 0.3, 0.05)
		button.TextColor3 = theme.text
		button.TextStrokeTransparency = 1
	end
	glassRim(host, 1.6, 0.9)
end

-- Panel / card look.
-- `glow = false` skips the soft outer glow (needed when the object has a UIPadding).
function UiTheme.stylePanel(obj: GuiObject, theme: Theme, radius: number?, glow: boolean?)
	if UiTheme.Style == "Glass" then
		panelGlass(obj, theme, radius)
		return
	end
	local corner = UDim.new(0, radius or 16)
	obj.BackgroundColor3 = Color3.new(1, 1, 1)
	obj.BackgroundTransparency = if theme.night then 0.06 else 0
	if not obj:FindFirstChildOfClass("UICorner") then
		child(obj, "UICorner", { CornerRadius = corner })
	end
	if theme.night then
		setGradient(obj, Color3.fromHex("#17104A"), theme.panel)
		setStroke(obj, theme.panelEdge, 2.5)
		if glow ~= false then
			neonEdge(obj, theme.panelEdge, corner)
		end
	else
		setGradient(obj, Color3.fromHex("#FFE3F1"), Color3.fromHex("#E4E8FF"))
		setStroke(obj, theme.panelEdge, 5)
	end
end

-- Button look in one of the five hues ("Sakura" | "Sora" | "Matcha" | "Yuzu" | "Fuji").
-- `glow = false` skips the soft outer glow (needed when the button has a UIPadding, which would inset it).
function UiTheme.styleButton(button: TextButton, theme: Theme, hueName: string, radius: number?, glow: boolean?)
	if UiTheme.Style == "Glass" then
		buttonGlass(button, theme, hueName, radius)
		return
	end
	local color = theme.hue(hueName)
	local corner = UDim.new(0, radius or 14)
	if not button:FindFirstChildOfClass("UICorner") then
		child(button, "UICorner", { CornerRadius = corner })
	end
	button.BackgroundColor3 = Color3.new(1, 1, 1)
	button.Font = theme.head
	if theme.night then
		button.BackgroundTransparency = 0.1
		setGradient(button, color:Lerp(Color3.new(0, 0, 0), 0.82), Color3.fromHex("#0B0820"))
		setStroke(button, color, 2.5)
		if glow ~= false then
			neonEdge(button, color, corner)
		end
		button.TextColor3 = color:Lerp(Color3.new(1, 1, 1), 0.35)
		button.TextStrokeColor3 = color
		button.TextStrokeTransparency = 0.65
	else
		button.BackgroundTransparency = 0
		setGradient(button, color:Lerp(Color3.new(1, 1, 1), 0.35), color)
		setStroke(button, Color3.new(1, 1, 1), 4)
		button.TextColor3 = Palette.Base.Sumi
		button.TextStrokeTransparency = 1
	end
end

-- Text look. `kind`: "head" (titles, numbers) or "body".
function UiTheme.styleText(target: TextLabel | TextButton, theme: Theme, kind: string?)
	local label = target :: any
	label.Font = if kind == "head" then theme.head else theme.body
	label.TextColor3 = theme.text
	label.TextStrokeTransparency = 1
	if UiTheme.Style ~= "Glass" and theme.night then
		label.TextStrokeColor3 = theme.panelEdge
		label.TextStrokeTransparency = if kind == "head" then 0.7 else 1
	end
end

-- Blurs the 3D scene behind the UI while a menu is open (what makes the glass look like glass).
-- Several menus can ask at once; the blur stays until every one of them has let go.
local blurKeys: { [string]: boolean? } = {}
local blurEffect: BlurEffect? = nil
function UiTheme.setBlur(key: string, on: boolean)
	blurKeys[key] = if on then true else nil -- The always-on HUD and the tutorial banner step aside while a menu is open.
	(Players.LocalPlayer :: Player):SetAttribute("MenuOpen", if next(blurKeys) ~= nil then true else nil)
	if UiTheme.Style ~= "Glass" then
		return
	end
	local effect = blurEffect
	if not effect then
		local created = Instance.new("BlurEffect")
		created.Name = "BeatGardenUiBlur"
		created.Size = 0
		created.Parent = Lighting
		blurEffect = created
		effect = created
	end
	local target = if next(blurKeys) ~= nil then 16 else 0
	TweenService:Create(effect :: BlurEffect, TweenInfo.new(0.2), { Size = target }):Play()
end

-- Accent for the one thing the tutorial wants tapped: the outline turns orange-red and thick.
function UiTheme.setAccent(obj: GuiObject, on: boolean)
	local host = obj:FindFirstChild("ThemeBg") or obj
	local stroke = host:FindFirstChild("ThemeStroke") :: UIStroke?
	if not stroke then
		return
	end
	local baseColor = stroke:GetAttribute("BaseColor")
	local baseThickness = stroke:GetAttribute("BaseThickness")
	stroke.Color = if on then Palette.Base.Torii elseif typeof(baseColor) == "Color3" then baseColor else stroke.Color
	stroke.Thickness = if on then 7 elseif type(baseThickness) == "number" then baseThickness else stroke.Thickness
end

-- The always-on HUD buttons sit on the right edge and are hidden while a rhythm run is going.
function UiTheme.hideDuringRun(gui: ScreenGui)
	local player = Players.LocalPlayer :: Player
	local function update()
		gui.Enabled = player:GetAttribute("InRhythm") ~= true and player:GetAttribute("MenuOpen") ~= true
	end
	update()
	player:GetAttributeChangedSignal("InRhythm"):Connect(update)
	player:GetAttributeChangedSignal("MenuOpen"):Connect(update)
end

-- Styles `button` now and again whenever day turns to night or back (for UI that stays on screen).
local watchers: { () -> () } = {}
local lastNight: boolean? = nil
local function startWatching()
	if lastNight ~= nil then
		return
	end
	lastNight = Atmosphere.timeOfDay() == "Night"
	task.spawn(function()
		while true do
			task.wait(1)
			local night = Atmosphere.timeOfDay() == "Night"
			if night ~= lastNight then
				lastNight = night
				for _, fn in watchers do
					fn()
				end
			end
		end
	end)
end

function UiTheme.watch(restyle: () -> ())
	startWatching()
	restyle()
	table.insert(watchers, restyle)
end

return UiTheme
