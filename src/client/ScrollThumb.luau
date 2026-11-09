--!strict
-- A scroll indicator that is always on screen while a list has more rows than fit: a thin track with a thumb
-- that follows the list. (The built-in scroll bar of a ScrollingFrame fades in late and, with the hand-made
-- scrolling the lists use, is easy to miss.)

local ScrollThumb = {}

-- `list` is the ScrollingFrame; the indicator is drawn in `parent` at `position` / `size` (right next to the list).
function ScrollThumb.attach(list: ScrollingFrame, parent: GuiObject, position: UDim2, size: UDim2)
	list.ScrollBarThickness = 0
	local track = Instance.new("Frame")
	track.Name = "ScrollTrack"
	track.AnchorPoint = Vector2.new(1, 0)
	track.Position = position
	track.Size = size
	track.BackgroundColor3 = Color3.new(1, 1, 1)
	track.BackgroundTransparency = 0.8
	track.BorderSizePixel = 0
	track.ZIndex = 20
	track.Parent = parent
	local trackCorner = Instance.new("UICorner")
	trackCorner.CornerRadius = UDim.new(0.5, 0)
	trackCorner.Parent = track
	local thumb = Instance.new("Frame")
	thumb.Name = "Thumb"
	thumb.BackgroundColor3 = Color3.new(1, 1, 1)
	thumb.BackgroundTransparency = 0.1
	thumb.BorderSizePixel = 0
	thumb.ZIndex = 21
	thumb.Parent = track
	local thumbCorner = Instance.new("UICorner")
	thumbCorner.CornerRadius = UDim.new(0.5, 0)
	thumbCorner.Parent = thumb
	local thumbStroke = Instance.new("UIStroke")
	thumbStroke.Color = Color3.fromRGB(120, 110, 160)
	thumbStroke.Thickness = 1
	thumbStroke.Transparency = 0.5
	thumbStroke.Parent = thumb

	local function update()
		local canvas = list.AbsoluteCanvasSize.Y
		local view = list.AbsoluteSize.Y
		if canvas <= view + 1 or view <= 0 then
			track.Visible = false
			return
		end
		track.Visible = true
		local ratio = view / canvas
		local top = list.CanvasPosition.Y / (canvas - view)
		thumb.Size = UDim2.fromScale(1, math.max(ratio, 0.12))
		thumb.Position = UDim2.fromScale(0, top * (1 - math.max(ratio, 0.12)))
	end
	list:GetPropertyChangedSignal("CanvasPosition"):Connect(update)
	list:GetPropertyChangedSignal("AbsoluteCanvasSize"):Connect(update)
	list:GetPropertyChangedSignal("AbsoluteSize"):Connect(update)
	update()
end

return ScrollThumb
