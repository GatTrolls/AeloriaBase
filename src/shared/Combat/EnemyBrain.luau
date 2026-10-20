--!strict
--[[
	EnemyBrain

	The decision-making half of an enemy, with no Roblox APIs: the server feeds it the distance to
	its target and whether it may attack, and acts on the events it returns. Pure Luau; covered by
	tests/EnemyBrain.spec.luau.

	  idle -> chase -> windup -> (strike) -> recover -> chase
	  any state but dead -> stagger when poise breaks -> chase
	  frozen pauses everything until it thaws

	Wind-ups always last `windupSeconds`, which is what makes every attack readable and dodgeable.
]]

local Enemies = require("../Config/Enemies")

export type StateName = "idle" | "chase" | "windup" | "recover" | "stagger" | "dead"

export type Brain = {
	def: Enemies.EnemyDef,
	state: StateName,
	stateEndsAt: number,
	poise: number,
	nextAttackAt: number,
	-- Set while frozen; timers resume where they left off when the freeze ends.
	frozenSince: number?,
}

export type Input = {
	now: number,
	-- Distance to the closest valid target, or nil when there is none.
	targetDistance: number?,
	-- Whether the shared attack budget lets this enemy start a wind-up.
	canTakeAttackToken: boolean,
	frozen: boolean?,
}

-- What the server should do this step.
export type Event = "none" | "aggro" | "lost" | "windup" | "strike" | "recovered"

local EnemyBrain = {}

function EnemyBrain.new(def: Enemies.EnemyDef): Brain
	return {
		def = def,
		state = "idle",
		stateEndsAt = 0,
		poise = def.poise,
		nextAttackAt = 0,
		frozenSince = nil,
	}
end

local function enter(brain: Brain, state: StateName, now: number, seconds: number?)
	brain.state = state
	brain.stateEndsAt = now + (seconds or 0)
end

-- Whether this enemy holds one of the shared attack slots.
function EnemyBrain.holdsAttackToken(brain: Brain): boolean
	return brain.state == "windup" or brain.state == "recover"
end

function EnemyBrain.step(brain: Brain, input: Input): Event
	local now = input.now
	local def = brain.def
	local distance = input.targetDistance

	if brain.state == "dead" then
		return "none"
	end
	if input.frozen then
		brain.frozenSince = brain.frozenSince or now
		return "none"
	end
	if brain.frozenSince then
		local paused = now - brain.frozenSince
		brain.stateEndsAt += paused
		brain.nextAttackAt += paused
		brain.frozenSince = nil
	end

	if brain.state == "idle" then
		if distance and distance <= def.aggroRange then
			enter(brain, "chase", now)
			return "aggro"
		end
		return "none"
	end

	if brain.state == "chase" then
		if not distance or distance > def.leashRange then
			enter(brain, "idle", now)
			return "lost"
		end
		if distance <= def.attackRange and now >= brain.nextAttackAt and input.canTakeAttackToken then
			enter(brain, "windup", now, def.windupSeconds)
			return "windup"
		end
		return "none"
	end

	if now < brain.stateEndsAt then
		return "none"
	end

	if brain.state == "windup" then
		enter(brain, "recover", now, def.recoverSeconds)
		return "strike"
	end

	-- recover or stagger finished
	brain.nextAttackAt = now + (if brain.state == "recover" then def.attackCooldown else 0)
	enter(brain, "chase", now)
	return "recovered"
end

-- Applies poise damage. Returns true if this hit broke poise and staggered the enemy, which also
-- cancels a wind-up in progress.
function EnemyBrain.hit(brain: Brain, poiseDamage: number, now: number): boolean
	if brain.state == "dead" then
		return false
	end
	if brain.state == "idle" then
		enter(brain, "chase", now)
	end
	brain.poise -= poiseDamage
	if brain.poise > 0 then
		return false
	end
	brain.poise = brain.def.poise
	enter(brain, "stagger", now, brain.def.staggerSeconds)
	return true
end

function EnemyBrain.kill(brain: Brain, now: number)
	enter(brain, "dead", now)
end

return EnemyBrain
