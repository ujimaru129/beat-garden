--!strict
-- The mark painted on the top of a garden plot, so each plot says what it is without any text floating in the
-- air. It follows the attributes the server sets on the soil (Stage, PlotKey, NextUnlock, Pass):
--   Empty               a white "+"            (plant here)
--   Locked, the next    a gold coin with price (buy this one)
--   Locked, later       a grey padlock         (buy the earlier plots first)
--   Locked, pass plot   a gold diamond         (Plot Pass)
--   anything else       no mark                (a plant is growing)
-- The mark of the plot whose prompt is on screen pops up bigger and bobs, so the plot you are at stands out.
-- Only the owner sees marks; other players' plots stay clean.

local PlotMarks = {}

export type Marks = {
	setFocus: (focused: boolean) -> (),
	update: (now: number) -> (),
}

local GOLD = Color3.fromHex("#FFD84D")
local GREY = Color3.fromRGB(205, 200, 225)

local function make(className: string, props: { [string]: any }, parent: Instance?): any
	local inst = Instance.new(className)
	for k, v in props do
		(inst :: any)[k] = v
	end
	inst.Parent = parent
	return inst
end

-- 400 -> "400", 14000 -> "14K", 2500 -> "2.5K": short enough for the coin.
local function shortPrice(n: number): string
	if n < 1000 then
		return tostring(n)
	end
	local k = n / 1000
	return (if k == math.floor(k) then tostring(k) else string.format("%.1f", k)) .. "K"
end

local function bar(parent: Instance, size: UDim2, color: Color3): Frame
	local f = make("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = size,
		BackgroundColor3 = color,
		BorderSizePixel = 0,
	}, parent) :: Frame
	make("UICorner", { CornerRadius = UDim.new(0, 8) }, f)
	return f
end

function PlotMarks.attach(soil: Part, mine: boolean): Marks
	local gui = make("SurfaceGui", {
		Name = "PlotMark",
		Face = Enum.NormalId.Top,
		Adornee = soil,
		SizingMode = Enum.SurfaceGuiSizingMode.FixedSize,
		CanvasSize = Vector2.new(300, 300),
		LightInfluence = 0,
		AlwaysOnTop = false,
		ResetOnSpawn = false,
	}, soil) :: SurfaceGui
	local holder = make("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(150, 150),
		BackgroundTransparency = 1,
	}, gui) :: Frame
	local scale = make("UIScale", {}, holder) :: UIScale
	local content = make("Frame", { Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1 }, holder) :: Frame
	local focused = false
	local shown = ""

	local function draw()
		local stage = soil:GetAttribute("Stage")
		local key = if stage == "Empty" then "empty" elseif stage == "Locked" then "locked" else "none"
		if not mine then
			key = "none"
		elseif key == "locked" then
			if soil:GetAttribute("Pass") == true then
				key = "pass"
			elseif tonumber(soil:GetAttribute("PlotKey")) == tonumber(soil:GetAttribute("NextUnlock")) then
				key = "coin"
			else
				key = "lock"
			end
		end
		local signature = `{key}{soil:GetAttribute("Price")}`
		if signature == shown then
			return
		end
		shown = signature
		content:ClearAllChildren()
		if key == "empty" then
			bar(content, UDim2.fromOffset(120, 24), Color3.new(1, 1, 1))
			bar(content, UDim2.fromOffset(24, 120), Color3.new(1, 1, 1))
		elseif key == "coin" then
			local coin = make("Frame", {
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.fromScale(0.5, 0.5),
				Size = UDim2.fromOffset(140, 140),
				BackgroundColor3 = GOLD,
			}, content) :: Frame
			make("UICorner", { CornerRadius = UDim.new(0.5, 0) }, coin)
			make("UIStroke", { Color = Color3.new(1, 1, 1), Thickness = 8 }, coin)
			make("TextLabel", {
				Size = UDim2.fromScale(1, 1),
				BackgroundTransparency = 1,
				Text = shortPrice(tonumber(soil:GetAttribute("Price")) or 0),
				TextScaled = true,
				Font = Enum.Font.GothamBlack,
				TextColor3 = Color3.fromRGB(120, 70, 0),
			}, coin)
			make("UIPadding", {
				PaddingTop = UDim.new(0.28, 0),
				PaddingBottom = UDim.new(0.28, 0),
				PaddingLeft = UDim.new(0.12, 0),
				PaddingRight = UDim.new(0.12, 0),
			}, coin:FindFirstChildOfClass("TextLabel"))
		elseif key == "lock" then
			-- a padlock: the shackle (a ring), then the body over its lower half
			local shackle = make("Frame", {
				AnchorPoint = Vector2.new(0.5, 0),
				Position = UDim2.new(0.5, 0, 0, 8),
				Size = UDim2.fromOffset(62, 70),
				BackgroundTransparency = 1,
			}, content) :: Frame
			make("UICorner", { CornerRadius = UDim.new(0.5, 0) }, shackle)
			make("UIStroke", { Color = GREY, Thickness = 12 }, shackle)
			local body = make("Frame", {
				AnchorPoint = Vector2.new(0.5, 0),
				Position = UDim2.new(0.5, 0, 0, 60),
				Size = UDim2.fromOffset(104, 80),
				BackgroundColor3 = GREY,
				BorderSizePixel = 0,
			}, content) :: Frame
			make("UICorner", { CornerRadius = UDim.new(0, 14) }, body)
			bar(body, UDim2.fromOffset(14, 30), Color3.fromRGB(120, 115, 150))
		elseif key == "pass" then
			local outer = make("Frame", {
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.fromScale(0.5, 0.5),
				Size = UDim2.fromOffset(100, 100),
				BackgroundColor3 = GOLD,
				Rotation = 45,
			}, content) :: Frame
			make("UICorner", { CornerRadius = UDim.new(0, 12) }, outer)
			make("UIStroke", { Color = Color3.new(1, 1, 1), Thickness = 8 }, outer)
			local inner = make("Frame", {
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.fromScale(0.5, 0.5),
				Size = UDim2.fromScale(0.45, 0.45),
				BackgroundColor3 = Color3.new(1, 1, 1),
			}, outer) :: Frame
			make("UICorner", { CornerRadius = UDim.new(0, 8) }, inner)
		end
	end

	for _, name in { "Stage", "PlotKey", "NextUnlock", "Pass", "Price" } do
		soil:GetAttributeChangedSignal(name):Connect(draw)
	end
	draw()

	return {
		setFocus = function(value: boolean)
			focused = value
		end,
		-- called every frame: the focused mark grows and bobs
		update = function(now: number)
			local target = if focused then 1.3 + 0.08 * math.sin(now * 5) else 1
			scale.Scale += (target - scale.Scale) * 0.25
		end,
	}
end

return PlotMarks
