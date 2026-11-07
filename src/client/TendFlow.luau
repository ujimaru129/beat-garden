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
local ListModal = require(script.Parent.ListModal)
local Mutations = require(ReplicatedStorage.Shared.Garden.Mutations)
local RhythmRunner = require(script.Parent.RhythmRunner)
local Seeds = require(ReplicatedStorage.Shared.Garden.Seeds)
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
		local info = tend:InvokeServer("begin", difficulty)
		if not (info and info.ok) then
			setPromptsEnabled(true)
			Toast.show(`Can't tend now: {if info then info.reason else "no answer"}`)
			return
		end
		local started = RhythmRunner.play(
			{ segment = info.segment, bpm = info.bpm, difficulty = info.difficulty },
			function(summary)
				local result = tend:InvokeServer("submit", summary)
				setPromptsEnabled(true)
				if result and result.ok then
					Toast.show(`+{result.points} growth!  {result.stage}  {math.floor(result.fraction * 100)}%`)
				else
					Toast.show(`Run not counted: {if result then result.reason else "no answer"}`)
				end
			end
		)
		if not started then
			setPromptsEnabled(true)
			Toast.show("Already playing")
		end
	end

	picker = DifficultyPicker.create(onPick, cancelPicker)
	picker.setVisible(false)

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
	local function harvest()
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
			harvest()
		else
			picking = true
			setPromptsEnabled(false)
			picker.setVisible(true)
		end
	end)
end

return TendFlow
