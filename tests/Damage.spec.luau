--!strict
local Damage = require("../src/shared/Damage")
local TestKit = require("./TestKit")

local function hit(overrides: { [string]: any }?): Damage.HitInput
	local input: { [string]: any } = {
		attack = 1000,
		multiplier = 1,
		critRate = 0,
		critDamage = 0.5,
		attackerLevel = 40,
		defense = 1000,
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
	["defence follows 1 - DEF / (DEF + 600 + 10 x level)"] = function()
		-- 1000 / (1000 + 600 + 400) = 0.5
		TestKit.equal(Damage.defenseFactor(1000, 40), 0.5)
		TestKit.equal(Damage.computeHit(hit(), never).amount, 500)
	end,

	["higher attacker level gets more through the same defence"] = function()
		TestKit.truthy(Damage.defenseFactor(1000, 80) > Damage.defenseFactor(1000, 20))
	end,

	["crits multiply by 1 + crit damage"] = function()
		local result = Damage.computeHit(hit({ critRate = 1 }), always)
		TestKit.truthy(result.crit)
		TestKit.equal(result.amount, 750)
	end,

	["Scald and Thaw multiply the hit"] = function()
		TestKit.equal(Damage.computeHit(hit({ reactionMultiplier = 1.5 }), never).amount, 750)
	end,

	["Rattled enemies take 30% more"] = function()
		TestKit.equal(Damage.computeHit(hit({ damageTaken = 0.3 }), never).amount, 650)
	end,

	["defence cuts are capped at 90%"] = function()
		TestKit.equal(Damage.defenseFactor(1000, 40, 5), Damage.defenseFactor(1000, 40, 0.9))
	end,

	["Brittle's 25% defence cut raises damage"] = function()
		TestKit.truthy(Damage.defenseFactor(1000, 40, 0.25) > Damage.defenseFactor(1000, 40))
	end,

	["resistance has diminishing returns at both ends"] = function()
		TestKit.equal(Damage.resistanceMultiplier(-0.2), 1.1)
		TestKit.equal(Damage.resistanceMultiplier(0.5), 0.5)
		TestKit.equal(Damage.resistanceMultiplier(1), 0.2)
	end,

	["enemies resist 10% by default"] = function()
		TestKit.equal(Damage.resistanceMultiplier(nil), 0.9)
	end,

	["damage is never below 1"] = function()
		TestKit.equal(Damage.computeHit(hit({ attack = 0 }), never).amount, 1)
	end,

	["reaction damage grows with attacker level"] = function()
		TestKit.truthy(Damage.reactionDamage(80, 2, 0) > Damage.reactionDamage(20, 2, 0))
	end,

	["healing scales with attack and max HP"] = function()
		TestKit.equal(Damage.heal(200, 0.5, 1000, 0.1), 200)
	end,
}
