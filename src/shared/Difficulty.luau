--!strict
-- Difficulty settings shared by client and server.
--
-- Judgement windows are NOT part of difficulty: Perfect / Great / Good stay the same on every
-- difficulty so the feel of a hit is consistent. Difficulty changes what is on the chart (note
-- count, set per chart in the master data) and how fast notes travel (scrollMs, below).

export type Name = "Easy" | "Normal" | "Hard"

local Difficulty = {}

local names: { Name } = { "Easy", "Normal", "Hard" }
Difficulty.Names = table.freeze(names)

-- How long a note is visible before it reaches the hit line, in ms. Larger = slower = easier.
-- Initial values; tune after playtests.
Difficulty.ScrollMs = table.freeze({
	Easy = 2000,
	Normal = 1500,
	Hard = 1100,
}) :: { [Name]: number }

-- Reward: growth points earned by a tend are multiplied by this (initial values, tune later).
-- Easy still grows the plant; Hard is for players who want to grow faster.
Difficulty.GrowthMultiplier = table.freeze({
	Easy = 1,
	Normal = 1.25,
	Hard = 1.5,
}) :: { [Name]: number }

-- Reward: multiplier on the chance of a mutation when the fruit is harvested (initial values).
-- Spec: Easy none, Normal small, Hard medium.
Difficulty.MutationChanceMultiplier = table.freeze({
	Easy = 1,
	Normal = 1.2,
	Hard = 1.4,
}) :: { [Name]: number }

return table.freeze(Difficulty)
