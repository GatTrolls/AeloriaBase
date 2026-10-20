--!strict
--[[
	Banners

	The Starfall banners and their numbers, straight from the design plan:

	  Featured    one limited 5-star and three 4-stars on rate-up; Gold Stars; 50/50, then a guarantee;
	              Star Pick after 120 pulls without the featured 5-star.
	  Armoury     two featured 5-star weapons; Gold Stars; the player names a target weapon that
	              has its own 37.5% chance, guaranteed after a miss.
	  Everlit     the standard 5-stars and every launch 4-star; Silver Stars; always on; one free
	              Star Pick (any standard character) at 300 pulls.
	  First Light the beginner banner: the Everlit pool, 20 pulls in all, 8 Silver Stars for ten.
	              Its pulls count toward Everlit's pity, and a new player's first 5-star arrives
	              by pull 50 across the two.

	Rates are published in the Details screen from these same numbers (Gacha.publishedOdds).
	Item ids and names are generic placeholders (see Config/Items).
]]

local Gacha = require("../Gacha")
local Items = require("./Items")

local FEATURED_RATES = {
	baseRate5 = 0.008,
	baseRate4 = 0.051,
	softPity5 = 60,
	softPityStep5 = 0.065,
	hardPity5 = 75,
	hardPity4 = 10,
	featuredChance5 = 0.5,
	featured4Chance = 0.5,
}

local ARMOURY_RATES = {
	baseRate5 = 0.009,
	baseRate4 = 0.06,
	softPity5 = 51,
	softPityStep5 = 0.07,
	hardPity5 = 65,
	hardPity4 = 10,
	featuredChance5 = 0.375,
	featured4Chance = 0.75,
	targetChance5 = 0.375,
}

local function concat(...: { string }): { string }
	local out = {}
	for _, list in { ... } do
		for _, id in list do
			table.insert(out, id)
		end
	end
	return out
end

local function without(list: { string }, remove: { string }): { string }
	local out = {}
	for _, id in list do
		if not table.find(remove, id) then
			table.insert(out, id)
		end
	end
	return out
end

local function banner(rates: { [string]: any }, fields: { [string]: any }): Gacha.Banner
	local result = table.clone(rates) :: any
	for key, value in fields do
		result[key] = value
	end
	local ok, problem = Gacha.validateBanner(result)
	assert(ok, `Banner {result.id}: {problem}`)
	return table.freeze(result)
end

-- 4-star characters and weapons that every banner can hand out.
local FOUR_ALL = concat(Items.FourCharacters, Items.FourWeapons)

local function featuredBanner(id: string, name: string, limited: string, rateUp: { string }): Gacha.Banner
	return banner(FEATURED_RATES, {
		id = id,
		displayName = name,
		tabName = "Featured",
		kind = "featured",
		currency = "goldStar",
		pityGroup = "featured",
		featured5 = { limited },
		featured4 = rateUp,
		pool5 = Items.StandardFive,
		pool4 = without(FOUR_ALL, rateUp),
		pool3 = Items.ThreeWeapons,
		starPickAt = 120,
	})
end

local Banners: { [string]: Gacha.Banner } = {
	featured_1 = featuredBanner(
		"featured_1",
		"Featured Starfall",
		"char_ltd_1",
		{ "char_4_a", "char_4_b", "char_4_c" }
	),
	featured_2 = featuredBanner(
		"featured_2",
		"Featured Starfall II",
		"char_ltd_2",
		{ "char_4_d", "char_4_e", "hero_frost_debuffer" }
	),

	armoury_1 = banner(ARMOURY_RATES, {
		id = "armoury_1",
		displayName = "Armoury Starfall",
		tabName = "Armoury",
		kind = "armoury",
		currency = "goldStar",
		pityGroup = "armoury",
		featured5 = { "wpn5_ltd_1", "wpn5_ltd_2" },
		featured4 = Items.FourWeaponsRateUp,
		pool5 = Items.StandardFiveWeapons,
		pool4 = without(FOUR_ALL, Items.FourWeaponsRateUp),
		pool3 = Items.ThreeWeapons,
		targetPick = true,
	}),

	everlit = banner(FEATURED_RATES, {
		id = "everlit",
		displayName = "Everlit Starfall",
		tabName = "Everlit",
		kind = "everlit",
		currency = "silverStar",
		pityGroup = "everlit",
		featured5 = {},
		featured4 = {},
		pool5 = concat(Items.StandardFive, Items.StandardFiveWeapons),
		pool4 = FOUR_ALL,
		pool3 = Items.ThreeWeapons,
		starPickAt = 300,
		starPickOnce = true,
		starPickPool = Items.StandardFive,
		newPlayerGuarantee = { pulls = 50, pool = Items.StandardFive },
	}),

	first_light = banner(FEATURED_RATES, {
		id = "first_light",
		displayName = "First Light Starfall",
		tabName = "First Light",
		kind = "firstLight",
		currency = "silverStar",
		pityGroup = "everlit",
		featured5 = {},
		featured4 = {},
		pool5 = concat(Items.StandardFive, Items.StandardFiveWeapons),
		pool4 = FOUR_ALL,
		pool3 = Items.ThreeWeapons,
		maxPulls = 20,
		tenPullCost = 8,
		newPlayerGuarantee = { pulls = 50, pool = Items.StandardFive },
	}),
}

-- Banners shown in the Starfall screen, in tab order. Time-limited banners join and leave here.
local Active: { string } = { "featured_1", "armoury_1", "everlit", "first_light" }

return {
	byId = Banners,
	Active = table.freeze(Active),
	-- Banners that share pity share one saved state under this key.
	pityKey = function(item: Gacha.Banner): string
		return item.pityGroup or item.id
	end,
	get = function(id: string): Gacha.Banner?
		return Banners[id]
	end,
}
