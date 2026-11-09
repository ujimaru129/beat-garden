--!strict
-- Song genres and the "favourite song" bonus. Every song has a genre (Songs data) and every seed likes one
-- genre (Seeds.favoriteGenre). Tending a plant with a song of its favourite genre grows it faster and makes
-- a mutation more likely. Values are initial, tune from playtest data.

export type Genre = "Pop" | "Japan" | "Dance" | "Rock"

local Genres = {}

Genres.List = table.freeze({ "Pop", "Japan", "Dance", "Rock" } :: { Genre })

Genres.Names = table.freeze({
	Pop = { en = "Pop", ja = "ポップ" },
	Japan = { en = "Japan", ja = "和風" },
	Dance = { en = "Dance", ja = "ダンス" },
	Rock = { en = "Rock", ja = "ロック" },
})

-- Growth points of a tend are multiplied by this when the song is the seed's favourite.
Genres.GrowthBonus = 1.3
-- The mutation chance multiplier of the tend is multiplied by this.
Genres.MutationBonus = 1.5

function Genres.isGenre(value: any): boolean
	return table.find(Genres.List :: any, value) ~= nil
end

return table.freeze(Genres)
