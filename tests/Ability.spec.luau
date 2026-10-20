--!strict
local Ability = require("../src/shared/Combat/Ability")
local CombatConfig = require("../src/shared/Config/CombatConfig")
local ElementConfig = require("../src/shared/Config/ElementConfig")
local Heroes = require("../src/shared/Config/Heroes")
local TestKit = require("./TestKit")

local kit = Heroes.hero_main

local STEP_KINDS = {
	hit = true,
	line = true,
	dash = true,
	pull = true,
	rain = true,
	zone = true,
	heal = true,
	shield = true,
	effect = true,
	infuse = true,
}

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

	["a charged attack resets the chain"] = function()
		local state = Ability.new()
		Ability.tryAttack(state, kit, 0, 0)
		TestKit.truthy(Ability.tryCharged(state, kit, 1, 0))
		TestKit.equal(Ability.tryAttack(state, kit, 1 + kit.charged.recovery, 0), 1)
	end,

	["the technique respects its cooldown"] = function()
		local state = Ability.new()
		TestKit.truthy(Ability.tryTechnique(state, kit, 0, 0))
		TestKit.equal(Ability.tryTechnique(state, kit, kit.technique.cooldown - 1, 0), false)
		TestKit.truthy(Ability.tryTechnique(state, kit, kit.technique.cooldown, 0))
	end,

	["the finale needs full energy and empties it"] = function()
		local state = Ability.new()
		TestKit.equal(Ability.tryFinale(state, kit, 0, 0), false)
		Ability.addEnergy(state, kit, 1000)
		TestKit.equal(state.energy, kit.finale.energyCost, "energy is capped at the finale cost")
		TestKit.truthy(Ability.tryFinale(state, kit, 0, 0))
		TestKit.equal(state.energy, 0)
	end,

	["swapping out cancels recovery"] = function()
		local state = Ability.new()
		Ability.tryAttack(state, kit, 0, 0)
		Ability.cancelRecovery(state)
		TestKit.equal(Ability.tryAttack(state, kit, 0.01, 0), 1)
	end,

	["an infusion lasts for its number of hits"] = function()
		local state = Ability.new()
		Ability.infuse(state, "Flame", 2)
		TestKit.equal(Ability.takeInfusion(state), "Flame")
		TestKit.equal(Ability.takeInfusion(state), "Flame")
		TestKit.equal(Ability.takeInfusion(state), nil)
	end,

	["every hero kit follows the character framework"] = function()
		local known = {}
		for _, element in ElementConfig.Elements do
			known[element] = true
		end
		for id, hero in Heroes do
			TestKit.equal(hero.id, id, "id matches key")
			TestKit.truthy(known[hero.element], `{id}: unknown element {hero.element}`)
			TestKit.truthy(#hero.chain == 4 or #hero.chain == 5, `{id}: chain has 4 or 5 hits`)
			local comboSeconds = 0
			for index, hit in hero.chain do
				TestKit.truthy(hit.recovery > 0 and hit.range > 0 and hit.arc > 0, `{id} hit {index}`)
				comboSeconds += hit.recovery
			end
			TestKit.truthy(comboSeconds >= 2.5 and comboSeconds <= 3.5, `{id}: combo takes {comboSeconds} s`)
			TestKit.truthy(
				hero.technique.cooldown >= 6 and hero.technique.cooldown <= 15,
				`{id}: technique cooldown`
			)
			TestKit.truthy(
				hero.finale.energyCost >= 60 and hero.finale.energyCost <= 90,
				`{id}: finale energy cost`
			)
			for _, part in { hero.technique.steps, hero.finale.steps, hero.relay.steps } do
				TestKit.truthy(#part > 0, `{id}: every ability has steps`)
				for _, step in part do
					TestKit.truthy(STEP_KINDS[step.kind], `{id}: unknown step kind {step.kind}`)
				end
			end
		end
	end,
}
