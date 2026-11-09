--!strict
-- Sleeve artwork for the song select screen: songId -> an image address made from the Creator Hub id.
-- A square image (512x512 or more) works best; songs without an entry show their initials on the genre colours.
-- The images are in assets/songart/ (one per song).

-- The ids Creator Hub shows for an uploaded Image are Decal ids. A "thumbnail" address works for those (and for plain
-- image ids) wherever an ImageLabel is used, so that is what the sleeves use.
local function image(id: string): string
	return `rbxthumb://type=Asset&id={id}&w=420&h=420`
end

return table.freeze({
	kabuki_dance = image("70952436279389"),
	dard_aur_dhamaka = image("128375813714853"),
	pastel_trip = image("128155770217807"),
	kamikaze = image("126428333735019"),
	gorilla_glue = image("110889861846415"),
	fly_me_to_the_saitama = image("121844605306176"),
	metropolitan_expressway = image("110142928408735"),
	naniwa_march = image("127616938013529"),
	blue_samurai = image("74172416191196"),
	shinjuku_deep_romance = image("122400082939476"),
} :: { [string]: string })
