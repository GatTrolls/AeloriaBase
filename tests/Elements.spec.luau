--!strict
local Elements = require("../src/shared/Elements")
local TestKit = require("./TestKit")

return {
	["an element on a clean target becomes an aura"] = function()
		local target = Elements.newTarget()
		local result = Elements.apply(target, "Water", 1, 0)
		TestKit.equal(result.reaction, nil)
		TestKit.equal(result.auraAfter, "Water")
	end,

	["wind, earth and light react but never stick"] = function()
		for _, element in { "Wind", "Earth", "Light" } do
			local target = Elements.newTarget()
			TestKit.equal(Elements.apply(target, element, 2, 0).auraAfter, nil, element)
		end
	end,

	["earth on an aura gives the attacker a shield of that element"] = function()
		local target = Elements.newTarget()
		Elements.apply(target, "Ice", 2, 0)
		local result = Elements.apply(target, "Earth", 1, 0)
		TestKit.equal(result.reaction and result.reaction.id, "Shield")
		TestKit.equal(result.shieldElement, "Ice")
	end,

	["every reaction in the table names a known element pair"] = function()
		local ElementConfig = require("../src/shared/Config/ElementConfig")
		local known = {}
		for _, element in ElementConfig.Elements do
			known[element] = true
		end
		for key in ElementConfig.Reactions do
			local trigger, aura = string.match(key, "^(%a+)>(%a+)$")
			TestKit.truthy(trigger and known[trigger] and aura and known[aura], key)
			TestKit.truthy(not ElementConfig.NonAttaching[aura :: string], `{key}: aura can never exist`)
		end
	end,

	["strong amplify doubles the hit and weak amplify gives 1.5x"] = function()
		local wet = Elements.newTarget()
		Elements.apply(wet, "Fire", 2, 0)
		local strong = Elements.apply(wet, "Water", 1, 0.1)
		TestKit.equal(strong.reaction and strong.reaction.id, "Steam")
		TestKit.equal(strong.hitMultiplier, 2)

		local burning = Elements.newTarget()
		Elements.apply(burning, "Water", 2, 0)
		local weak = Elements.apply(burning, "Fire", 1, 0.1)
		TestKit.equal(weak.hitMultiplier, 1.5)
	end,

	["reactions consume the aura"] = function()
		local target = Elements.newTarget()
		Elements.apply(target, "Fire", 1, 0) -- 0.8 units of Fire
		local result = Elements.apply(target, "Water", 1, 0) -- strong Steam eats 2 units
		TestKit.equal(result.auraAfter, nil, "Fire aura should be gone")
	end,

	["sweep spreads the aura element"] = function()
		local target = Elements.newTarget()
		Elements.apply(target, "Lightning", 2, 0)
		local result = Elements.apply(target, "Wind", 1, 0)
		TestKit.equal(result.reaction and result.reaction.id, "Sweep")
		TestKit.equal(result.spreadElement, "Lightning")
	end,

	["freeze applies a timed status"] = function()
		local target = Elements.newTarget()
		Elements.apply(target, "Water", 2, 0)
		Elements.apply(target, "Ice", 1, 1)
		TestKit.truthy(Elements.hasStatus(target, "Freeze", 2))
		TestKit.truthy(not Elements.hasStatus(target, "Freeze", 3.5))
	end,

	["auras decay away over time"] = function()
		local target = Elements.newTarget()
		Elements.apply(target, "Ice", 1, 0) -- 0.8 units, lasts 6 + 3 * 0.8 = 8.4 s
		TestKit.equal(Elements.currentAura(target, 8), "Ice")
		TestKit.equal(Elements.currentAura(target, 8.5), nil)
	end,

	["internal cooldown allows hits 1, 4, 7 and resets after the window"] = function()
		local icd = Elements.newIcd()
		local allowed = {}
		for hit = 1, 7 do
			allowed[hit] = Elements.icdAllows(icd, "p1:basic", hit * 0.1)
		end
		TestKit.equal(allowed[1], true)
		TestKit.equal(allowed[2], false)
		TestKit.equal(allowed[3], false)
		TestKit.equal(allowed[4], true)
		TestKit.equal(allowed[7], true)
		TestKit.equal(Elements.icdAllows(icd, "p1:basic", 5), true, "window should reset")
		TestKit.equal(Elements.icdAllows(icd, "p2:basic", 5), true, "sources are independent")
	end,
}
