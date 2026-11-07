--!strict
-- The first-time tutorial: one lap of the loop in five steps (spec: "初回体験").
-- The step number is saved with the player data. Steps only move forward, and only when the player
-- does the thing the current step asks for. Pure logic, so it is tested in Lune.

local Tutorial = {}

Tutorial.Steps = table.freeze({
	Plant = 1,
	Tend = 2,
	Harvest = 3,
	Sell = 4,
	Buy = 5,
})
Tutorial.Done = 6

export type Event = "plant" | "tend" | "harvest" | "sell" | "buy"

local expects: { [number]: Event } = {
	[1] = "plant",
	[2] = "tend",
	[3] = "harvest",
	[4] = "sell",
	[5] = "buy",
}

function Tutorial.isActive(step: number): boolean
	return step >= 1 and step < Tutorial.Done
end

-- The step after `event`: moves on only if the event is what `step` is waiting for.
function Tutorial.advance(step: number, event: Event): number
	if expects[step] == event then
		return step + 1
	end
	return step
end

return table.freeze(Tutorial)
