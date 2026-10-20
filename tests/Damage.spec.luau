--!strict
local Damage = require("../src/shared/Damage")
local TestKit = require("./TestKit")

local function hit(overrides: { [string]: any }?): Damage.HitInput
	local input: { [string]: any } = {
		attack = 1000,
		skillMultiplier = 1,
		critRate = 0,
		critDamage = 0.5,
		attackerLevel = 50,
		targetLevel = 50,
		resistance = 0,
	}
	for key, value in overrides or {} do
		input[key] = value
	end
	return input :: any
end

local never = function()
	return 0.99
end
local always = function()
	return 0
end

return {
	["equal levels halve damage through defense"] = function()
		TestKit.equal(Damage.defenseMultiplier(50, 50), 0.5)
		TestKit.equal(Damage.computeHit(hit(), never).amount, 500)
	end,

	["crits multiply by 1 + crit damage"] = function()
		local result = Damage.computeHit(hit({ critRate = 1 }), always)
		TestKit.truthy(result.crit)
		TestKit.equal(result.amount, 750)
	end,

	["amplify reactions multiply the hit"] = function()
		TestKit.equal(Damage.computeHit(hit({ hitMultiplier = 2 }), never).amount, 1000)
	end,

	["resistance has diminishing returns at both ends"] = function()
		TestKit.equal(Damage.resistanceMultiplier(-0.2), 1.1)
		TestKit.equal(Damage.resistanceMultiplier(0.5), 0.5)
		TestKit.equal(Damage.resistanceMultiplier(1), 0.2)
	end,

	["defense reduction is capped at 90%"] = function()
		TestKit.equal(Damage.defenseMultiplier(50, 50, 5), Damage.defenseMultiplier(50, 50, 0.9))
	end,

	["damage is never below 1"] = function()
		TestKit.equal(Damage.computeHit(hit({ attack = 0 }), never).amount, 1)
	end,

	["transform damage grows with attacker level"] = function()
		TestKit.truthy(Damage.transformDamage(80, 2, 0) > Damage.transformDamage(20, 2, 0))
	end,
}
