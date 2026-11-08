--!strict
-- Result rank from the server-verified accuracy (0..1), and the score shown to the player.

local Rank = {}

export type Name = "S" | "A" | "B" | "C" | "D"

local steps: { { name: Name, min: number } } = {
	{ name = "S", min = 0.95 },
	{ name = "A", min = 0.9 },
	{ name = "B", min = 0.8 },
	{ name = "C", min = 0.65 },
	{ name = "D", min = 0 },
}

-- Growth bonus for a very good run (multiplies the tend points).
Rank.GrowthBonus = table.freeze({ S = 1.2, A = 1.1, B = 1, C = 1, D = 1 }) :: { [Name]: number }

function Rank.forAccuracy(accuracy: number): Name
	for _, step in steps do
		if accuracy >= step.min then
			return step.name
		end
	end
	return "D"
end

-- 0..1,000,000. The same number the running score ends on during the run.
function Rank.score(accuracy: number): number
	return math.floor(math.clamp(accuracy, 0, 1) * 1000000 + 0.5)
end

return table.freeze(Rank)
