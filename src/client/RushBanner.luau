--!strict
-- The BPM Rush banner: a short line at the left of the screen while a Rush is on (or about to start), with the
-- genre and a countdown. Worked out from the same clock as the server (Garden/Rush), nothing is sent.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Genres = require(ReplicatedStorage.Shared.Garden.Genres)
local Rush = require(ReplicatedStorage.Shared.Garden.Rush)
local Lang = require(script.Parent.Lang)
local Toast = require(script.Parent.Toast)
local TipsUI = require(script.Parent.TipsUI)
local UiTheme = require(script.Parent.UiTheme)

local RushBanner = {}

function RushBanner.start()
	local gui = Instance.new("ScreenGui")
	gui.Name = "RushBanner"
	gui.ResetOnSpawn = false
	gui.DisplayOrder = 28

	local label = Instance.new("TextLabel")
	label.Position = UDim2.fromOffset(16, 72)
	label.Size = UDim2.fromOffset(250, 34)
	label.TextScaled = true
	label.Visible = false
	label.Parent = gui
	local limit = Instance.new("UITextSizeConstraint")
	limit.MaxTextSize = 18
	limit.Parent = label
	local padding = Instance.new("UIPadding")
	padding.PaddingLeft = UDim.new(0, 8)
	padding.PaddingRight = UDim.new(0, 8)
	padding.PaddingTop = UDim.new(0, 4)
	padding.PaddingBottom = UDim.new(0, 4)
	padding.Parent = label
	UiTheme.watch(function()
		local theme = UiTheme.get()
		UiTheme.stylePanel(label, theme, 10)
		UiTheme.styleText(label, theme, "head")
	end)
	UiTheme.hideDuringRun(gui)
	gui.Parent = (Players.LocalPlayer :: Player):WaitForChild("PlayerGui")

	local wasActive = false
	task.spawn(function()
		while true do
			local now = math.floor(Workspace:GetServerTimeNow())
			local state = Rush.state(now)
			if state then
				local names = (Genres.Names :: any)[state.genre]
				local genre = if Lang.code == "ja" then names.ja else names.en
				local time = `{state.secondsLeft // 60}:{string.format("%02d", state.secondsLeft % 60)}`
				label.Text =
					Lang.t(if state.active then `BPM RUSH  {genre}  {time}` else `BPM Rush soon: {genre}  {time}`)
				label.Visible = true
				if state.active and not wasActive then
					Toast.show(`BPM Rush! {genre} seeds mutate more for a while`)
					TipsUI.show("rush")
				end
				wasActive = state.active
			else
				label.Visible = false
				wasActive = false
			end
			task.wait(1)
		end
	end)
end

return RushBanner
