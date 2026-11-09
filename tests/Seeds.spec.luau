return function(loader, expect)
	local Seeds = loader.require("src/shared/Garden/Seeds")
	local Genres = loader.require("src/shared/Garden/Genres")
	local Shop = loader.require("src/shared/Garden/Shop")
	local Collection = loader.require("src/shared/Garden/Collection")
	local Songs = loader.require("src/shared/Songs")
	local PlayerData = loader.require("src/shared/Data/PlayerData")

	return {
		{
			"every seed has a known favourite genre and a fruit worth more than the seed",
			function()
				for _, seed in Seeds.List do
					expect(Genres.isGenre(seed.favoriteGenre)).toBeTruthy()
					-- even the lightest fruit (weight 0.8) pays back the seed, or the loop stalls
					expect(seed.baseSellPrice * 0.8 > seed.price).toBeTruthy()
				end
			end,
		},
		{
			"every genre has a seed that likes it and a song",
			function()
				for _, genre in Genres.List do
					local seedFound, songFound = false, false
					for _, seed in Seeds.List do
						seedFound = seedFound or seed.favoriteGenre == genre
					end
					for _, song in Songs.List do
						songFound = songFound or song.genre == genre
					end
					expect(seedFound).toBeTruthy()
					expect(songFound).toBeTruthy()
				end
				for _, song in Songs.List do
					expect(Genres.isGenre(song.genre)).toBeTruthy()
				end
			end,
		},
		{
			"shop stock is deterministic, has the starter seed and distinct seeds",
			function()
				for slot = 1, 200 do
					local stock = Shop.stock(slot)
					expect(stock[1]).toBe(Seeds.StarterSeedId)
					expect(#stock).toBe(1 + Shop.RotatingSlots)
					local seen = {}
					for _, id in stock do
						expect(Seeds.get(id) ~= nil).toBeTruthy()
						expect(seen[id]).toBe(nil)
						seen[id] = true
					end
					expect(table.concat(Shop.stock(slot), ",")).toBe(table.concat(stock, ","))
				end
			end,
		},
		{
			"shop stock changes over time and rarer seeds come up less often",
			function()
				local counts = {}
				local changes = 0
				local previous = ""
				for slot = 1, 600 do
					local stock = Shop.stock(slot)
					local joined = table.concat(stock, ",")
					if joined ~= previous then
						changes += 1
					end
					previous = joined
					for _, id in stock do
						counts[id] = (counts[id] or 0) + 1
					end
				end
				expect(changes > 300).toBeTruthy()
				expect((counts.seed_yuzu or 0) > (counts.seed_hanabi or 0)).toBeTruthy()
				expect((counts.seed_hanabi or 0) > 0).toBeTruthy()
			end,
		},
		{
			"shop slots follow the clock",
			function()
				expect(Shop.slotOf(0)).toBe(0)
				expect(Shop.slotOf(299)).toBe(0)
				expect(Shop.slotOf(300)).toBe(1)
				expect(Shop.secondsLeft(0)).toBe(300)
				expect(Shop.secondsLeft(299)).toBe(1)
				expect(Shop.inStock(Seeds.StarterSeedId, 12345)).toBe(true)
			end,
		},
		{
			"collection pays once per entry and an egg for a complete seed",
			function()
				local book = {}
				local first = Collection.discover(book, "seed_sakura", nil)
				expect(first.isNew).toBe(true)
				expect(first.coins).toBe(Collection.Reward.Normal)
				expect(Collection.discover(book, "seed_sakura", nil).isNew).toBe(false)
				expect(Collection.discover(book, "seed_sakura", nil).coins).toBe(0)
				expect(Collection.discover(book, "seed_sakura", "Film").coins).toBe(Collection.Reward.Film)
				expect(Collection.discover(book, "seed_sakura", "Vapor").completedSeed).toBe(false)
				local last = Collection.discover(book, "seed_sakura", "GoldenHour")
				expect(last.completedSeed).toBe(true)
				expect(last.coins).toBe(Collection.Reward.GoldenHour)
				local found, total = Collection.progress(book)
				expect(found).toBe(#Collection.Variants)
				expect(total).toBe(#Seeds.List * #Collection.Variants)
			end,
		},
		{
			"saved collections are sanitised",
			function()
				local d = PlayerData.sanitize({
					collection = {
						["seed_sakura|Normal"] = true,
						["seed_sakura|Neon"] = true,
						["seed_nope|Normal"] = true,
						["seed_matcha|Film"] = false,
						[5] = true,
						["junk"] = true,
					},
				})
				expect(d.collection["seed_sakura|Normal"]).toBe(true)
				expect(d.collection["seed_sakura|Neon"]).toBe(nil)
				expect(d.collection["seed_nope|Normal"]).toBe(nil)
				expect(d.collection["seed_matcha|Film"]).toBe(nil)
				expect(d.collection.junk).toBe(nil)
				expect(next(PlayerData.sanitize(nil).collection)).toBe(nil)
			end,
		},
	}
end
