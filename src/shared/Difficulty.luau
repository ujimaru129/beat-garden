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

return table.freeze(Difficulty)
