--!strict
local Quests = require("../src/shared/Config/Quests")
local TestKit = require("./TestKit")

local function fresh()
	local state = Quests.newState()
	Quests.unlock(state)
	return state
end

return {
	["a new log starts the first quest and tracks it"] = function()
		local state = fresh()
		TestKit.equal(state.active.q_prologue_1 ~= nil, true)
		TestKit.equal(state.active.q_prologue_2, nil)
		TestKit.equal(state.tracked, "q_prologue_1")
	end,

	["matching events advance objectives in order"] = function()
		local state = fresh()
		-- Wrong order does nothing: the first objective is a talk.
		Quests.report(state, "reach", "spot_camp")
		TestKit.equal(state.active.q_prologue_1.step, 1)
		Quests.report(state, "talk", "npc_pocket")
		TestKit.equal(state.active.q_prologue_1.step, 2)
		local result = Quests.report(state, "reach", "spot_camp")
		TestKit.equal(#result.completed, 1)
		TestKit.equal(state.completed.q_prologue_1, true)
		TestKit.equal(state.active.q_prologue_2 ~= nil, true)
		TestKit.equal(state.tracked, "q_prologue_2")
	end,

	["counted objectives need every kill"] = function()
		local state = fresh()
		Quests.report(state, "talk", "npc_pocket")
		Quests.report(state, "reach", "spot_camp")
		for _ = 1, 4 do
			Quests.report(state, "defeat", "grunt_melee")
		end
		TestKit.equal(state.active.q_prologue_2.step, 1)
		TestKit.equal(state.active.q_prologue_2.progress, 4)
		Quests.report(state, "defeat", "grunt_melee")
		TestKit.equal(state.active.q_prologue_2.step, 2)
	end,

	["completed quests never restart and chains finish"] = function()
		local state = fresh()
		Quests.report(state, "talk", "npc_pocket")
		Quests.report(state, "reach", "spot_camp")
		Quests.report(state, "defeat", "grunt_melee", 5)
		Quests.report(state, "interact", "obj_lookout")
		Quests.report(state, "talk", "npc_pocket")
		TestKit.equal(state.completed.q_prologue_3, true)
		TestKit.equal(next(state.active), nil)
		Quests.unlock(state)
		TestKit.equal(next(state.active), nil)
	end,

	["tracking only works on an active quest"] = function()
		local state = fresh()
		TestKit.equal(Quests.track(state, "q_prologue_2"), false)
		TestKit.equal(Quests.track(state, "q_prologue_1"), true)
	end,

	["old saves are normalised"] = function()
		local state = Quests.normalize({})
		TestKit.equal(state.tracked, "")
		TestKit.equal(next(state.active), nil)
	end,
}
