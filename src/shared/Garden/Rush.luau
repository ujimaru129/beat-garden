--!strict
-- BPM Rush: a server-wide event, worked out from the shared clock like DayNight (nothing to store or sync).
-- Every hour there is a window where one music genre is "rushing": seeds that love that genre mutate more
-- easily. The genre moves on every hour. (Spec: "BPM Rush: the genre changes and its mutations get likelier".)

local Genres = require(script.Parent.Genres)

local Rush = {}

Rush.CycleSeconds = 3600
Rush.StartSeconds = 1200 -- minute 20 of the hour (the hourly night is the last 20 minutes)
Rush.DurationSeconds = 600 -- 10 minutes
Rush.MutationBoost = 1.6 -- multiplies the mutation chance of the genre's seeds
Rush.WarnSeconds = 60 -- the banner shows up this long before it starts

function Rush.genreOfHour(hour: number): string
	return Genres.List[hour % #Genres.List + 1]
end

export type State = {
	active: boolean,
	genre: string,
	secondsLeft: number, -- active: until it ends; otherwise until it starts
}

-- The event now, or the next one if it is not on (and `nil` more than WarnSeconds before it starts).
function Rush.state(now: number): State?
	local hour = now // Rush.CycleSeconds
	local t = now % Rush.CycleSeconds
	if t >= Rush.StartSeconds and t < Rush.StartSeconds + Rush.DurationSeconds then
		return {
			active = true,
			genre = Rush.genreOfHour(hour),
			secondsLeft = Rush.StartSeconds + Rush.DurationSeconds - t,
		}
	end
	if t < Rush.StartSeconds and Rush.StartSeconds - t <= Rush.WarnSeconds then
		return { active = false, genre = Rush.genreOfHour(hour), secondsLeft = Rush.StartSeconds - t }
	end
	return nil
end

-- Mutation chance multiplier for a seed that loves `favoriteGenre`.
function Rush.boost(favoriteGenre: string, now: number): number
	local state = Rush.state(now)
	if state and state.active and state.genre == favoriteGenre then
		return Rush.MutationBoost
	end
	return 1
end

return table.freeze(Rush)
