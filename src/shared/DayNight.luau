--!strict
-- The day / night schedule, shared by every client and server from the same clock (unix seconds).
-- Spec: "1時間ごとに5分間の夜" (raised to 20 minutes after the first playtests). For the MVP night is only a look (the Night Heist game rules come in
-- v1.1), but the schedule is already the real one so it will not change later.

local DayNight = {}

DayNight.CycleSeconds = 3600 -- one day = one hour
DayNight.NightSeconds = 1200 -- the last 20 minutes of every hour
DayNight.TransitionSeconds = 5 -- length of the grading change at dusk and dawn

export type TimeOfDay = "Day" | "Night"

function DayNight.isNight(now: number): boolean
	return now % DayNight.CycleSeconds >= DayNight.CycleSeconds - DayNight.NightSeconds
end

function DayNight.timeOfDay(now: number): TimeOfDay
	return if DayNight.isNight(now) then "Night" else "Day"
end

-- Seconds until the next switch between day and night.
function DayNight.secondsUntilChange(now: number): number
	local t = now % DayNight.CycleSeconds
	local nightStart = DayNight.CycleSeconds - DayNight.NightSeconds
	if t >= nightStart then
		return DayNight.CycleSeconds - t
	end
	return nightStart - t
end

return table.freeze(DayNight)
