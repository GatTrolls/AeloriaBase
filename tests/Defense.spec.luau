--!strict
local CombatConfig = require("../src/shared/Config/CombatConfig")
local Defense = require("../src/shared/Combat/Defense")
local TestKit = require("./TestKit")

local Config = CombatConfig.Defense

return {
	["three dodges, then a short cooldown"] = function()
		local state = Defense.newDodge()
		local t = 0
		for _ = 1, Config.DodgeCharges do
			TestKit.truthy(Defense.tryDodge(state, t))
			t += Config.DodgeMinGapSeconds
		end
		TestKit.equal(Defense.tryDodge(state, t), false, "locked out")
		TestKit.equal(Defense.chargesLeft(state, t), 0)
		TestKit.truthy(Defense.tryDodge(state, t + Config.DodgeLockoutSeconds))
	end,

	["a quiet moment resets the dodge chain"] = function()
		local state = Defense.newDodge()
		Defense.tryDodge(state, 0)
		Defense.tryDodge(state, 0.3)
		TestKit.equal(Defense.chargesLeft(state, 0.4), Config.DodgeCharges - 2)
		TestKit.equal(
			Defense.chargesLeft(state, 0.3 + Config.DodgeChainResetSeconds + 0.1),
			Config.DodgeCharges
		)
	end,

	["dodges can't be spammed faster than the minimum gap"] = function()
		local state = Defense.newDodge()
		Defense.tryDodge(state, 0)
		TestKit.equal(Defense.tryDodge(state, 0.05), false)
	end,

	["a dodge evades while invulnerable or when it arrives before the decision"] = function()
		local strike = 10
		local resolve = Defense.resolveAt(strike)
		TestKit.truthy(Defense.evades(strike - 0.1, strike, resolve), "invulnerable when it landed")
		TestKit.equal(Defense.evades(strike - 1, strike, resolve), false, "too early")
		TestKit.truthy(Defense.evades(strike + 0.05, strike, resolve), "arrived before the decision")
		TestKit.equal(Defense.evades(resolve + 0.01, strike, resolve), false, "too late")
	end,

	["a slip is a dodge just before the hit"] = function()
		local strike = 10
		local resolve = Defense.resolveAt(strike)
		TestKit.truthy(Defense.isSlip(strike - 0.1, strike, resolve))
		TestKit.equal(Defense.isSlip(strike - 0.25, strike, resolve), false)
		TestKit.truthy(Defense.isSlip(strike - 0.25, strike, resolve, true), "assist mode is wider")
	end,

	["a lift is an attack just before a gold hit"] = function()
		local strike = 10
		local resolve = Defense.resolveAt(strike)
		TestKit.truthy(Defense.isLift(strike - 0.1, strike, resolve))
		TestKit.equal(Defense.isLift(strike - 0.3, strike, resolve), false)
		TestKit.truthy(Defense.isLift(strike + 0.05, strike, resolve), "input still in flight")
	end,
}
