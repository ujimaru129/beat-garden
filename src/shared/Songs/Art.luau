--!strict
-- Sleeve artwork for the song select screen: songId -> "rbxassetid://<Image id>".
-- A square image (512x512 or more) works best; songs without an entry show their initials on the genre colours.
-- The images are in assets/songart/ (one per song).
--
-- Creator Hub shows the id of the uploaded "Decal"; an ImageLabel needs the id of the "Image" that belongs to it.
-- Studio's Asset Manager lists both for every upload (Type = Image is the one to use here).

local function image(id: string): string
	return `rbxassetid://{id}`
end

return table.freeze({
	kabuki_dance = image("89922850902813"),
	dard_aur_dhamaka = image("109437283664632"),
	pastel_trip = image("131267665491357"),
	kamikaze = image("116748942312280"),
	gorilla_glue = image("100187950830411"),
	fly_me_to_the_saitama = image("76282413359343"),
	metropolitan_expressway = image("110747535513328"),
	naniwa_march = image("108135762307534"),
	blue_samurai = image("83508184986174"),
	shinjuku_deep_romance = image("104178620412622"),
	yokohama_stars = image("116350374243444"),
	popping_popping = image("120861416936660"),
	good_morning_harajuku = image("120165436734457"),
	feels_so_good = image("116067297006123"),
} :: { [string]: string })
