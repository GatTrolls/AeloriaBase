--!strict
--[[
	Ability

	Per-hero combat timing: the normal attack chain, the elemental skill cooldown, burst energy and
	the recovery after each action. The server runs this for every request; the client runs the
	same code to predict its HUD. Pure Luau; covered by tests/Ability.spec.luau.

	Times are absolute (seconds). `tolerance` lets a request arrive slightly early, so normal
	network jitter does not eat inputs.
]]

local CombatConfig = require("../Config/CombatConfig")
local Heroes = require("../Config/Heroes")

export type State = {
	comboIndex: number, -- last chain hit played, 0 = chain not started
	lastAttackAt: number,
	-- No new action is accepted before this time.
	busyUntil: number,
	skillReadyAt: number,
	burstReadyAt: number,
	energy: number,
}

local Ability = {}

function Ability.new(): State
	return {
		comboIndex = 0,
		lastAttackAt = -math.huge,
		busyUntil = -math.huge,
		skillReadyAt = -math.huge,
		burstReadyAt = -math.huge,
		energy = 0,
	}
end

-- Plays the next hit of the chain. Returns the chain index played, or nil if still recovering.
function Ability.tryAttack(state: State, kit: Heroes.Kit, now: number, tolerance: number): number?
	if now < state.busyUntil - tolerance then
		return nil
	end
	if now - state.lastAttackAt > CombatConfig.Combat.ComboResetSeconds then
		state.comboIndex = 0
	end
	state.comboIndex = state.comboIndex % #kit.chain + 1
	state.lastAttackAt = now
	state.busyUntil = now + kit.chain[state.comboIndex].recovery
	return state.comboIndex
end

function Ability.trySkill(state: State, kit: Heroes.Kit, now: number, tolerance: number): boolean
	if now < state.busyUntil - tolerance or now < state.skillReadyAt - tolerance then
		return false
	end
	state.skillReadyAt = now + kit.skill.cooldown
	state.busyUntil = now + kit.skill.recovery
	state.comboIndex = 0
	return true
end

function Ability.burstReady(state: State, kit: Heroes.Kit, now: number, tolerance: number): boolean
	return state.energy >= kit.burst.energyCost and now >= state.burstReadyAt - tolerance
end

function Ability.tryBurst(state: State, kit: Heroes.Kit, now: number, tolerance: number): boolean
	if now < state.busyUntil - tolerance or not Ability.burstReady(state, kit, now, tolerance) then
		return false
	end
	state.energy = 0
	state.burstReadyAt = now + kit.burst.cooldown
	state.busyUntil = now + kit.burst.recovery
	state.comboIndex = 0
	return true
end

function Ability.addEnergy(state: State, kit: Heroes.Kit, amount: number)
	state.energy = math.clamp(state.energy + amount, 0, kit.burst.energyCost)
end

-- Swapping heroes cancels the outgoing hero's recovery, so a swap can cut a combo short.
function Ability.cancelRecovery(state: State)
	state.busyUntil = -math.huge
	state.comboIndex = 0
end

return Ability
