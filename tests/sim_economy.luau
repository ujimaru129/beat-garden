-- Economy simulation: how long does it take to reach each plot at different skill levels?
-- Run from the repo root:  lune run tests/sim_economy
-- A simplified player: plays rhythm runs back to back, tends the plant that needs it, harvests and sells at once,
-- replants with the seed that pays best per run among the ones in stock, and buys the next plot as soon as it can.
-- The numbers it prints are for tuning prices, not predictions.

local loader = require("./loader")

local Plots = loader.require("src/shared/Garden/Plots")
local Seeds = loader.require("src/shared/Garden/Seeds")
local Shop = loader.require("src/shared/Garden/Shop")
local Growth = loader.require("src/shared/Garden/Growth")
local Mutations = loader.require("src/shared/Garden/Mutations")
local Collection = loader.require("src/shared/Garden/Collection")
local Difficulty = loader.require("src/shared/Difficulty")
local Rank = loader.require("src/shared/Rank")
local Progression = loader.require("src/shared/Garden/Progression")

local RUN_SECONDS = 105 -- a 90 s song plus menus
local COOLDOWN = Growth.TendCooldownSeconds
local MAX_HOURS = 24

-- Expected sell multiplier of the mutation roll (a Perfect streak of about 15, Normal difficulty).
local function expectedMutationMultiplier(): number
	local mult = 0
	local remaining = 1
	for _, def in Mutations.Defs do
		local p = Mutations.chance(def, 15, 1)
		mult += remaining * p * def.multiplier
		remaining *= 1 - p
	end
	return mult + remaining
end
local MUTATION_MULT = expectedMutationMultiplier()

local function simulate(accuracy: number, difficulty: string, maxPoints: number, growScale: number)
	local points = math.round(
		maxPoints
			* accuracy
			* (Difficulty.GrowthMultiplier :: any)[difficulty]
			* Rank.GrowthBonus[Rank.forAccuracy(accuracy)]
	)
	local coins = 0
	local plotCount = 1
	local reachedAt: { [number]: number } = { [1] = 0 }
	-- plots: nil = empty, otherwise { seed, care, plantedAt, lastTend }
	local plots: { [number]: any } = {}
	local now = 0
	local xp = 0
	local mastery: { [string]: number } = {}
	local levelAt: { [number]: number } = { [1] = 0 } -- hour each garden level was reached

	local function addXp(amount: number)
		xp += amount
		local level = Progression.levelFor(xp).level
		for l = 2, level do
			if levelAt[l] == nil then
				levelAt[l] = now
			end
		end
	end

	local function replant(index: number)
		local stock = Shop.stock(Shop.slotOf(now), Progression.levelFor(xp).level)
		local best, bestScore = nil, -math.huge
		for _, seedId in stock do
			local seed = Seeds.get(seedId)
			if seed and seed.price <= coins then
				local grow = seed.growSeconds
					* growScale
					* Progression.growTimeMult(Progression.starsFor(mastery[seed.seedId] or 0))
				local tends = math.max(1, math.ceil(grow / points))
				local score = (seed.baseSellPrice * MUTATION_MULT - seed.price) / tends
				if score > bestScore then
					best, bestScore = seed, score
				end
			end
		end
		if not best then
			best = Seeds.get(Seeds.StarterSeedId) -- the free starter seed
		else
			coins -= best.price
		end
		local grow = best.growSeconds
			* growScale
			* Progression.growTimeMult(Progression.starsFor(mastery[best.seedId] or 0))
		plots[index] = { seed = best, care = 0, plantedAt = now, lastTend = -1e9, grow = grow }
	end

	for i = 1, plotCount do
		local starter = Seeds.get(Seeds.StarterSeedId)
		plots[i] = { seed = starter, care = 0, plantedAt = 0, lastTend = -1e9, grow = starter.growSeconds * growScale }
	end

	local runs = 0
	while now < MAX_HOURS * 3600 do
		-- harvest and sell everything that is ready
		for i = 1, plotCount do
			local plot = plots[i]
			if plot == nil then
				replant(i)
			elseif plot.care + (now - plot.plantedAt) >= plot.grow then
				coins += plot.seed.baseSellPrice * MUTATION_MULT + Collection.Reward.Normal * 0.1
				mastery[plot.seed.seedId] = (mastery[plot.seed.seedId] or 0) + 1
				addXp(Progression.harvestXp(plot.seed.seedId, nil))
				replant(i)
			end
		end
		-- buy the next plot when affordable
		local nextIndex = plotCount + 1
		if nextIndex <= Plots.CoinMax and coins >= Plots.Price[nextIndex] then
			coins -= Plots.Price[nextIndex]
			plotCount = nextIndex
			reachedAt[plotCount] = now
			replant(plotCount)
		end
		-- tend the growing plant that is closest to done and whose cooldown is over
		local pick, pickLeft = nil, math.huge
		for i = 1, plotCount do
			local plot = plots[i]
			if plot and now - plot.lastTend >= COOLDOWN then
				local left = plot.grow - plot.care - (now - plot.plantedAt)
				if left > 0 and left < pickLeft then
					pick, pickLeft = plot, left
				end
			end
		end
		if pick then
			pick.care += points
			addXp(Progression.tendXp(accuracy))
			pick.lastTend = now
			runs += 1
			now += RUN_SECONDS
		else
			now += 5 -- nothing to tend: wait for the cooldown or for a plant to ripen
		end
	end
	return reachedAt, runs, levelAt
end

local profiles = {
	{ "casual  (acc 0.80, Easy)", 0.8, "Easy" },
	{ "average (acc 0.90, Normal)", 0.9, "Normal" },
	{ "expert  (acc 0.97, Hard)", 0.97, "Hard" },
}

print(`expected mutation sell multiplier: {string.format("%.2f", MUTATION_MULT)}`)
-- Settings to compare: { full-accuracy points per run, grow time scale }. Today: { MaxTendPoints, 1 }.
for _, setting in { { Growth.MaxTendPoints, 1 }, { 60, 1 } } do
	print(`\n=== MaxTendPoints {setting[1]}, grow time x{setting[2]} ===`)
	for _, profile in profiles do
		local reached, runs, levelAt = simulate(profile[2], profile[3], setting[1], setting[2])
		local parts = {}
		for index = 2, Plots.CoinMax do
			local t = reached[index]
			table.insert(parts, `#{index}: {if t then string.format("%.1fh", t / 3600) else "-"}`)
		end
		local levels = {}
		for _, l in { 3, 5, 8, 10, 13, 15, 20 } do
			table.insert(levels, `Lv{l}: {if levelAt[l] then string.format("%.1fh", levelAt[l] / 3600) else "-"}`)
		end
		print(`{profile[1]}  runs in {MAX_HOURS}h: {runs}`)
		print("   plots  " .. table.concat(parts, "  "))
		print("   levels " .. table.concat(levels, "  "))
	end
end
