--!strict
local Economy = require("../src/shared/Config/Economy")
local Rewards = require("../src/shared/Rewards")
local TestKit = require("./TestKit")

local function profile(): { [string]: any }
	return { currencies = { moonflakes = 0 }, roster = {}, weapons = {} }
end

return {
	["a new 5-star character joins the roster and pays 15 Moonflakes"] = function()
		local p = profile()
		local grant = Rewards.grantItem(p, "char_ever_1")
		TestKit.equal(grant.isNew, true)
		TestKit.equal(grant.moonflakes, 15)
		TestKit.equal(p.currencies.moonflakes, 15)
		TestKit.equal(p.roster.char_ever_1.awakening, 0)
	end,

	["a new 4-star character pays 3 Moonflakes"] = function()
		local p = profile()
		TestKit.equal(Rewards.grantItem(p, "char_4_a").moonflakes, 3)
	end,

	["duplicate characters raise Awakening up to the maximum"] = function()
		local p = profile()
		Rewards.grantItem(p, "char_ever_2")
		for expected = 1, Economy.MaxAwakening do
			local grant = Rewards.grantItem(p, "char_ever_2")
			TestKit.equal(grant.isNew, false)
			TestKit.equal(grant.awakening, expected)
			TestKit.equal(grant.maxed, false)
			TestKit.equal(grant.moonflakes, 15)
		end
		TestKit.equal(p.roster.char_ever_2.awakening, Economy.MaxAwakening)
	end,

	["past maximum Awakening a duplicate pays the larger amount"] = function()
		local p = profile()
		for _ = 1, Economy.MaxAwakening + 1 do
			Rewards.grantItem(p, "char_ever_3")
		end
		local five = Rewards.grantItem(p, "char_ever_3")
		TestKit.equal(five.maxed, true)
		TestKit.equal(five.moonflakes, 40)
		for _ = 1, Economy.MaxAwakening + 1 do
			Rewards.grantItem(p, "char_4_b")
		end
		local four = Rewards.grantItem(p, "char_4_b")
		TestKit.equal(four.maxed, true)
		TestKit.equal(four.moonflakes, 12)
		TestKit.equal(p.roster.char_4_b.awakening, Economy.MaxAwakening)
	end,

	["duplicate 4-star characters pay 6 Moonflakes while they still raise Awakening"] = function()
		local p = profile()
		Rewards.grantItem(p, "char_4_c")
		local grant = Rewards.grantItem(p, "char_4_c")
		TestKit.equal(grant.moonflakes, 6)
		TestKit.equal(grant.awakening, 1)
	end,

	["weapons start at Polish 1 and gain one per duplicate up to 5"] = function()
		local p = profile()
		local first = Rewards.grantItem(p, "wpn5_ltd_1")
		TestKit.equal(first.isNew, true)
		TestKit.equal(first.polish, 1)
		for expected = 2, Economy.MaxPolish do
			TestKit.equal(Rewards.grantItem(p, "wpn5_ltd_1").polish, expected)
		end
		local maxed = Rewards.grantItem(p, "wpn5_ltd_1")
		TestKit.equal(maxed.maxed, true)
		TestKit.equal(maxed.moonflakes, 40)
		TestKit.equal(p.weapons.wpn5_ltd_1.polish, Economy.MaxPolish)
		TestKit.equal(p.weapons.wpn5_ltd_1.count, Economy.MaxPolish + 1)
	end,

	["3-star weapons stack and always pay 1 Moonflake"] = function()
		local p = profile()
		for _ = 1, 4 do
			TestKit.equal(Rewards.grantItem(p, "wpn3_a_sword").moonflakes, 1)
		end
		TestKit.equal(p.weapons.wpn3_a_sword.count, 4)
		TestKit.equal(p.weapons.wpn3_a_sword.polish, 1)
		TestKit.equal(p.currencies.moonflakes, 4)
	end,

	["history keeps six months and no more than the cap, newest last"] = function()
		local day = 86400
		local history = {}
		for index = 1, 10 do
			table.insert(history, { at = index * day, banner = "x", itemId = "y", rarity = 3 })
		end
		-- "now" is day 200; entries older than 183 days (before day 17) are dropped: all ten here.
		Rewards.trimHistory(history, 200 * day, 183, 600)
		TestKit.equal(#history, 0)

		for index = 1, 10 do
			table.insert(history, { at = (190 + index) * day })
		end
		Rewards.trimHistory(history, 200 * day, 183, 4)
		TestKit.equal(#history, 4)
		TestKit.equal(history[1].at, 197 * day)
		TestKit.equal(history[4].at, 200 * day)

		local mixed = { { at = 1 * day }, { at = 150 * day }, { at = 199 * day } }
		Rewards.trimHistory(mixed, 200 * day, 183, 600)
		TestKit.equal(#mixed, 2)
		TestKit.equal(mixed[1].at, 150 * day)
	end,
}
