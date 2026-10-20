--!strict
local CombatConfig = require("../src/shared/Config/CombatConfig")
local Enemies = require("../src/shared/Config/Enemies")
local EnemyBrain = require("../src/shared/Combat/EnemyBrain")
local TestKit = require("./TestKit")

local grunt = Enemies.grunt_melee
local elite = Enemies.elite_brute
local swipe = grunt.attacks[1]

local function input(now: number, distance: number?, token: boolean?, roll: number?): EnemyBrain.Input
	return { now = now, targetDistance = distance, canTakeAttackToken = token ~= false, roll = roll }
end

return {
	["an idle enemy notices a target in range"] = function()
		local brain = EnemyBrain.new(grunt)
		TestKit.equal(EnemyBrain.step(brain, input(0, grunt.aggroRange + 1)), "none")
		TestKit.equal(EnemyBrain.step(brain, input(0, grunt.aggroRange - 1)), "aggro")
		TestKit.equal(brain.state, "chase")
	end,

	["every attack is telegraphed for its full wind-up"] = function()
		local brain = EnemyBrain.new(grunt)
		EnemyBrain.step(brain, input(0, 1))
		TestKit.equal(EnemyBrain.step(brain, input(0, 1)), "windup")
		TestKit.equal(EnemyBrain.step(brain, input(swipe.windupSeconds - 0.01, 1)), "none")
		TestKit.equal(EnemyBrain.step(brain, input(swipe.windupSeconds, 1)), "strike")
		TestKit.equal(brain.state, "recover")
	end,

	["no wind-up without an attack token"] = function()
		local brain = EnemyBrain.new(grunt)
		EnemyBrain.step(brain, input(0, 1))
		TestKit.equal(EnemyBrain.step(brain, input(0, 1, false)), "none")
		TestKit.equal(brain.state, "chase")
	end,

	["no wind-up when the target is out of reach"] = function()
		local brain = EnemyBrain.new(grunt)
		EnemyBrain.step(brain, input(0, swipe.maxRange + 1))
		TestKit.equal(EnemyBrain.step(brain, input(0, swipe.maxRange + 1)), "none")
	end,

	["it waits for its cooldown after recovering"] = function()
		local brain = EnemyBrain.new(grunt)
		EnemyBrain.step(brain, input(0, 1))
		EnemyBrain.step(brain, input(0, 1))
		EnemyBrain.step(brain, input(swipe.windupSeconds, 1))
		local recoveredAt = swipe.windupSeconds + swipe.recoverSeconds
		TestKit.equal(EnemyBrain.step(brain, input(recoveredAt, 1)), "recovered")
		TestKit.equal(EnemyBrain.step(brain, input(recoveredAt + 0.1, 1)), "none")
		TestKit.equal(EnemyBrain.step(brain, input(recoveredAt + grunt.attackCooldown, 1)), "windup")
	end,

	["grunts flinch and lose their wind-up"] = function()
		local brain = EnemyBrain.new(grunt)
		EnemyBrain.step(brain, input(0, 1))
		EnemyBrain.step(brain, input(0, 1))
		TestKit.equal(EnemyBrain.hit(brain, grunt.poise, 0.1), true)
		TestKit.equal(brain.state, "stagger")
		TestKit.equal(EnemyBrain.holdsAttackToken(brain), false)
	end,

	["elites ignore poise"] = function()
		local brain = EnemyBrain.new(elite)
		EnemyBrain.step(brain, input(0, 1))
		TestKit.equal(EnemyBrain.hit(brain, 10000, 0.1), false)
	end,

	["elites choose between their attacks"] = function()
		local seen = {}
		for _, roll in { 0, 0.5, 0.99 } do
			local brain = EnemyBrain.new(elite)
			EnemyBrain.step(brain, input(0, 1))
			EnemyBrain.step(brain, input(0, 1, true, roll))
			seen[(brain.attack :: Enemies.AttackDef).id] = true
		end
		TestKit.truthy(seen.swipe and seen.slam, "low and high rolls pick different attacks")
	end,

	["breaking composure rattles an elite, then it answers with its signature attack"] = function()
		local brain = EnemyBrain.new(elite)
		EnemyBrain.step(brain, input(0, 1))
		TestKit.equal(EnemyBrain.addComposure(brain, (elite.composure :: number) - 1, 0.1), false)
		TestKit.equal(EnemyBrain.addComposure(brain, 1, 0.2), true)
		TestKit.truthy(EnemyBrain.isRattled(brain))
		local rattledEnds = 0.2 + CombatConfig.Combat.RattledSeconds
		TestKit.equal(EnemyBrain.step(brain, input(rattledEnds, 1)), "recovered")
		EnemyBrain.step(brain, input(rattledEnds, 1, true, 0))
		TestKit.equal((brain.attack :: Enemies.AttackDef).id, elite.afterRattled)
	end,

	["grunts have no composure"] = function()
		local brain = EnemyBrain.new(grunt)
		TestKit.equal(EnemyBrain.addComposure(brain, 1000, 0), false)
	end,

	["freezing pauses the wind-up timer"] = function()
		local brain = EnemyBrain.new(grunt)
		EnemyBrain.step(brain, input(0, 1))
		EnemyBrain.step(brain, input(0, 1))
		local frozen = input(0.1, 1)
		frozen.frozen = true
		EnemyBrain.step(brain, frozen)
		TestKit.equal(EnemyBrain.step(brain, input(3.1, 1)), "none")
		TestKit.equal(EnemyBrain.step(brain, input(3 + swipe.windupSeconds, 1)), "strike")
	end,

	["it gives up when the target leaves the leash range"] = function()
		local brain = EnemyBrain.new(grunt)
		EnemyBrain.step(brain, input(0, 1))
		TestKit.equal(EnemyBrain.step(brain, input(1, grunt.leashRange + 1)), "lost")
		TestKit.equal(brain.state, "idle")
	end,
}
