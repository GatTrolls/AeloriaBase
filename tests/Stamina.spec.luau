--!strict
local CombatConfig = require("../src/shared/Config/CombatConfig")
local Stamina = require("../src/shared/Combat/Stamina")
local TestKit = require("./TestKit")

local Config = CombatConfig.Stamina

return {
	["a new bar starts full"] = function()
		TestKit.equal(Stamina.new(0).value, Config.Max)
	end,

	["sprinting drains over time"] = function()
		local state = Stamina.new(0)
		Stamina.setActivity(state, "sprint", 0)
		Stamina.update(state, 2)
		TestKit.equal(state.value, Config.Max - Config.SprintPerSecond * 2)
	end,

	["running out ends the activity and reports it"] = function()
		local state = Stamina.new(0)
		Stamina.setActivity(state, "climb", 0)
		local exhausted = Stamina.update(state, Config.Max / Config.ClimbPerSecond + 1)
		TestKit.truthy(exhausted, "should report exhaustion")
		TestKit.equal(state.value, 0)
		TestKit.equal(state.activity, "none")
		TestKit.equal(
			Stamina.setActivity(state, "glide", state.updatedAt),
			false,
			"cannot start with an empty bar"
		)
	end,

	["a climb leap fails without enough grip and spends nothing"] = function()
		local state = Stamina.new(0)
		state.value = Config.ClimbLeapCost - 1
		TestKit.equal(Stamina.spend(state, Config.ClimbLeapCost, 0), false)
		TestKit.equal(state.value, Config.ClimbLeapCost - 1)
	end,

	["regeneration waits for the delay after a spend"] = function()
		local state = Stamina.new(0)
		Stamina.spend(state, 100, 0)
		Stamina.update(state, Config.RegenDelaySeconds * 0.5)
		TestKit.equal(state.value, Config.Max - 100, "no regen inside the delay")
		Stamina.update(state, Config.RegenDelaySeconds + 1)
		TestKit.equal(state.value, Config.Max - 100 + Config.RegenPerSecond, "one second of regen")
	end,

	["regeneration never passes the maximum"] = function()
		local state = Stamina.new(0)
		Stamina.spend(state, 10, 0)
		Stamina.update(state, 1000)
		TestKit.equal(state.value, Config.Max)
	end,

	["a client that never stops sprinting still runs dry"] = function()
		local state = Stamina.new(0)
		Stamina.setActivity(state, "sprint", 0)
		local highest = 0
		for tick = 1, 600 do
			-- A cheating client asks to sprint again every tenth of a second.
			local now = 20 + tick / 10
			Stamina.setActivity(state, "sprint", now)
			highest = math.max(highest, state.value)
		end
		-- After the first run-out it can only ever sprint on the little it regains.
		TestKit.truthy(highest < Config.RegenPerSecond, `stamina climbed back to {highest}`)
	end,
}
