return function(loader, expect)
	local Products = loader.require("src/shared/Garden/Products")
	local PlayerData = loader.require("src/shared/Data/PlayerData")
	local Shop = loader.require("src/shared/Garden/Shop")

	return {
		{
			"products with no id set up are never matched by a receipt",
			function()
				expect(Products.kindOf(0)).toBe(nil)
				expect(Products.kindOf(-1)).toBe(nil)
				expect(Products.kindOf(123456789)).toBe(nil)
			end,
		},
		{
			"purchase state survives the data sanitiser and bad values are dropped",
			function()
				local clean = PlayerData.sanitize({
					receipts = { "a1", "b2", 7, string.rep("x", 100) },
					instantCredits = 3.7,
					sprinklerUntil = 12345,
					restockSlot = 9,
					restockShift = 2,
					plots = { ["1"] = { seedId = "seed_sakura", plantedAt = 1, careGauge = 0, sprinkled = true } },
				})
				expect(#clean.receipts).toBe(2)
				expect(clean.instantCredits).toBe(3)
				expect(clean.sprinklerUntil).toBe(12345)
				expect(clean.restockSlot).toBe(9)
				expect(clean.restockShift).toBe(2)
				expect(clean.plots["1"].sprinkled).toBe(true)
				local fresh = PlayerData.sanitize(nil)
				expect(fresh.instantCredits).toBe(0)
				expect(#fresh.receipts).toBe(0)
			end,
		},
		{
			"the receipt list is capped",
			function()
				local ids = {}
				for i = 1, Products.MaxReceipts + 50 do
					table.insert(ids, `id{i}`)
				end
				expect(#PlayerData.sanitize({ receipts = ids }).receipts).toBe(Products.MaxReceipts)
			end,
		},
		{
			"a personal restock changes the stock of that slot only",
			function()
				local same = true
				for slot = 1, 40 do
					if table.concat(Shop.stock(slot, nil, 0), ",") ~= table.concat(Shop.stock(slot, nil, 1), ",") then
						same = false
					end
				end
				expect(same).toBe(false) -- a restock really changes it (at least for some slots)
				expect(table.concat(Shop.stock(5, nil, 0), ",")).toBe(table.concat(Shop.stock(5), ","))
			end,
		},
	}
end
