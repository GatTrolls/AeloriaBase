--!strict
--[[
	Damage

	Damage formulas. Pure functions with no Roblox APIs; the server calls them when it
	confirms a hit, and the Lune tests cover them (tests/Damage.spec.luau).

	Outgoing = (attack * skillMultiplier + flatBonus) * (1 + bonusPercent) * crit
	Incoming = Outgoing * defenseMultiplier * resistanceMultiplier * reactionMultiplier
]]

local Damage = {}

export type HitInput = {
	attack: number,
	skillMultiplier: number, -- 1.2 = 120% of attack
	flatBonus: number?,
	bonusPercent: number?, -- 0.466 = +46.6%
	critRate: number, -- 0 to 1
	critDamage: number, -- 0.5 = +50%
	attackerLevel: number,
	targetLevel: number,
	defenseReduction: number?, -- 0 to 1, from debuffs such as Brittle
	resistance: number?, -- -1 to 1+
	hitMultiplier: number?, -- from an amplify reaction
}

export type HitResult = {
	amount: number,
	crit: boolean,
}

-- The level constant keeps low-level fights from swinging wildly.
local LEVEL_CONSTANT = 100

function Damage.defenseMultiplier(attackerLevel: number, targetLevel: number, reduction: number?): number
	local a = attackerLevel + LEVEL_CONSTANT
	local t = (targetLevel + LEVEL_CONSTANT) * (1 - math.clamp(reduction or 0, 0, 0.9))
	return a / (a + t)
end

-- Negative resistance helps but with diminishing returns; very high resistance never
-- reaches full immunity.
function Damage.resistanceMultiplier(resistance: number?): number
	local res = resistance or 0.1
	if res < 0 then
		return 1 - res / 2
	elseif res < 0.75 then
		return 1 - res
	end
	return 1 / (4 * res + 1)
end

function Damage.computeHit(input: HitInput, rng: () -> number): HitResult
	local base = input.attack * input.skillMultiplier + (input.flatBonus or 0)
	local outgoing = base * (1 + (input.bonusPercent or 0))

	local crit = rng() < math.clamp(input.critRate, 0, 1)
	if crit then
		outgoing *= 1 + input.critDamage
	end

	local amount = outgoing
		* Damage.defenseMultiplier(input.attackerLevel, input.targetLevel, input.defenseReduction)
		* Damage.resistanceMultiplier(input.resistance)
		* (input.hitMultiplier or 1)

	return { amount = math.max(1, math.floor(amount + 0.5)), crit = crit }
end

-- Transform reactions deal their own damage that ignores defense and crit and scales with
-- the attacker's level, so every hero can use them.
function Damage.transformDamage(attackerLevel: number, scale: number, resistance: number?): number
	local levelBase = 20 + attackerLevel * 12
	return math.floor(levelBase * scale * Damage.resistanceMultiplier(resistance) + 0.5)
end

return Damage
