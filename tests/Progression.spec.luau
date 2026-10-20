--!strict
local Heroes = require("../src/shared/Config/Heroes")
local Progression = require("../src/shared/Config/Progression")
local TestKit = require("./TestKit")

local function profile(glint: number): { [string]: any }
	local p = { currencies = { glint = glint }, roster = {} }
	Progression.ensureEntry(p, "hero_main")
	return p
end

return {
	["a new entry starts at level 1 with every talent at 1"] = function()
		local p = profile(0)
		local entry = p.roster.hero_main
		TestKit.equal(entry.level, 1)
		TestKit.equal(entry.ascension, 0)
		TestKit.equal(entry.talents.technique, 1)
	end,

	["level caps rise with ascension up to 90"] = function()
		TestKit.equal(Progression.cap(0), 20)
		TestKit.equal(Progression.cap(3), 60)
		TestKit.equal(Progression.cap(6), 90)
		TestKit.equal(Progression.cap(99), 90)
	end,

	["costs grow with level"] = function()
		local last = 0
		for level = 1, 89 do
			local cost = Progression.levelCost(level)
			TestKit.equal(cost > last, true, `level {level}`)
			last = cost
		end
		TestKit.equal(Progression.talentCost(2) > Progression.talentCost(1), true)
		TestKit.equal(Progression.ascendCost(1) > Progression.ascendCost(0), true)
	end,

	["levelling charges Glint and stops at the cap"] = function()
		local p = profile(1000000)
		for _ = 1, 19 do
			local ok = Progression.levelUp(p, "hero_main")
			TestKit.equal(ok, true)
		end
		TestKit.equal(p.roster.hero_main.level, 20)
		local ok, why = Progression.levelUp(p, "hero_main")
		TestKit.equal(ok, false)
		TestKit.equal(why, "needs_ascension")
		TestKit.equal(p.currencies.glint < 1000000, true)
	end,

	["ascending needs the cap, then raises it"] = function()
		local p = profile(1000000)
		local ok, why = Progression.ascend(p, "hero_main")
		TestKit.equal(ok, false)
		TestKit.equal(why, "needs_level")
		p.roster.hero_main.level = 20
		TestKit.equal(Progression.ascend(p, "hero_main"), true)
		TestKit.equal(Progression.cap(p.roster.hero_main.ascension), 40)
		TestKit.equal(Progression.levelUp(p, "hero_main"), true)
	end,

	["without Glint nothing happens"] = function()
		local p = profile(0)
		local ok, why = Progression.levelUp(p, "hero_main")
		TestKit.equal(ok, false)
		TestKit.equal(why, "not_enough_glint")
		TestKit.equal(p.roster.hero_main.level, 1)
	end,

	["talents go to 10 and no further"] = function()
		local p = profile(1000000)
		for expected = 2, Progression.MaxTalent do
			TestKit.equal(Progression.raiseTalent(p, "hero_main", "finale"), true)
			TestKit.equal(p.roster.hero_main.talents.finale, expected)
		end
		local ok, why = Progression.raiseTalent(p, "hero_main", "finale")
		TestKit.equal(ok, false)
		TestKit.equal(why, "max_talent")
		local bad, badWhy = Progression.raiseTalent(p, "hero_main", "dance")
		TestKit.equal(bad, false)
		TestKit.equal(badWhy, "bad_talent")
	end,

	["stats match the kit at level 20 and grow from there"] = function()
		local kit = Heroes.hero_main
		local at20 = Progression.stats(
			kit,
			{ level = 20, exp = 0, ascension = 0, awakening = 0, friendship = 0, talents = {} }
		)
		TestKit.equal(at20.hp, kit.stats.maxHp)
		TestKit.equal(at20.atk, kit.stats.attack)
		local at90 = Progression.stats(
			kit,
			{ level = 90, exp = 0, ascension = 6, awakening = 0, friendship = 0, talents = {} }
		)
		TestKit.equal(at90.hp > at20.hp * 3, true)
		TestKit.equal(at90.energy > 1, true)
	end,
}
