--!strict
-- What can be bought with Robux (spec: 収益化). Ids are made in Creator Hub; 0 = not set up yet (the screens then
-- say "coming soon" instead of opening a purchase). Prices here are only for showing; Roblox charges the real price.
-- Nothing here is needed to enjoy the game: it saves time or adds a little luck, and never beats other players.

local Products = {}

-- Game pass: plants grow twice as fast, for good.
Products.DoubleGrowthPassId = 0
Products.GrowSpeedMult = 2

-- Developer products (each purchase is used once)
Products.InstantGrowId = 0 -- the plant you tended last ripens at once
Products.RestockId = 0 -- a fresh shop stock for you alone, until the normal stock changes
Products.SprinklerId = 0 -- plants now growing, and ones planted within SprinklerSeconds, mutate more

Products.SprinklerSeconds = 600
Products.SprinklerBoost = 1.5 -- multiplies the mutation chance when the fruit ripens

Products.Prices = table.freeze({
	DoubleGrowth = 199,
	InstantGrow = 25,
	Restock = 39,
	Sprinkler = 49,
})

export type Kind = "InstantGrow" | "Restock" | "Sprinkler"

-- Which developer product a receipt is for.
function Products.kindOf(productId: number): Kind?
	if productId <= 0 then
		return nil
	end
	if productId == Products.InstantGrowId then
		return "InstantGrow"
	elseif productId == Products.RestockId then
		return "Restock"
	elseif productId == Products.SprinklerId then
		return "Sprinkler"
	end
	return nil
end

-- How many recent purchase ids are kept to stop a purchase from being granted twice.
Products.MaxReceipts = 100

return table.freeze(Products)
