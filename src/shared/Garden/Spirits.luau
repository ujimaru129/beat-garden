--!strict
-- Beat Spirits (pets): hatched from eggs, one can be equipped. An equipped spirit tends the plant on
-- its own while the player is away from it (low accuracy: small points, on a timer) and may add a
-- passive effect. Two kinds for the MVP. Values are initial, tune from playtest data.

export type Kind = "Mochi" | "Kitsune"

export type Def = {
	kind: Kind,
	name: { en: string, ja: string },
	weight: number, -- hatch odds weight (shown to the player as a percentage)
	autoCareSeconds: number, -- how often it tends the plant
	autoCarePoints: number, -- growth seconds it adds each time
	mutationMult: number, -- multiplies the mutation chance at harvest
	estimatedValue: number, -- coins, for the trade screen's "estimated value"
}

local Spirits = {}

local list: { Def } = {
	{
		kind = "Mochi",
		name = { en = "Mochi", ja = "もち" },
		weight = 70,
		autoCareSeconds = 45,
		autoCarePoints = 8,
		mutationMult = 1,
		estimatedValue = 120,
	},
	{
		kind = "Kitsune",
		name = { en = "Kitsune", ja = "きつね" },
		weight = 30,
		autoCareSeconds = 60,
		autoCarePoints = 6,
		mutationMult = 1.3,
		estimatedValue = 300,
	},
}
Spirits.List = table.freeze(list)

Spirits.EggPrice = 150 -- coins
Spirits.MaxOwned = 100

local byKind: { [string]: Def } = {}
for _, def in list do
	byKind[def.kind] = def
end

function Spirits.get(kind: string): Def?
	return byKind[kind]
end

-- `random` returns a number in [0, 1).
function Spirits.hatch(random: () -> number): Kind
	local total = 0
	for _, def in list do
		total += def.weight
	end
	local roll = random() * total
	for _, def in list do
		roll -= def.weight
		if roll < 0 then
			return def.kind
		end
	end
	return list[#list].kind
end

-- Hatch odds in percent, for the egg's description (paid random items must show their odds).
function Spirits.odds(): { { kind: Kind, percent: number } }
	local total = 0
	for _, def in list do
		total += def.weight
	end
	local out = {}
	for _, def in list do
		table.insert(out, { kind = def.kind, percent = math.round(def.weight / total * 1000) / 10 })
	end
	return out
end

return table.freeze(Spirits)
