--!strict
-- Garden plots. Everyone starts with one. Plots 2..CoinMax are bought with coins, in order, on a steep price
-- curve (more plots = more plants growing at once). The last PassBonus plots come only with the "Plot Pass"
-- game pass: they are extra on top of the coin plots, never a shortcut past them, so the pass is a bonus
-- and not pay-to-skip. Every plot looks fancier than the one before (see `tier`). Initial values.

local Plots = {}

Plots.CoinMax = 10 -- plots a player can reach with coins
Plots.PassBonus = 2 -- extra plots the game pass adds
Plots.Max = Plots.CoinMax + Plots.PassBonus
-- The Plot Pass game pass id. 0 = not set up yet (the pass plots then show "coming soon"). Create the pass in the
-- Creator Dashboard and put its id here.
Plots.PassId = 0

-- Where the plots stand: the island is a ring of up to 8 territories around the hub (spawn and shops at the
-- centre). A territory is a grid of Columns x Rows plots; row 0 (plots 1..4) is nearest the hub.
Plots.Slots = 8 -- territories = players per server the island is made for (set Max Players to this)
Plots.Columns = 4
Plots.Rows = 3
Plots.Spacing = 13 -- studs between plot centres (a plot is 10 wide)
Plots.RingRadius = 70 -- distance from the hub centre to the first row

-- Ground position (x, z) of plot `index` in territory `slot` (1..Slots), and the territory's angle (radians,
-- the way it faces away from the hub). (centerX, centerZ) is the hub centre.
function Plots.place(centerX: number, centerZ: number, slot: number, index: number): (number, number, number)
	local angle = ((slot - 1) % Plots.Slots) / Plots.Slots * math.pi * 2
	local column = (index - 1) % Plots.Columns
	local row = (index - 1) // Plots.Columns
	local radial = Plots.RingRadius + row * Plots.Spacing
	local tangent = (column - (Plots.Columns - 1) / 2) * Plots.Spacing
	local x = centerX + math.cos(angle) * radial - math.sin(angle) * tangent
	local z = centerZ + math.sin(angle) * radial + math.cos(angle) * tangent
	return x, z, angle
end

-- Price of the plot with this number (the first one is free; pass plots have no coin price).
Plots.Price = table.freeze({
	[2] = 400,
	[3] = 1000,
	[4] = 2500,
	[5] = 6000,
	[6] = 14000,
	[7] = 30000,
	[8] = 65000,
	[9] = 140000,
	[10] = 300000,
} :: { [number]: number })

-- The plot keys are "1".."Max".
function Plots.keyOf(index: number): string
	return tostring(index)
end

-- The plot number a key stands for, or nil when it is not a valid plot key.
function Plots.indexOf(key: unknown): number?
	if type(key) ~= "string" then
		return nil
	end
	local n = tonumber(key)
	if n == nil or n ~= math.floor(n) or n < 1 or n > Plots.Max or tostring(n) ~= key then
		return nil
	end
	return n
end

function Plots.isPass(index: number): boolean
	return index > Plots.CoinMax
end

-- Look tier: 1 candy frame, 2 + posts, 3 neon, 4 tall neon, 5 gold premium (the pass plots).
function Plots.tier(index: number): number
	if index <= 2 then
		return 1
	elseif index <= 5 then
		return 2
	elseif index <= 8 then
		return 3
	elseif index <= Plots.CoinMax then
		return 4
	end
	return 5
end

return table.freeze(Plots)
