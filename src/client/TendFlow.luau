--!strict
-- Client side of the plant prompt. What the prompt does depends on the plant's stage:
--   Empty -> pick a seed to plant      Fruit -> harvest      anything else -> Tend (rhythm run)
-- Tend: pick a difficulty -> play the chart -> see the result. The server hands out the chart and
-- decides every number; this module only shows and plays.

local ContentProvider = game:GetService("ContentProvider")
local Players = game:GetService("Players")
local MarketplaceService = game:GetService("MarketplaceService")
local ProximityPromptService = game:GetService("ProximityPromptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local DifficultyPicker = require(script.Parent.DifficultyPicker)
local GardenState = require(script.Parent.GardenState)
local HarvestFx = require(script.Parent.HarvestFx)
local BoardCells = require(script.Parent.BoardCells)
local ListModal = require(script.Parent.ListModal)
local SongSelect = require(script.Parent.SongSelect)
local Mutations = require(ReplicatedStorage.Shared.Garden.Mutations)
local ResultScreen = require(script.Parent.ResultScreen)
local RhythmRunner = require(script.Parent.RhythmRunner)
local Palette = require(ReplicatedStorage.Shared.Palette)
local Plots = require(ReplicatedStorage.Shared.Garden.Plots)
local Seeds = require(ReplicatedStorage.Shared.Garden.Seeds)
local Genres = require(ReplicatedStorage.Shared.Garden.Genres)
local Songs = require(ReplicatedStorage.Shared.Songs)
local Spirits = require(ReplicatedStorage.Shared.Garden.Spirits)
local Lang = require(script.Parent.Lang)
local SongArt = require(ReplicatedStorage.Shared.Songs.Art)
local Toast = require(script.Parent.Toast)
local TipsUI = require(script.Parent.TipsUI)

local TendFlow = {}

local function seedName(seedId: string): string
	local seed = Seeds.get(seedId)
	return if seed then (if Lang.code == "ja" then seed.name.ja else seed.name.en) else seedId
end

-- Level-ups and newly opened seeds, after a tend or a harvest.
local function announceLevelUp(result: any)
	if not result.leveledUp then
		return
	end
	TipsUI.show("levelup")
	local names: { string } = {}
	for _, seedId in result.unlocked or {} do
		table.insert(names, seedName(seedId))
	end
	if #names > 0 then
		Toast.show(`Garden Lv {result.level}!  New seed in the shop: {table.concat(names, ", ")}`)
	else
		Toast.show(`Garden Lv {result.level}!`)
	end
end

-- The equipped spirit grew with this tend: a level, and at some levels a random trait (a look or a ride).
local function announceSpiritGrowth(result: any)
	local growth = result.spiritGrowth
	if not growth then
		return
	end
	local def = Spirits.get(growth.kind)
	if not def then
		return
	end
	local ja = Lang.code == "ja"
	local name = if ja then def.name.ja else def.name.en
	if growth.leveledUp then
		Toast.show(`{name} grew to Lv {growth.level}!`)
	end
	for _, id in growth.traits or {} do
		local trait = Spirits.trait(id)
		if trait then
			Toast.show(`{name} learned a new look: {if ja then trait.name.ja else trait.name.en}!`)
		end
	end
end

function TendFlow.start()
	-- Load the song sleeves in the background now, so they are already there when the song select opens.
	task.spawn(function()
		local urls: { string } = {}
		for _, url in SongArt do
			table.insert(urls, url)
		end
		pcall(function()
			ContentProvider:PreloadAsync(urls)
		end)
	end)

	local remote = ReplicatedStorage:WaitForChild("Tend", 10) :: RemoteFunction?
	if not remote then
		warn("[TendFlow] Tend remote not found")
		return
	end
	local tend: RemoteFunction = remote
	local player = Players.LocalPlayer :: Player
	local picking = false
	local chosenSongId = ""
	local currentPlotKey = "1" -- the plot whose prompt was used last

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
		local info =
			tend:InvokeServer("begin", { difficulty = difficulty, songId = chosenSongId, plotKey = currentPlotKey })
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
			audioEndMs = info.audioEndMs,
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
					favorite = result.favorite,
					xpGained = result.xpGained,
					level = result.level,
					leveledUp = result.leveledUp,
				}, function()
					setPromptsEnabled(true)
					announceLevelUp(result)
					announceSpiritGrowth(result)
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
	local songSelect: SongSelect.Select
	songSelect = SongSelect.create(function(item)
		advancing = true
		songSelect.close()
		advancing = false
		chosenSongId = item.songId
		picker.setTitle(item.name, `{item.genre}  |  {math.floor(item.bpm + 0.5)} BPM`)
		picker.setVisible(true)
	end, function()
		if advancing then
			return
		end
		picking = false
		setPromptsEnabled(true)
	end)
	-- The preview starts at the busiest segment (most Hard notes): usually the chorus.
	local function previewStartOf(song: Songs.SongData): number
		local bestStart, bestCount = 0, -1
		for _, seg in song.segments do
			local count = #((seg :: any).Hard or {})
			if count > bestCount then
				bestStart, bestCount = seg.startMs, count
			end
		end
		return bestStart
	end

	local function openSongPicker()
		-- The planted seed's favourite genre: songs of that genre are marked and listed first.
		local snapshot = GardenState.get()
		local planted = if snapshot then snapshot.plots[currentPlotKey] else nil
		local seed = if planted then Seeds.get(planted.seedId) else nil
		local favorite = if seed then seed.favoriteGenre else nil
		local songs: { Songs.SongData } = table.clone(Songs.List) :: any
		table.sort(songs, function(a, b)
			local fa, fb = a.genre == favorite, b.genre == favorite
			if fa ~= fb then
				return fa
			end
			return a.name < b.name
		end)
		local items: { SongSelect.Item } = {}
		for _, song in songs do
			-- A song whose audio is not uploaded yet would play silent: it is listed only while testing in Studio.
			if not song.audioAssetId and not RunService:IsStudio() then
				continue
			end
			table.insert(items, {
				songId = song.songId,
				name = song.name,
				genre = (Genres.Names :: any)[song.genre].en,
				bpm = song.bpm,
				favorite = song.genre == favorite,
				isNew = Songs.NewIds[song.songId] == true,
				artAssetId = SongArt[song.songId],
				audioAssetId = song.audioAssetId,
				previewStartMs = previewStartOf(song),
			})
		end
		picking = true
		setPromptsEnabled(false)
		songSelect.open(items)
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
		-- A table: seed | how many you have | Plant.
		BoardCells.refresh()
		local columns: { BoardCells.Column } = {
			{ title = "", width = 50 },
			{ title = "SEED", flex = 1 },
			{ title = "HAVE", width = 72, align = "center" },
			{ title = "", width = 96, align = "center" },
		}
		local rows: { ListModal.Row } = {}
		for _, seed in Seeds.List do
			local count = snapshot.seeds[seed.seedId] or 0
			if count > 0 then
				if #rows == 0 then
					table.insert(rows, {
						text = "",
						head = true,
						columns = columns,
						cells = { { text = "" }, { text = "SEED" }, { text = "HAVE" }, { text = "" } },
					})
				end
				table.insert(rows, {
					text = seedName(seed.seedId),
					columns = columns,
					cells = {
						{ icon = { kind = "plant", id = seed.seedId } },
						{ text = seedName(seed.seedId), bold = true },
						{ text = `x{count}`, bold = true },
						{ text = Lang.t("Plant"), pill = BoardCells.pill("Matcha") },
					},
					onTap = function()
						seedModal.close()
						local result = GardenState.call("plant", { seedId = seed.seedId, plotKey = currentPlotKey })
						if result.ok then
							Toast.show(`Planted {seedName(seed.seedId)}! Tend it to make it grow`)
						else
							Toast.show(result.reason or "could not plant")
						end
					end,
				})
			end
		end
		if #rows == 0 then
			table.insert(rows, { text = "No seeds. Buy some from the Shop button!" })
		end
		seedModal.setRows(rows)
		picking = true
		setPromptsEnabled(false)
		seedModal.open()
	end

	-- Unlock (a plot that is not bought yet) ------------------------------------------------
	local unlockModal = ListModal.create("Unlock a plot", function()
		picking = false
		setPromptsEnabled(true)
	end)

	local function openUnlock(plotKey: string, price: number)
		unlockModal.setRows({
			{ text = `Plot {plotKey}: one more plant growing at a time`, note = true },
			{
				text = `Unlock for {price} coins`,
				color = Palette.Hues.Matcha.Night,
				onTap = function()
					unlockModal.close()
					local result = GardenState.call("unlockPlot", plotKey)
					if result.ok then
						Toast.show(`Plot {plotKey} unlocked!`)
					else
						Toast.show(result.reason or "could not unlock")
					end
				end,
			},
			{
				text = "Not now",
				color = Palette.Rarity.Common,
				onTap = function()
					unlockModal.close()
				end,
			},
		})
		picking = true
		setPromptsEnabled(false)
		unlockModal.open()
	end

	-- The Plot Pass: premium plots that only the game pass opens.
	local passModal = ListModal.create("Plot Pass", function()
		picking = false
		setPromptsEnabled(true)
	end)

	local function openPass()
		passModal.setRows({
			{
				text = `The Plot Pass opens {Plots.PassBonus} extra gold plots, on top of the others`,
				note = true,
			},
			{
				text = "Get the Plot Pass",
				color = Palette.Hues.Yuzu.Night,
				onTap = function()
					passModal.close()
					if Plots.PassId > 0 then
						MarketplaceService:PromptGamePassPurchase(player, Plots.PassId)
					else
						Toast.show("The Plot Pass is coming soon!")
					end
				end,
			},
			{
				text = "Not now",
				color = Palette.Rarity.Common,
				onTap = function()
					passModal.close()
				end,
			},
		})
		picking = true
		setPromptsEnabled(false)
		passModal.open()
	end

	-- Harvest -------------------------------------------------------------------------------
	local function harvest(plot: Instance)
		local result = GardenState.call("harvest", currentPlotKey)
		if not result.ok then
			Toast.show(result.reason or "could not harvest")
			return
		end
		local mutation: string? = result.mutation
		local name = if mutation
			then `{Mutations.displayName(mutation)} {seedName(result.seedId)}`
			else seedName(result.seedId)
		local overripe = (result.freshness or 1) < 0.999
		local discovery = result.discovery
		if discovery and discovery.isNew then
			local extra = `  NEW in the book! +{discovery.coins} coins`
			if (result.completionEggs or 0) > 0 then
				extra ..= `  Complete! +{result.completionEggs} Spirit Egg`
			end
			Toast.show(
				`Harvested {name}!  worth {result.value}{extra}{if overripe then "  (overripe: harvest sooner!)" else ""}`
			)
		else
			Toast.show(
				`Harvested {name}!  worth {result.value}{if overripe then "  (overripe: harvest sooner!)" else ""}`
			)
		end
		if overripe then
			TipsUI.show("overripe")
		end
		if result.newStar then
			TipsUI.show("star")
			Toast.show(
				`{seedName(result.seedId)} mastery {string.rep("\u{2605}", result.stars)}: grows faster, mutates more!`
			)
		end
		announceLevelUp(result)
		if plot:IsA("BasePart") then
			HarvestFx.play(plot.Position, mutation)
		end
	end

	-- Studio only: C gives 500 coins.
	if RunService:IsStudio() then
		UserInputService.InputBegan:Connect(function(input, gameProcessed)
			if gameProcessed or input.KeyCode ~= Enum.KeyCode.C then
				return
			end
			local result = GardenState.call("devGrant", 500)
			Toast.show(if result.ok then "+500 coins (Studio)" else result.reason or "not available")
		end)
	end

	-- Studio only: G grows every plant to its next stage; L jumps to the next garden level.
	if RunService:IsStudio() then
		UserInputService.InputBegan:Connect(function(input, gameProcessed)
			if gameProcessed or input.KeyCode ~= Enum.KeyCode.G then
				return
			end
			local result = GardenState.call("devGrow")
			Toast.show(if result.ok then "Plants grew one stage (Studio)" else result.reason or "not available")
		end)
		UserInputService.InputBegan:Connect(function(input, gameProcessed)
			if gameProcessed or input.KeyCode ~= Enum.KeyCode.L then
				return
			end
			local result = GardenState.call("devLevelUp")
			if result.ok then
				announceLevelUp({ leveledUp = true, level = result.level, unlocked = result.unlocked })
			else
				Toast.show(result.reason or "not available")
			end
		end)
	end

	-- Studio only: M raises the equipped spirit one level (a trait is rolled at Lv3 / 6 / 10).
	if RunService:IsStudio() then
		UserInputService.InputBegan:Connect(function(input, gameProcessed)
			if gameProcessed or input.KeyCode ~= Enum.KeyCode.M then
				return
			end
			local result = GardenState.call("devSpiritLevelUp")
			if result.ok then
				announceSpiritGrowth({ spiritGrowth = result })
			else
				Toast.show(result.reason or "not available")
			end
		end)
	end

	-- Studio only: B gives 3 Gift Boxes for the park.
	if RunService:IsStudio() then
		UserInputService.InputBegan:Connect(function(input, gameProcessed)
			if gameProcessed or input.KeyCode ~= Enum.KeyCode.B then
				return
			end
			local result = GardenState.call("devBoxes")
			Toast.show(if result.ok then "+3 Gift Boxes (Studio)" else result.reason or "not available")
		end)
	end

	-- Studio only: P switches the Plot Pass on and off, to try the premium plots and the locked look.
	if RunService:IsStudio() then
		UserInputService.InputBegan:Connect(function(input, gameProcessed)
			if gameProcessed or input.KeyCode ~= Enum.KeyCode.P then
				return
			end
			local result = GardenState.call("devPlotPass")
			Toast.show(
				if result.ok then `Plot Pass {if result.hasPass then "ON" else "OFF"} (Studio)` else "not available"
			)
		end)
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
		currentPlotKey = tostring(plot:GetAttribute("PlotKey") or "1")
		player:SetAttribute("LastPlotKey", currentPlotKey) -- the Instant Grow in the shop uses this plant
		local stage = plot:GetAttribute("Stage")
		if stage == "Locked" and plot:GetAttribute("Pass") == true then
			openPass()
		elseif stage == "Locked" and tonumber(plot:GetAttribute("NextUnlock")) ~= tonumber(currentPlotKey) then
			Toast.show(`Buy plot {tostring(plot:GetAttribute("NextUnlock") or "?")} first`)
		elseif stage == "Locked" then
			openUnlock(currentPlotKey, tonumber(plot:GetAttribute("Price")) or 0)
		elseif stage == "Empty" then
			openSeedPicker()
		elseif stage == "Fruit" then
			harvest(plot)
		else
			openSongPicker()
		end
	end)
end

return TendFlow
