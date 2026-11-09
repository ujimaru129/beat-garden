--!strict
-- The global rankings: what they are called, how a value is shown, and how a stored value is made from a
-- player's data. Pure, so it is tested in Lune; the server (server/Leaderboards) does the saving and reading.

local Collection = require(script.Parent.Collection)
local Progression = require(script.Parent.Progression)

local Leaderboard = {}

export type Board = "Level" | "Book"

Leaderboard.Boards = table.freeze({ "Level", "Book" } :: { Board })
Leaderboard.TopCount = 50

local TITLES: { [string]: string } = {
	Level = "Garden level",
	Book = "Book entries",
}

function Leaderboard.title(board: string): string
	return TITLES[board] or board
end

-- The number stored for a player: total XP for the level board (so equal levels sort by progress), the number of
-- discovered book entries for the book board.
function Leaderboard.valueFor(board: string, xp: number, collection: Collection.Book): number
	if board == "Level" then
		return math.max(0, math.floor(xp))
	end
	local found = Collection.progress(collection)
	return found
end

function Leaderboard.format(board: string, value: number): string
	if board == "Level" then
		return `Lv {Progression.levelFor(value).level}`
	end
	local _, total = Collection.progress({})
	return `{value} / {total}`
end

return table.freeze(Leaderboard)
