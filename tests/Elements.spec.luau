--!strict
local ElementConfig = require("../src/shared/Config/ElementConfig")
local Elements = require("../src/shared/Elements")
local TestKit = require("./TestKit")

local function reactionId(result: Elements.ApplyResult): string?
	return result.reaction and result.reaction.id
end

return {
	["a status element on a clean target leaves its status"] = function()
		local target = Elements.newTarget()
		local result = Elements.apply(target, "Tide", 0)
		TestKit.equal(result.reaction, nil)
		TestKit.equal(result.statusAfter, "Tide")
	end,

	["gale, terra and astral never stay"] = function()
		for _, element in { "Gale", "Terra", "Astral" } do
			local target = Elements.newTarget()
			TestKit.equal(Elements.apply(target, element, 0).statusAfter, nil, element)
		end
	end,

	["statuses run out after their duration"] = function()
		local target = Elements.newTarget()
		Elements.apply(target, "Tide", 0)
		TestKit.equal(Elements.statusOf(target, 9.9), "Tide")
		TestKit.equal(Elements.statusOf(target, 10.1), nil)
	end,

	["the same element refreshes the status"] = function()
		local target = Elements.newTarget()
		Elements.apply(target, "Flame", 0)
		Elements.apply(target, "Flame", 5)
		TestKit.equal(Elements.statusOf(target, 12), "Flame")
	end,

	["scald and thaw multiply the hit whichever element lands second"] = function()
		for _, order in { { "Flame", "Tide" }, { "Tide", "Flame" } } do
			local target = Elements.newTarget()
			Elements.apply(target, order[1], 0)
			local result = Elements.apply(target, order[2], 1)
			TestKit.equal(reactionId(result), "Scald")
			TestKit.equal(result.hitMultiplier, 1.5)
		end
		local frozen = Elements.newTarget()
		Elements.apply(frozen, "Frost", 0)
		TestKit.equal(Elements.apply(frozen, "Flame", 1).hitMultiplier, 1.75)
	end,

	["a reaction uses the status up"] = function()
		local target = Elements.newTarget()
		Elements.apply(target, "Volt", 0)
		local result = Elements.apply(target, "Tide", 1)
		TestKit.equal(reactionId(result), "Conduct")
		TestKit.equal(result.consumed, "Volt")
		TestKit.equal(Elements.statusOf(target, 1), nil)
	end,

	["every pair of status elements reacts"] = function()
		local statusElements = {}
		for element in ElementConfig.Statuses do
			table.insert(statusElements, element)
		end
		for _, a in statusElements do
			for _, b in statusElements do
				if a ~= b then
					TestKit.truthy(ElementConfig.reactionFor(a, b), `{a} on {b}`)
				end
			end
		end
	end,

	["lock freezes the target and a heavy hit shatters it"] = function()
		local target = Elements.newTarget()
		Elements.apply(target, "Tide", 0)
		TestKit.equal(reactionId(Elements.apply(target, "Frost", 1)), "Lock")
		TestKit.truthy(Elements.hasEffect(target, "Locked", 3.9))
		TestKit.truthy(Elements.shatter(target, 2), "shatters while locked")
		TestKit.equal(Elements.hasEffect(target, "Locked", 2.1), false, "and only once")
	end,

	["brittle lowers defence for 8 seconds"] = function()
		local target = Elements.newTarget()
		Elements.apply(target, "Frost", 0)
		Elements.apply(target, "Volt", 0)
		TestKit.truthy(Elements.hasEffect(target, "Brittle", 7.9))
		TestKit.equal(Elements.hasEffect(target, "Brittle", 8.1), false)
	end,

	["sweep cuts resistance to the swept element"] = function()
		local target = Elements.newTarget()
		Elements.apply(target, "Flame", 0)
		local result = Elements.apply(target, "Gale", 1)
		TestKit.equal(reactionId(result), "Sweep")
		TestKit.equal(result.consumed, "Flame")
		TestKit.equal(Elements.resistanceCut(target, "Flame", 2), 0.2)
		TestKit.equal(Elements.resistanceCut(target, "Tide", 2), 0)
	end,

	["starburst works once per enemy every 2 seconds"] = function()
		local target = Elements.newTarget()
		Elements.apply(target, "Tide", 0)
		TestKit.equal(reactionId(Elements.apply(target, "Astral", 1)), "Starburst")
		Elements.apply(target, "Tide", 1.5)
		TestKit.equal(Elements.apply(target, "Astral", 2).reaction, nil, "still cooling down")
		TestKit.equal(Elements.statusOf(target, 2), "Tide", "the status stays when nothing reacts")
		TestKit.equal(reactionId(Elements.apply(target, "Astral", 3.1)), "Starburst")
	end,

	["basic attacks apply their element once every 2.5 seconds per source"] = function()
		local target = Elements.newTarget()
		local basic = { basic = true, sourceKey = "p1:hero" }
		TestKit.truthy(Elements.apply(target, "Tide", 0, basic).applied)
		TestKit.equal(Elements.apply(target, "Tide", 1, basic).applied, false)
		TestKit.truthy(Elements.apply(target, "Tide", 2.6, basic).applied)
		TestKit.truthy(
			Elements.apply(target, "Tide", 2.7, { basic = true, sourceKey = "p2:hero" }).applied,
			"other sources are independent"
		)
	end,

	["techniques always apply"] = function()
		local target = Elements.newTarget()
		Elements.apply(target, "Flame", 0)
		TestKit.equal(reactionId(Elements.apply(target, "Tide", 0.1)), "Scald")
		Elements.apply(target, "Flame", 0.2)
		TestKit.equal(reactionId(Elements.apply(target, "Tide", 0.3)), "Scald")
	end,
}
