--!strict
local Gacha = require("../src/shared/Gacha")
local TestKit = require("./TestKit")

local banner: Gacha.Banner = {
	id = "test",
	displayName = "Test",
	baseRate5 = 0.006,
	baseRate4 = 0.051,
	softPity5 = 74,
	softPityStep5 = 0.06,
	hardPity5 = 90,
	hardPity4 = 10,
	featuredChance5 = 0.5,
	featured5 = { "featured_hero" },
	featured4 = { "featured_four" },
	pool5 = { "standard_hero" },
	pool4 = { "standard_four" },
	pool3 = { "three" },
}

return {
	["banner passes validation"] = function()
		TestKit.truthy(Gacha.validateBanner(banner))
	end,

	["rate is base before soft pity and 100% at hard pity"] = function()
		TestKit.equal(Gacha.rate5ForPull(banner, 1), 0.006)
		TestKit.equal(Gacha.rate5ForPull(banner, 73), 0.006)
		TestKit.truthy(Gacha.rate5ForPull(banner, 74) > 0.06)
		TestKit.equal(Gacha.rate5ForPull(banner, 90), 1)
	end,

	["hard pity always gives a 5-star by pull 90"] = function()
		local rng = TestKit.seededRng(1)
		for _ = 1, 200 do
			local results = Gacha.pullMany(banner, Gacha.newPityState(), 90, rng)
			local got5 = false
			for _, result in results do
				if result.rarity == 5 then
					got5 = true
				end
			end
			TestKit.truthy(got5, "no 5-star in 90 pulls")
		end
	end,

	["4-star pity triggers within 10 pulls"] = function()
		-- 0.99 never hits a 5-star or 4-star by rate, so only pity can produce one.
		local results = Gacha.pullMany(banner, Gacha.newPityState(), 10, TestKit.scriptedRng({ 0.99 }))
		TestKit.equal(results[10].rarity, 4)
		for index = 1, 9 do
			TestKit.equal(results[index].rarity, 3)
		end
	end,

	["losing the 50/50 guarantees the next 5-star is featured"] = function()
		-- First pull: roll 0 hits the 5-star, 0.9 loses the 50/50.
		local first, state = Gacha.pull(banner, Gacha.newPityState(), TestKit.scriptedRng({ 0, 0.9, 0 }))
		TestKit.equal(first.rarity, 5)
		TestKit.equal(first.featured, false)
		TestKit.equal(state.guaranteedFeatured5, true)
		TestKit.equal(state.sinceLast5, 0)

		-- Next 5-star: even a losing 50/50 roll gives the featured item.
		local second, after = Gacha.pull(banner, state, TestKit.scriptedRng({ 0, 0.9, 0 }))
		TestKit.equal(second.itemId, "featured_hero")
		TestKit.equal(after.guaranteedFeatured5, false)
	end,

	["input pity state is never mutated"] = function()
		local state = Gacha.newPityState()
		Gacha.pullMany(banner, state, 10, TestKit.seededRng(7))
		TestKit.equal(state.sinceLast5, 0)
		TestKit.equal(state.sinceLast4, 0)
	end,

	["long-run 5-star rate lands near the expected ~1.6%"] = function()
		local rng = TestKit.seededRng(42)
		local state = Gacha.newPityState()
		local total, fives = 100000, 0
		for _ = 1, total do
			local result
			result, state = Gacha.pull(banner, state, rng)
			if result.rarity == 5 then
				fives += 1
			end
		end
		local rate = fives / total
		TestKit.truthy(rate > 0.014 and rate < 0.018, `5-star rate {rate} outside expected range`)
	end,
}
