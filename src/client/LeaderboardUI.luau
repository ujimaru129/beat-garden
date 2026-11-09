--!strict
-- The ranking screen: a HUD button that opens the top players of the global boards (garden level, book entries).
-- The server keeps a cache of the boards, so opening the screen is cheap. The first row switches the board; your
-- own row is highlighted, and your own number is shown at the bottom when you are not in the top list.

local Players = game:GetService("Players")
local ProximityPromptService = game:GetService("ProximityPromptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GardenState = require(script.Parent.GardenState)
local Leaderboard = require(ReplicatedStorage.Shared.Garden.Leaderboard)
local ListModal = require(script.Parent.ListModal)
local MarketUI = require(script.Parent.MarketUI)
local Palette = require(ReplicatedStorage.Shared.Palette)
local Toast = require(script.Parent.Toast)
local UiTheme = require(script.Parent.UiTheme)

local LeaderboardUI = {}

type Entry = { userId: number, name: string, value: number }

function LeaderboardUI.start()
	local player = Players.LocalPlayer :: Player
	local boardIndex = 1
	local boards: { [string]: { Entry } } = {}

	local modal = ListModal.create("Ranking", function()
		ProximityPromptService.Enabled = true
	end)

	local rebuild: () -> ()
	local function rebuildRows()
		local board = Leaderboard.Boards[boardIndex]
		local snapshot = GardenState.get()
		local rows: { ListModal.Row } = {
			{
				text = `Ranking: {Leaderboard.title(board)}   (tap to switch)`,
				color = Palette.Hues.Fuji.Night,
				onTap = function()
					boardIndex = boardIndex % #Leaderboard.Boards + 1
					rebuild()
				end,
			},
		}
		local entries = boards[board] or {}
		local inTop = false
		for rank, entry in entries do
			local mine = entry.userId == player.UserId
			inTop = inTop or mine
			table.insert(rows, {
				text = `{rank}. {entry.name}   {Leaderboard.format(board, entry.value)}`,
				color = if mine then Palette.Hues.Yuzu.Night elseif rank <= 3 then Palette.Hues.Sora.Night else nil,
			})
		end
		if #entries == 0 then
			table.insert(rows, { text = "No ranking yet. Check back in a few minutes" })
		end
		if snapshot and not inTop then
			local own = Leaderboard.valueFor(board, snapshot.xp, snapshot.collection)
			table.insert(rows, {
				note = true,
				text = `You: {Leaderboard.format(board, own)}  (not in the top {Leaderboard.TopCount} yet)`,
			})
		end
		modal.setRows(rows)
	end
	rebuild = function()
		modal.setTitle("Ranking")
		rebuildRows()
	end

	local gui = Instance.new("ScreenGui")
	gui.Name = "RankingHud"
	gui.ResetOnSpawn = false
	gui.DisplayOrder = 30
	UiTheme.hideDuringRun(gui)
	local button = MarketUI.makeHudButton(gui, "Ranking", 284)
	gui.Parent = player:WaitForChild("PlayerGui")

	button.Activated:Connect(function()
		local result = GardenState.call("leaderboard")
		if result.ok then
			boards = result.boards
		else
			Toast.show(result.reason or "ranking not available")
		end
		rebuild()
		ProximityPromptService.Enabled = false
		modal.open()
	end)
end

return LeaderboardUI
