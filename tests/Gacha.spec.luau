--!strict
local Banners = require("../src/shared/Config/Banners")
local Gacha = require("../src/shared/Gacha")
local Items = require("../src/shared/Config/Items")
local TestKit = require("./TestKit")

local featured = Banners.byId.featured_1
local armoury = Banners.byId.armoury_1
local everlit = Banners.byId.everlit
local firstLight = Banners.byId.first_light

-- A small banner for tests that script exact rolls.
local plain: Gacha.Banner = {
	id = "test",
	displayName = "Test",
	baseRate5 = 0.008,
	baseRate4 = 0.051,
	softPity5 = 60,
	softPityStep5 = 0.065,
	hardPity5 = 75,
	hardPity4 = 10,
	featuredChance5 = 0.5,
	featured5 = { "featured_hero" },
	featured4 = { "featured_four" },
	pool5 = { "standard_hero" },
	pool4 = { "standard_four" },
	pool3 = { "three" },
}

local function sumOdds(banner: Gacha.Banner): number
	local total = 0
	for _, odds in Gacha.itemOdds(banner) do
		total += odds.chance
	end
	return total
end

local function near(actual: number, expected: number, tolerance: number, message: string)
	if math.abs(actual - expected) > tolerance then
		error(`{message}: expected about {expected}, got {actual}`, 2)
	end
end

-- Pulls until the featured 5-star arrives, using Star Pick whenever it is ready. Returns the pulls used.
local function pullsToFeatured(rng: Gacha.Rng): number
	local state = Gacha.newPityState()
	local pulls = 0
	while true do
		if Gacha.starPickReady(featured, state) then
			return pulls
		end
		local result
		result, state = Gacha.pull(featured, state, rng)
		pulls += 1
		if result.rarity == 5 and result.featured then
			return pulls
		end
	end
end

return {
	["every shipped banner passes validation"] = function()
		for id, banner in Banners.byId do
			local ok, problem = Gacha.validateBanner(banner)
			TestKit.truthy(ok, `{id}: {tostring(problem)}`)
		end
	end,

	["every banner item exists in the catalogue"] = function()
		for id, banner in Banners.byId do
			for _, list in { banner.featured5, banner.featured4, banner.pool5, banner.pool4, banner.pool3 } do
				for _, itemId in list do
					TestKit.truthy(Items.get(itemId) ~= nil, `{id} lists unknown item {itemId}`)
				end
			end
		end
	end,

	["item rarities match the pool they are in"] = function()
		for id, banner in Banners.byId do
			for _, itemId in banner.pool3 do
				TestKit.equal(Items.rarityOf(itemId), 3, `{id} {itemId}`)
			end
			for _, itemId in banner.pool4 do
				TestKit.equal(Items.rarityOf(itemId), 4, `{id} {itemId}`)
			end
			for _, itemId in banner.featured5 do
				TestKit.equal(Items.rarityOf(itemId), 5, `{id} {itemId}`)
			end
		end
	end,

	["published odds add up to exactly 100% on every banner"] = function()
		for id, banner in Banners.byId do
			near(sumOdds(banner), 1, 1e-9, id)
		end
		-- ...and for each target the Armoury player can choose.
		for _, targetId in armoury.featured5 do
			local aimed = Gacha.withTarget(armoury, targetId)
			TestKit.truthy(aimed ~= nil)
			near(sumOdds(aimed :: Gacha.Banner), 1, 1e-9, `armoury target {targetId}`)
		end
	end,

	["rate is base before soft pity and 100% at hard pity"] = function()
		TestKit.equal(Gacha.rate5ForPull(featured, 1), 0.008)
		TestKit.equal(Gacha.rate5ForPull(featured, 59), 0.008)
		near(Gacha.rate5ForPull(featured, 60), 0.073, 1e-9, "first soft pity pull")
		TestKit.equal(Gacha.rate5ForPull(featured, 75), 1)
		TestKit.equal(Gacha.rate5ForPull(armoury, 50), 0.009)
		near(Gacha.rate5ForPull(armoury, 51), 0.079, 1e-9, "armoury soft pity")
		TestKit.equal(Gacha.rate5ForPull(armoury, 65), 1)
	end,

	["published overall rates match the plan"] = function()
		near(Gacha.overallRate5(featured), 0.020, 0.0015, "featured")
		near(Gacha.overallRate5(armoury), 0.023, 0.0015, "armoury")
		near(Gacha.overallRate5(everlit), 0.020, 0.0015, "everlit")
	end,

	["hard pity gives a 5-star within the limit on each banner"] = function()
		local rng = TestKit.seededRng(1)
		for _, banner in { featured, armoury, everlit } do
			for _ = 1, 100 do
				local results = Gacha.pullMany(banner, Gacha.newPityState(), banner.hardPity5, rng)
				local got5 = false
				for _, result in results do
					if result.rarity == 5 then
						got5 = true
					end
				end
				TestKit.truthy(got5, `no 5-star in {banner.hardPity5} pulls on {banner.id}`)
			end
		end
	end,

	["4-star pity triggers within 10 pulls"] = function()
		-- 0.99 never hits a 5-star or 4-star by rate, so only pity can produce one.
		local results = Gacha.pullMany(plain, Gacha.newPityState(), 10, TestKit.scriptedRng({ 0.99 }))
		TestKit.equal(results[10].rarity, 4)
		for index = 1, 9 do
			TestKit.equal(results[index].rarity, 3)
		end
	end,

	["a 5-star also resets the 4-star counter"] = function()
		local _, state = Gacha.pull(plain, Gacha.newPityState(), TestKit.scriptedRng({ 0, 0, 0 }))
		TestKit.equal(state.sinceLast4, 0)
	end,

	["losing the 50/50 guarantees the next 5-star is featured"] = function()
		-- First pull: roll 0 hits the 5-star, 0.9 loses the 50/50.
		local first, state = Gacha.pull(plain, Gacha.newPityState(), TestKit.scriptedRng({ 0, 0.9, 0 }))
		TestKit.equal(first.rarity, 5)
		TestKit.equal(first.featured, false)
		TestKit.equal(state.guaranteedFeatured5, true)
		-- Second 5-star: even a losing roll comes out featured.
		local second, after = Gacha.pull(plain, state, TestKit.scriptedRng({ 0, 0.9, 0 }))
		TestKit.equal(second.itemId, "featured_hero")
		TestKit.equal(after.guaranteedFeatured5, false)
	end,

	["pulls never change the state they were given"] = function()
		local state = Gacha.newPityState()
		Gacha.pullMany(featured, state, 30, TestKit.seededRng(3))
		TestKit.equal(state.pullsMade, 0)
		TestKit.equal(state.sinceLast5, 0)
	end,

	["the featured 5-star never takes more than 120 pulls and averages about 74"] = function()
		local rng = TestKit.seededRng(11)
		local total, worst = 0, 0
		local runs = 4000
		for _ = 1, runs do
			local pulls = pullsToFeatured(rng)
			total += pulls
			worst = math.max(worst, pulls)
		end
		TestKit.truthy(worst <= 120, `worst case was {worst} pulls`)
		near(total / runs, 74, 4, "average pulls to the featured 5-star")
	end,

	["Star Pick unlocks at 120 pulls without the featured 5-star and resets only that counter"] = function()
		local state = Gacha.newPityState()
		state.sinceFeatured5 = 119
		TestKit.equal(Gacha.starPickReady(featured, state), false)
		TestKit.equal(Gacha.starPickIn(featured, state), 1)
		state.sinceFeatured5 = 120
		state.sinceLast5 = 17
		TestKit.equal(Gacha.starPickReady(featured, state), true)
		local result, after = Gacha.starPick(featured, state, "char_ltd_1")
		TestKit.truthy(result ~= nil and result.itemId == "char_ltd_1" and result.featured)
		TestKit.equal((after :: Gacha.PityState).sinceFeatured5, 0)
		TestKit.equal((after :: Gacha.PityState).sinceLast5, 17)
	end,

	["Star Pick only offers the featured 5-star and refuses early use"] = function()
		local state = Gacha.newPityState()
		local _, _, early = Gacha.starPick(featured, state, "char_ltd_1")
		TestKit.equal(early, "not_ready")
		state.sinceFeatured5 = 130
		local _, _, wrong = Gacha.starPick(featured, state, "char_ever_1")
		TestKit.equal(wrong, "not_a_choice")
	end,

	["Everlit Star Pick is a one-time choice of a standard character at 300 pulls"] = function()
		local state = Gacha.newPityState()
		state.pullsMade = 299
		TestKit.equal(Gacha.starPickReady(everlit, state), false)
		state.pullsMade = 300
		TestKit.equal(Gacha.starPickReady(everlit, state), true)
		-- Weapons are not on offer, only the standard characters.
		local _, _, weapon = Gacha.starPick(everlit, state, "wpn5_std_sword")
		TestKit.equal(weapon, "not_a_choice")
		local result, after = Gacha.starPick(everlit, state, "char_ever_2")
		TestKit.truthy(result ~= nil and result.itemId == "char_ever_2")
		TestKit.equal(Gacha.starPickReady(everlit, after :: Gacha.PityState), false)
		TestKit.equal(Gacha.starPickIn(everlit, after :: Gacha.PityState), nil)
	end,

	["First Light shares pity with Everlit and is capped at 20 pulls for 8 tokens a ten"] = function()
		TestKit.equal(Banners.pityKey(firstLight), Banners.pityKey(everlit))
		TestKit.equal(Gacha.cost(firstLight, 10), 8)
		TestKit.equal(Gacha.cost(firstLight, 1), 1)
		TestKit.equal(Gacha.cost(everlit, 10), 10)
		TestKit.equal(firstLight.maxPulls, 20)
	end,

	["a new player's first 5-star arrives by pull 50 and is a standard character"] = function()
		local rng = TestKit.scriptedRng({ 0.99 }) -- never a 5-star by rate
		local results, state = Gacha.pullMany(everlit, Gacha.newPityState(), 49, rng)
		for _, result in results do
			TestKit.truthy(result.rarity < 5)
		end
		TestKit.equal(Gacha.nextRate5(everlit, state), 1)
		local fifty, after = Gacha.pull(everlit, state, rng)
		TestKit.equal(fifty.rarity, 5)
		TestKit.truthy(table.find(Items.StandardFive, fifty.itemId) ~= nil, `got {fifty.itemId}`)
		-- Once they have a 5-star the guarantee is spent.
		TestKit.truthy(Gacha.nextRate5(everlit, after) < 0.1)
	end,

	["the new-player guarantee does not apply to someone who already had a 5-star"] = function()
		local state = Gacha.newPityState()
		state.pullsMade = 60
		state.sinceLast5 = 12
		TestKit.equal(Gacha.newPlayerGuarantee(everlit, state), nil)
	end,

	["Armoury target: the target and the other featured weapon each get 37.5%"] = function()
		local aimed = Gacha.withTarget(armoury, "wpn5_ltd_1") :: Gacha.Banner
		local chances: { [string]: number } = {}
		for _, odds in Gacha.itemOdds(aimed) do
			chances[odds.itemId] = odds.chance
		end
		near(chances.wpn5_ltd_1 / armoury.baseRate5, 0.375, 1e-9, "target share")
		near(chances.wpn5_ltd_2 / armoury.baseRate5, 0.375, 1e-9, "other featured share")
		local standard = 0
		for _, itemId in Items.StandardFiveWeapons do
			standard += chances[itemId]
		end
		near(standard / armoury.baseRate5, 0.25, 1e-9, "standard share")
	end,

	["Armoury target: missing it guarantees the next 5-star is the target"] = function()
		local aimed = Gacha.withTarget(armoury, "wpn5_ltd_2") :: Gacha.Banner
		-- Roll 0 hits a 5-star; 0.9 on the target roll misses it.
		local first, state = Gacha.pull(aimed, Gacha.newPityState(), TestKit.scriptedRng({ 0, 0.9, 0.5 }))
		TestKit.equal(first.rarity, 5)
		TestKit.equal(first.featured, false)
		TestKit.equal(state.guaranteedFeatured5, true)
		local second = Gacha.pull(aimed, state, TestKit.scriptedRng({ 0, 0.9, 0.5 }))
		TestKit.equal(second.itemId, "wpn5_ltd_2")
	end,

	["Armoury target must be one of the featured weapons"] = function()
		TestKit.equal(Gacha.withTarget(armoury, "wpn5_std_sword"), nil)
		TestKit.equal(Gacha.withTarget(featured, "char_ltd_1"), nil)
	end,

	["long-run 5-star rate matches the published overall rate"] = function()
		local rng = TestKit.seededRng(99)
		local state = Gacha.newPityState()
		local fives, pulls = 0, 300000
		for _ = 1, pulls do
			local result
			result, state = Gacha.pull(featured, state, rng)
			if result.rarity == 5 then
				fives += 1
			end
		end
		near(fives / pulls, Gacha.overallRate5(featured), 0.0015, "simulated 5-star rate")
	end,

	["featured 4-stars take their published share of 4-star results"] = function()
		local rng = TestKit.seededRng(5)
		local fours, ofWhichFeatured = 0, 0
		local state = Gacha.newPityState()
		for _ = 1, 200000 do
			local result
			result, state = Gacha.pull(featured, state, rng)
			if result.rarity == 4 then
				fours += 1
				if result.featured then
					ofWhichFeatured += 1
				end
			end
		end
		near(ofWhichFeatured / fours, 0.5, 0.01, "featured 4-star share")
	end,

	["state from an older save is filled in"] = function()
		local state = Gacha.normalizeState({ sinceLast5 = 12, sinceLast4 = 3, guaranteedFeatured5 = true })
		TestKit.equal(state.sinceLast5, 12)
		TestKit.equal(state.pullsMade, 0)
		TestKit.equal(state.starPickUsed, false)
		TestKit.equal(Gacha.normalizeState(nil).sinceLast5, 0)
	end,
}
