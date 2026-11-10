return function(loader, expect)
	local Park = loader.require("src/shared/Garden/Park")

	-- A small deterministic random source (Lune has no `Random`).
	local function fakeRandom(seed: number): any
		local state = seed
		return {
			NextNumber = function()
				state = (state * 1103515245 + 12345) % 2147483648
				return state / 2147483648
			end,
		}
	end

	local function stats(overrides: { [string]: number }?)
		local s = { harvests = 0, runs = 0, maxCombo = 0, book = 0, spirits = 0, level = 1 }
		for k, v in overrides or {} do
			s[k] = v
		end
		return s
	end

	return {
		{
			"goals pay one box each, once",
			function()
				local state = Park.newState()
				expect(Park.claimGoals(state, stats())).toBe(0)
				expect(Park.claimGoals(state, stats({ harvests = 5 }))).toBe(2) -- harvest_1 and harvest_5
				expect(state.boxes).toBe(2)
				expect(Park.claimGoals(state, stats({ harvests = 5 }))).toBe(0)
			end,
		},
		{
			"every goal has a unique id and a positive target",
			function()
				local seen = {}
				for _, g in Park.Goals do
					expect(seen[g.id] == nil).toBe(true)
					seen[g.id] = true
					expect(g.target > 0).toBe(true)
				end
			end,
		},
		{
			"a box gives an item the player does not own, and never the same twice",
			function()
				local state = Park.newState()
				state.boxes = Park.itemCount()
				local rng = fakeRandom(1)
				local seen = {}
				for _ = 1, Park.itemCount() do
					local key = Park.openBox(state, rng)
					expect(key ~= nil).toBe(true)
					expect(seen[key :: string] == nil).toBe(true)
					seen[key :: string] = true
					expect(Park.parseKey(key) ~= nil).toBe(true)
				end
				expect(state.boxes).toBe(0)
				state.boxes = 3
				expect(Park.openBox(state, rng) == nil).toBe(true) -- everything is owned
			end,
		},
		{
			"no box, no item",
			function()
				expect(Park.openBox(Park.newState(), fakeRandom(1)) == nil).toBe(true)
			end,
		},
		{
			"placing needs the item, an open lot and the right kind",
			function()
				local state = Park.newState()
				state.items["fountain|Sakura"] = true
				state.items["swing|Sora"] = true
				local ok = Park.place(state, "G1", "fountain|Sakura", 2)
				expect(ok).toBe(false) -- G1 opens at level 3
				ok = Park.place(state, "G1", "fountain|Sakura", 3)
				expect(ok).toBe(true)
				ok = Park.place(state, "G1", "swing|Sora", 20)
				expect(ok).toBe(false) -- a swing is a sky attraction
				ok = Park.place(state, "S1", "swing|Sora", 20)
				expect(ok).toBe(true)
				ok = Park.place(state, "S1", "swing|Matcha", 20)
				expect(ok).toBe(false) -- not owned
				ok = Park.place(state, "nope", "swing|Sora", 20)
				expect(ok).toBe(false)
			end,
		},
		{
			"moving an item empties its old lot; nil clears a lot",
			function()
				local state = Park.newState()
				state.items["fountain|Sakura"] = true
				Park.place(state, "G1", "fountain|Sakura", 20)
				Park.place(state, "G2", "fountain|Sakura", 20)
				expect(state.placed.G1 == nil).toBe(true)
				expect(state.placed.G2).toBe("fountain|Sakura")
				Park.place(state, "G2", nil, 20)
				expect(state.placed.G2 == nil).toBe(true)
			end,
		},
		{
			"sanitize drops what is not valid",
			function()
				local clean = Park.sanitize({
					boxes = 5000,
					items = { ["fountain|Sakura"] = true, ["fake|Sakura"] = true, ["fountain|Pink"] = true },
					claimed = { harvest_1 = true, nonsense = true },
					placed = { G1 = "fountain|Sakura", G2 = "fountain|Sakura", S1 = "fountain|Sakura" },
				})
				expect(clean.boxes).toBe(Park.MaxBoxes)
				expect(clean.items["fountain|Sakura"]).toBe(true)
				expect(clean.items["fake|Sakura"] == nil).toBe(true)
				expect(clean.claimed.harvest_1).toBe(true)
				expect(clean.claimed.nonsense == nil).toBe(true)
				expect(clean.placed.S1 == nil).toBe(true) -- a fountain is not a sky attraction
				local count = 0
				for _ in clean.placed do
					count += 1
				end
				expect(count).toBe(1)
				expect(#Park.Attractions > 0).toBe(true)
				local fresh = Park.sanitize(nil)
				expect(fresh.boxes).toBe(0)
			end,
		},
	}
end
