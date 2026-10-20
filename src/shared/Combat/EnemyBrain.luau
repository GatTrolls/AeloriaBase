--!strict
--[[
	EnemyBrain

	The decision-making half of an enemy, with no Roblox APIs: the server feeds it the distance to
	its target and whether it may attack, and acts on the events it returns. Pure Luau; covered by
	tests/EnemyBrain.spec.luau.

	  idle -> chase -> windup -> (strike) -> recover -> chase
	  grunts flinch into stagger when their poise breaks; elites ignore poise
	  elites and bosses fill a Composure bar; when it breaks they are Rattled for a few seconds
	  frozen (Lock, a Slip's slow, a Finale) pauses everything until it ends

	Each attack's wind-up lasts its full `windupSeconds`, which is what makes every attack
	readable and answerable.
]]

local CombatConfig = require("../Config/CombatConfig")
local Enemies = require("../Config/Enemies")

export type StateName = "idle" | "chase" | "windup" | "recover" | "stagger" | "rattled" | "dead"

export type Brain = {
	def: Enemies.EnemyDef,
	state: StateName,
	stateEndsAt: number,
	poise: number,
	composure: number,
	nextAttackAt: number,
	attackReadyAt: { [string]: number },
	attack: Enemies.AttackDef?,
	-- The attack to use next regardless of the usual choice (after a Rattled window).
	forced: string?,
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
	-- 0 to 1, for choosing between attacks. Defaults to the first eligible attack.
	roll: number?,
}

export type Event = "none" | "aggro" | "lost" | "windup" | "strike" | "recovered"

local EnemyBrain = {}

function EnemyBrain.new(def: Enemies.EnemyDef): Brain
	return {
		def = def,
		state = "idle",
		stateEndsAt = 0,
		poise = def.poise,
		composure = 0,
		nextAttackAt = 0,
		attackReadyAt = {},
		attack = nil,
		forced = nil,
		frozenSince = nil,
	}
end

local function enter(brain: Brain, state: StateName, now: number, seconds: number?)
	brain.state = state
	brain.stateEndsAt = now + (seconds or 0)
end

local function findAttack(def: Enemies.EnemyDef, id: string): Enemies.AttackDef?
	for _, attack in def.attacks do
		if attack.id == id then
			return attack
		end
	end
	return nil
end

local function chooseAttack(brain: Brain, distance: number, now: number, roll: number): Enemies.AttackDef?
	if brain.forced then
		local forced = findAttack(brain.def, brain.forced)
		if forced and distance <= forced.maxRange then
			brain.forced = nil
			return forced
		end
	end
	local eligible = {}
	local total = 0
	for _, attack in brain.def.attacks do
		if distance <= attack.maxRange and now >= (brain.attackReadyAt[attack.id] or 0) then
			table.insert(eligible, attack)
			total += attack.weight
		end
	end
	if #eligible == 0 then
		return nil
	end
	local pick = roll * total
	for _, attack in eligible do
		pick -= attack.weight
		if pick <= 0 then
			return attack
		end
	end
	return eligible[#eligible]
end

-- Whether this enemy holds one of the shared attack slots.
function EnemyBrain.holdsAttackToken(brain: Brain): boolean
	return brain.state == "windup" or brain.state == "recover"
end

function EnemyBrain.isRattled(brain: Brain): boolean
	return brain.state == "rattled"
end

-- The shortest reach of any attack, for deciding how close to stand.
function EnemyBrain.reach(def: Enemies.EnemyDef): number
	local reach = math.huge
	for _, attack in def.attacks do
		reach = math.min(reach, attack.maxRange)
	end
	return reach
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
		if now >= brain.nextAttackAt and input.canTakeAttackToken then
			local attack = chooseAttack(brain, distance, now, input.roll or 0)
			if attack then
				brain.attack = attack
				enter(brain, "windup", now, attack.windupSeconds)
				return "windup"
			end
		end
		return "none"
	end

	if now < brain.stateEndsAt then
		return "none"
	end

	if brain.state == "windup" then
		local attack = brain.attack :: Enemies.AttackDef
		brain.attackReadyAt[attack.id] = now + attack.cooldown
		enter(brain, "recover", now, attack.recoverSeconds)
		return "strike"
	end

	if brain.state == "rattled" then
		brain.composure = 0
		brain.forced = def.afterRattled
	end
	-- recover, stagger or rattled finished
	brain.nextAttackAt = now + (if brain.state == "recover" then def.attackCooldown else 0)
	brain.attack = nil
	enter(brain, "chase", now)
	return "recovered"
end

local function interruptInto(brain: Brain, state: StateName, seconds: number, now: number)
	brain.attack = nil
	enter(brain, state, now, seconds)
end

-- Applies poise damage. Returns true if this hit made the enemy flinch, which also cancels a
-- wind-up in progress. Enemies with infinite poise (elites) never flinch.
function EnemyBrain.hit(brain: Brain, poiseDamage: number, now: number): boolean
	if brain.state == "dead" then
		return false
	end
	if brain.state == "idle" then
		enter(brain, "chase", now)
	end
	if brain.state == "rattled" or brain.def.poise == math.huge then
		return false
	end
	brain.poise -= poiseDamage
	if brain.poise > 0 then
		return false
	end
	brain.poise = brain.def.poise
	interruptInto(brain, "stagger", brain.def.staggerSeconds, now)
	return true
end

-- Fills the Composure bar. Returns true if it broke and the enemy is now Rattled.
function EnemyBrain.addComposure(brain: Brain, amount: number, now: number): boolean
	local max = brain.def.composure
	if not max or brain.state == "dead" or brain.state == "rattled" then
		return false
	end
	if brain.state == "idle" then
		enter(brain, "chase", now)
	end
	brain.composure = math.min(max, brain.composure + amount)
	if brain.composure < max then
		return false
	end
	interruptInto(brain, "rattled", CombatConfig.Combat.RattledSeconds, now)
	return true
end

-- Cancels the current action and stuns briefly: a Lift, or a heavy knock-back.
function EnemyBrain.interrupt(brain: Brain, seconds: number, now: number)
	if brain.state == "dead" or brain.state == "rattled" then
		return
	end
	interruptInto(brain, "stagger", seconds, now)
end

function EnemyBrain.kill(brain: Brain, now: number)
	interruptInto(brain, "dead", 0, now)
end

return EnemyBrain
