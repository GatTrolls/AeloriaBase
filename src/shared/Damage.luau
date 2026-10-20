--!strict
--[[
	Damage

	Damage formulas. Pure functions with no Roblox APIs; the server calls them when it
	confirms a hit, and the Lune tests cover them (tests/Damage.spec.luau).

	Damage = attack × move multiplier × (1 + damage bonuses) × critical hit
	         × defence factor × resistance factor × reaction multiplier × damage-taken bonus

	Defence factor = 1 − DEF ÷ (DEF + 600 + 10 × attacker level): easy to tune, and a stronger
	attacker always gets more out of the same enemy.
]]

local Damage = {}

export type HitInput = {
	attack: number,
	multiplier: number, -- the move's share of attack: 1.2 = 120%
	flatBonus: number?,
	bonusPercent: number?, -- 0.466 = +46.6%
	critRate: number, -- 0 to 1
	critDamage: number, -- 0.5 = +50%
	attackerLevel: number,
	defense: number, -- the target's DEF
	defenseCut: number?, -- 0 to 0.9, from Brittle and similar
	resistance: number?, -- the target's resistance to this hit's element, -1 to 1+
	reactionMultiplier: number?, -- from Scald or Thaw
	damageTaken: number?, -- extra damage the target takes: 0.3 while Rattled
}

export type HitResult = {
	amount: number,
	crit: boolean,
}

-- Every enemy resists every element by this much unless its definition says otherwise.
Damage.BaseResistance = 0.1

function Damage.defenseFactor(defense: number, attackerLevel: number, cut: number?): number
	local def = math.max(0, defense) * (1 - math.clamp(cut or 0, 0, 0.9))
	return 1 - def / (def + 600 + 10 * attackerLevel)
end

-- Negative resistance helps but with diminishing returns; very high resistance never
-- reaches full immunity.
function Damage.resistanceMultiplier(resistance: number?): number
	local res = resistance or Damage.BaseResistance
	if res < 0 then
		return 1 - res / 2
	elseif res < 0.75 then
		return 1 - res
	end
	return 1 / (4 * res + 1)
end

function Damage.computeHit(input: HitInput, rng: () -> number): HitResult
	local base = input.attack * input.multiplier + (input.flatBonus or 0)
	local outgoing = base * (1 + (input.bonusPercent or 0))

	local crit = rng() < math.clamp(input.critRate, 0, 1)
	if crit then
		outgoing *= 1 + input.critDamage
	end

	local amount = outgoing
		* Damage.defenseFactor(input.defense, input.attackerLevel, input.defenseCut)
		* Damage.resistanceMultiplier(input.resistance)
		* (input.reactionMultiplier or 1)
		* (1 + (input.damageTaken or 0))

	return { amount = math.max(1, math.floor(amount + 0.5)), crit = crit }
end

-- Reaction damage (Flashpoint, Conduct, Burning, Sweep, Starburst, a Lock shatter) ignores
-- defence and crits and scales with the attacker's level, so every hero can use reactions.
function Damage.reactionDamage(
	attackerLevel: number,
	scale: number,
	resistance: number?,
	damageTaken: number?
): number
	local levelBase = 20 + attackerLevel * 12
	return math.floor(
		levelBase * scale * Damage.resistanceMultiplier(resistance) * (1 + (damageTaken or 0)) + 0.5
	)
end

-- Healing scales with the healer's attack and the target's max HP, so it stays useful as
-- everyone levels up.
function Damage.heal(attack: number, attackShare: number, maxHp: number, hpShare: number): number
	return math.floor(attack * attackShare + maxHp * hpShare + 0.5)
end

return Damage
