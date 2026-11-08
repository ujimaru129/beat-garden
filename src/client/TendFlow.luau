--!strict
-- Client side of the plant prompt. What the prompt does depends on the plant's stage:
--   Empty -> pick a seed to plant      Fruit -> harvest      anything else -> Tend (rhythm run)
-- Tend: pick a difficulty -> play the chart -> see the result. The server hands out the chart and
-- decides every number; this module only shows and plays.

local Players = game:GetService("Players")
local ProximityPromptService = game:GetService("ProximityPromptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local DifficultyPicker = require(script.Parent.DifficultyPicker)
local GardenState = require(script.Parent.GardenState)
local HarvestFx = require(script.Parent.HarvestFx)
local ListModal = require(script.Parent.ListModal)
local Mutations = require(ReplicatedStorage.Shared.Garden.Mutations)
local ResultScreen = require(script.Parent.ResultScreen)
local RhythmRunner = require(script.Parent.RhythmRunner)
local Seeds = require(ReplicatedStorage.Shared.Garden.Seeds)
local Songs = require(ReplicatedStorage.Shared.Songs)
local Toast = require(script.Parent.Toast)

local TendFlow = {}

local function seedName(seedId: string): string
	local seed = Seeds.get(seedId)
	return if seed then seed.name.en else seedId
end

function TendFlow.start()
	local remote = ReplicatedStorage:WaitForChild("Tend", 10) :: RemoteFunction?
	if not remote then
		warn("[TendFlow] Tend remote not found")
		return
	end
	local tend: RemoteFunction = remote
	local player = Players.LocalPlayer :: Player
	local picking = false
	local chosenSongId = ""

	-- The prompt button sits over the lane buttons and the pickers, so it is hidden while they are up.
	local function setPromptsEnabled(enabled: boolean)
		ProximityPromptService.Enabled = enabled
	end

	-- Difficulty picker (Tend) --------------------------------------------------------------
	local picker: DifficultyPicker.Picker
	local function closePicker()
		picking = false
		picker.setVisible(false)
	end
	local function cancelPicker()
		closePicker()
		setPromptsEnabled(true)
	end

	local function onPick(difficulty: string)
		closePicker()
		local info = tend:InvokeServer("begin", { difficulty = difficulty, songId = chosenSongId })
		if not (info and info.ok) then
			setPromptsEnabled(true)
			Toast.show(`Can't tend now: {if info then info.reason else "no answer"}`)
			return
		end
		local started = RhythmRunner.play({
			segment = info.segment,
			bpm = info.bpm,
			beatsMs = info.beatsMs,
			audioAssetId = info.audioAssetId,
			offsetMs = info.offsetMs,
			difficulty = info.difficulty,
		}, function(summary)
			local result = tend:InvokeServer("submit", summary)
			if result and result.ok then
				-- The result screen re-enables the prompts when it is closed.
				ResultScreen.show({
					songName = result.songName,
					difficulty = result.difficulty,
					rank = result.rank,
					score = result.score,
					counts = result.counts,
					maxCombo = result.maxCombo,
					points = result.points,
					stage = result.stage,
					fraction = result.fraction,
				}, function()
					setPromptsEnabled(true)
				end)
			else
				setPromptsEnabled(true)
				Toast.show(`Run not counted: {if result then result.reason else "no answer"}`)
			end
		end)
		if not started then
			setPromptsEnabled(true)
			Toast.show("Already playing")
		end
	end

	picker = DifficultyPicker.create(onPick, cancelPicker)
	picker.setVisible(false)

	-- Song picker (Tend, step 1): the player chooses the song, then the difficulty.
	local advancing = false
	local songModal = ListModal.create("Choose a song", function()
		if advancing then
			return
		end
		picking = false
		setPromptsEnabled(true)
	end)
	local function openSongPicker()
		local rows: { ListModal.Row } = {}
		for _, song in Songs.List do
			local seconds = math.floor(song.durationMs / 1000 + 0.5)
			table.insert(rows, {
				text = `{song.name}   {seconds // 60}:{string.format("%02d", seconds % 60)}`,
				onTap = function()
					advancing = true
					songModal.close()
					advancing = false
					chosenSongId = song.songId
					picker.setTitle(
						song.name,
						`BPM {math.floor(song.bpm + 0.5)}  -  {seconds // 60}:{string.format("%02d", seconds % 60)}`
					)
					picker.setVisible(true)
				end,
			})
		end
		songModal.setRows(rows)
		picking = true
		setPromptsEnabled(false)
		songModal.open()
	end

	-- Seed picker (Plant) -------------------------------------------------------------------
	local seedModal = ListModal.create("Plant a seed", function()
		picking = false
		setPromptsEnabled(true)
	end)

	local function openSeedPicker()
		local snapshot = GardenState.get()
		if not snapshot then
			Toast.show("Still loading...")
			return
		end
		local rows: { ListModal.Row } = {}
		for _, seed in Seeds.List do
			local count = snapshot.seeds[seed.seedId] or 0
			if count > 0 then
				table.insert(rows, {
					text = `{seed.name.en}  x{count}`,
					onTap = function()
						seedModal.close()
						local result = GardenState.call("plant", seed.seedId)
						if result.ok then
							Toast.show(`Planted {seed.name.en}! Tend it to make it grow`)
						else
							Toast.show(result.reason or "could not plant")
						end
					end,
				})
			end
		end
		if #rows == 0 then
			table.insert(rows, { text = "No seeds. Buy some at the Market!" })
		end
		seedModal.setRows(rows)
		picking = true
		setPromptsEnabled(false)
		seedModal.open()
	end

	-- Harvest -------------------------------------------------------------------------------
	local function harvest(plot: Instance)
		local result = GardenState.call("harvest")
		if not result.ok then
			Toast.show(result.reason or "could not harvest")
			return
		end
		local mutation: string? = result.mutation
		local name = if mutation
			then `{Mutations.displayName(mutation)} {seedName(result.seedId)}`
			else seedName(result.seedId)
		Toast.show(`Harvested {name}!  worth {result.value}`)
		if plot:IsA("BasePart") then
			HarvestFx.play(plot.Position, mutation)
		end
	end

	-- The prompt --------------------------------------------------------------------------
	ProximityPromptService.PromptTriggered:Connect(function(prompt: ProximityPrompt)
		if prompt.Name ~= "TendPrompt" or picking or RhythmRunner.isRunning() then
			return
		end
		local plot = prompt.Parent
		if not plot or plot:GetAttribute("OwnerUserId") ~= player.UserId then
			Toast.show("This is not your plant")
			return
		end
		local stage = plot:GetAttribute("Stage")
		if stage == "Empty" then
			openSeedPicker()
		elseif stage == "Fruit" then
			harvest(plot)
		else
			openSongPicker()
		end
	end)
end

return TendFlow
