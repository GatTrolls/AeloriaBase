--!strict
local Ability = require("../src/shared/Combat/Ability")
local CombatConfig = require("../src/shared/Config/CombatConfig")
local Heroes = require("../src/shared/Config/Heroes")
local TestKit = require("./TestKit")

local kit = Heroes.hero_placeholder_a

return {
	["the attack chain plays in order and loops"] = function()
		local state = Ability.new()
		local now = 0
		for expected = 1, #kit.chain + 1 do
			local index = Ability.tryAttack(state, kit, now, 0)
			TestKit.equal(index, (expected - 1) % #kit.chain + 1)
			now += kit.chain[index :: number].recovery
		end
	end,

	["attacks during recovery are refused"] = function()
		local state = Ability.new()
		Ability.tryAttack(state, kit, 0, 0)
		TestKit.equal(Ability.tryAttack(state, kit, kit.chain[1].recovery * 0.5, 0), nil)
	end,

	["timing tolerance accepts slightly early requests"] = function()
		local state = Ability.new()
		Ability.tryAttack(state, kit, 0, 0)
		TestKit.equal(Ability.tryAttack(state, kit, kit.chain[1].recovery - 0.05, 0.1), 2)
	end,

	["waiting too long resets the chain"] = function()
		local state = Ability.new()
		Ability.tryAttack(state, kit, 0, 0)
		TestKit.equal(Ability.tryAttack(state, kit, CombatConfig.Combat.ComboResetSeconds + 1, 0), 1)
	end,

	["the skill respects its cooldown"] = function()
		local state = Ability.new()
		TestKit.truthy(Ability.trySkill(state, kit, 0, 0))
		TestKit.equal(Ability.trySkill(state, kit, kit.skill.cooldown - 1, 0), false)
		TestKit.truthy(Ability.trySkill(state, kit, kit.skill.cooldown, 0))
	end,

	["the burst needs full energy and empties it"] = function()
		local state = Ability.new()
		TestKit.equal(Ability.tryBurst(state, kit, 0, 0), false)
		Ability.addEnergy(state, kit, 1000)
		TestKit.equal(state.energy, kit.burst.energyCost, "energy is capped at the burst cost")
		TestKit.truthy(Ability.tryBurst(state, kit, 0, 0))
		TestKit.equal(state.energy, 0)
	end,

	["swapping out cancels recovery"] = function()
		local state = Ability.new()
		Ability.tryAttack(state, kit, 0, 0)
		Ability.cancelRecovery(state)
		TestKit.equal(Ability.tryAttack(state, kit, 0.01, 0), 1)
	end,

	["every hero kit is complete"] = function()
		local ElementConfig = require("../src/shared/Config/ElementConfig")
		local known = {}
		for _, element in ElementConfig.Elements do
			known[element] = true
		end
		for id, hero in Heroes do
			TestKit.equal(hero.id, id, "id matches key")
			TestKit.truthy(known[hero.element], `{id}: unknown element {hero.element}`)
			TestKit.equal(#hero.chain, 4, `{id}: chain length`)
			for index, hit in hero.chain do
				TestKit.truthy(hit.recovery > 0 and hit.range > 0 and hit.arc > 0, `{id} hit {index}`)
			end
			TestKit.truthy(hero.skill.cooldown > 0 and hero.burst.energyCost > 0, `{id}: skill and burst`)
		end
	end,
}
