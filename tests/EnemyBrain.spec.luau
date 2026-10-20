--!strict
local Enemies = require("../src/shared/Config/Enemies")
local EnemyBrain = require("../src/shared/Combat/EnemyBrain")
local TestKit = require("./TestKit")

local def = Enemies.grunt_melee

local function input(now: number, distance: number?, token: boolean?): EnemyBrain.Input
	return { now = now, targetDistance = distance, canTakeAttackToken = token ~= false }
end

return {
	["an idle enemy notices a target in range"] = function()
		local brain = EnemyBrain.new(def)
		TestKit.equal(EnemyBrain.step(brain, input(0, def.aggroRange + 1)), "none")
		TestKit.equal(EnemyBrain.step(brain, input(0, def.aggroRange - 1)), "aggro")
		TestKit.equal(brain.state, "chase")
	end,

	["every attack is telegraphed for the full wind-up"] = function()
		local brain = EnemyBrain.new(def)
		EnemyBrain.step(brain, input(0, 1))
		TestKit.equal(EnemyBrain.step(brain, input(0, 1)), "windup")
		TestKit.equal(EnemyBrain.step(brain, input(def.windupSeconds - 0.01, 1)), "none")
		TestKit.equal(EnemyBrain.step(brain, input(def.windupSeconds, 1)), "strike")
		TestKit.equal(brain.state, "recover")
	end,

	["no wind-up without an attack token"] = function()
		local brain = EnemyBrain.new(def)
		EnemyBrain.step(brain, input(0, 1))
		TestKit.equal(EnemyBrain.step(brain, input(0, 1, false)), "none")
		TestKit.equal(brain.state, "chase")
	end,

	["it waits for its cooldown after recovering"] = function()
		local brain = EnemyBrain.new(def)
		EnemyBrain.step(brain, input(0, 1))
		EnemyBrain.step(brain, input(0, 1))
		EnemyBrain.step(brain, input(def.windupSeconds, 1))
		local recoveredAt = def.windupSeconds + def.recoverSeconds
		TestKit.equal(EnemyBrain.step(brain, input(recoveredAt, 1)), "recovered")
		TestKit.equal(EnemyBrain.step(brain, input(recoveredAt + 0.1, 1)), "none")
		TestKit.equal(EnemyBrain.step(brain, input(recoveredAt + def.attackCooldown, 1)), "windup")
	end,

	["breaking poise staggers and cancels a wind-up"] = function()
		local brain = EnemyBrain.new(def)
		EnemyBrain.step(brain, input(0, 1))
		EnemyBrain.step(brain, input(0, 1))
		TestKit.equal(EnemyBrain.hit(brain, def.poise - 1, 0.1), false)
		TestKit.equal(EnemyBrain.hit(brain, 1, 0.2), true)
		TestKit.equal(brain.state, "stagger")
		TestKit.equal(EnemyBrain.holdsAttackToken(brain), false)
		TestKit.equal(EnemyBrain.step(brain, input(0.2 + def.staggerSeconds, 1)), "recovered")
	end,

	["freezing pauses the wind-up timer"] = function()
		local brain = EnemyBrain.new(def)
		EnemyBrain.step(brain, input(0, 1))
		EnemyBrain.step(brain, input(0, 1))
		local frozen = input(0.1, 1)
		frozen.frozen = true
		EnemyBrain.step(brain, frozen)
		-- Thaws three seconds later; the wind-up still has most of its time left.
		TestKit.equal(EnemyBrain.step(brain, input(3.1, 1)), "none")
		TestKit.equal(EnemyBrain.step(brain, input(3 + def.windupSeconds, 1)), "strike")
	end,

	["it gives up when the target leaves the leash range"] = function()
		local brain = EnemyBrain.new(def)
		EnemyBrain.step(brain, input(0, 1))
		TestKit.equal(EnemyBrain.step(brain, input(1, def.leashRange + 1)), "lost")
		TestKit.equal(brain.state, "idle")
	end,
}
