--!strict
-- A small badge on the left of the screen that always shows what is set: the spirit that is with you (its picture,
-- name, Spirit Lv and traits) and the park (how many lots stand ready, and the Gift Boxes waiting). It is
-- only a display: the Spirits and Park buttons on the right change the settings.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GardenState = require(script.Parent.GardenState)
local Lang = require(script.Parent.Lang)
local SpiritModel = require(script.Parent.SpiritModel)
local UiTheme = require(script.Parent.UiTheme)
local Park = require(ReplicatedStorage.Shared.Garden.Park)
local Spirits = require(ReplicatedStorage.Shared.Garden.Spirits)

local StatusBadge = {}

local ICON = 40

function StatusBadge.start()
	local player = Players.LocalPlayer :: Player
	local ja = Lang.code == "ja"

	local gui = Instance.new("ScreenGui")
	gui.Name = "StatusBadge"
	gui.ResetOnSpawn = false
	gui.DisplayOrder = 20
	UiTheme.hideDuringRun(gui)

	local panel = Instance.new("Frame")
	panel.Name = "Panel"
	panel.Position = UDim2.fromOffset(12, 8) -- the screen gui starts under the Roblox top bar
	panel.Size = UDim2.fromOffset(176, ICON + 12)
	panel.Parent = gui

	local icon = Instance.new("ViewportFrame")
	icon.Name = "SpiritIcon"
	icon.Position = UDim2.fromOffset(6, 6)
	icon.Size = UDim2.fromOffset(ICON, ICON)
	icon.BackgroundColor3 = Color3.new(1, 1, 1)
	icon.BackgroundTransparency = 0.7
	icon.Ambient = Color3.fromRGB(190, 190, 205)
	icon.LightColor = Color3.new(1, 1, 1)
	icon.LightDirection = Vector3.new(-0.4, -1, -0.6)
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0.5, 0)
	corner.Parent = icon
	icon.Parent = panel

	local function makeLabel(y: number, height: number, kind: string): TextLabel
		local label = Instance.new("TextLabel")
		label.BackgroundTransparency = 1
		label.Position = UDim2.fromOffset(ICON + 12, y)
		label.Size = UDim2.new(1, -(ICON + 18), 0, height)
		label.TextXAlignment = Enum.TextXAlignment.Left
		label.TextScaled = true
		label.Text = ""
		local limit = Instance.new("UITextSizeConstraint")
		limit.MaxTextSize = if kind == "head" then 14 else 11
		limit.MinTextSize = 7
		limit.Parent = label
		label.Parent = panel
		return label
	end
	local nameLabel = makeLabel(4, 17, "head")
	local traitLabel = makeLabel(21, 15, "body")
	local parkLabel = makeLabel(36, 15, "body")

	UiTheme.watch(function()
		local theme = UiTheme.get()
		UiTheme.stylePanel(panel, theme, 14, false)
		UiTheme.styleText(nameLabel, theme, "head")
		UiTheme.styleText(traitLabel, theme, "body")
		UiTheme.styleText(parkLabel, theme, "body")
		traitLabel.TextColor3 = theme.subText
		parkLabel.TextColor3 = theme.subText
	end)

	-- The picture is built again only when the spirit changes (kind, level or traits).
	local shown = ""
	local function setIcon(kind: string?, level: number, traits: { string })
		local key = if kind then `{kind}:{level}:{table.concat(traits, "+")}` else ""
		if key == shown then
			return
		end
		shown = key
		icon:ClearAllChildren()
		local rounding = Instance.new("UICorner")
		rounding.CornerRadius = UDim.new(0.5, 0)
		rounding.Parent = icon
		if not kind then
			return
		end
		local model = SpiritModel.create(kind, traits)
		model.Parent = icon
		local camera = Instance.new("Camera")
		camera.FieldOfView = 30
		local tall = if table.find(traits, "Balloon") then 1.5 else 0
		camera.CFrame = CFrame.lookAt(Vector3.new(0, 1.9 + tall, -8.2 - tall), Vector3.new(0, 1.65 + tall, 0))
		camera.Parent = icon
		icon.CurrentCamera = camera
	end

	local function render(snapshot: GardenState.Snapshot)
		-- the spirit
		local equipped = nil
		for _, spirit in snapshot.spirits do
			if spirit.id == snapshot.equippedSpirit then
				equipped = spirit
			end
		end
		local def = if equipped then Spirits.get(equipped.kind) else nil
		if equipped and def then
			local traits: { string } = if equipped.traits then equipped.traits else {}
			local level = Spirits.levelOf(equipped.xp or 0)
			local name = Spirits.nickname(equipped.nick, Lang.code) or (if ja then def.name.ja else def.name.en)
			nameLabel.Text = `{name}  {if ja then "\u{30B9}\u{30D4}\u{30EA}\u{30C3}\u{30C8}" else "Spirit"} Lv {level}`
			local names: { string } = {}
			for _, id in traits do
				local trait = Spirits.trait(id)
				if trait then
					table.insert(names, if ja then trait.name.ja else trait.name.en)
				end
			end
			traitLabel.Text = if #names > 0
				then `\u{2728} {table.concat(names, ", ")}`
				else (if ja then "\u{3044}\u{3063}\u{3057}\u{3087}\u{306B}\u{3044}\u{308B}" else "With you")
			setIcon(equipped.kind, level, traits)
		else
			nameLabel.Text = if ja then "\u{30B9}\u{30D4}\u{30EA}\u{30C3}\u{30C8}\u{306A}\u{3057}" else "No spirit"
			traitLabel.Text = if ja
				then "\u{300C}\u{30B9}\u{30D4}\u{30EA}\u{30C3}\u{30C8}\u{300D}\u{3067}\u{9078}\u{3076}"
				else "Pick one in Spirits"
			setIcon(nil, 1, {})
		end
		-- the park
		local open, used = 0, 0
		for _, lot in Park.Lots do
			if snapshot.level.level >= lot.level then
				open += 1
				if snapshot.park.placed[lot.id] then
					used += 1
				end
			end
		end
		local boxes = snapshot.park.boxes
		parkLabel.Text = if ja
			then `\u{30D1}\u{30FC}\u{30AF}: {used}/{open} \u{533A}\u{753B}{if boxes > 0
				then `  \u{1F381}{boxes}`
				else ""}`
			else `Park: {used}/{open} lots{if boxes > 0 then `  \u{1F381}{boxes}` else ""}`
	end

	gui.Parent = player:WaitForChild("PlayerGui")
	GardenState.onChanged(render)
	local snapshot = GardenState.get()
	if snapshot then
		render(snapshot)
	end
end

return StatusBadge
