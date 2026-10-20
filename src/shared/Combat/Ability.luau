--!strict
--[[
	Ability

	Per-hero combat timing: the Basic Attack chain, charged attacks, plunges, the Technique
	cooldown, Finale energy and the recovery after each action, plus elemental infusions from
	other heroes' Relays. The server runs this for every request; the client runs the same code
	to time its inputs and count down its HUD. Pure Luau; covered by tests/Ability.spec.luau.

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
	techniqueReadyAt: number,
	finaleReadyAt: number,
	energy: number,
	-- Basic attacks left that carry an infused element, and which element.
	infusedHits: number,
	infusedElement: string?,
}

local Ability = {}

function Ability.new(): State
	return {
		comboIndex = 0,
		lastAttackAt = -math.huge,
		busyUntil = -math.huge,
		techniqueReadyAt = -math.huge,
		finaleReadyAt = -math.huge,
		energy = 0,
		infusedHits = 0,
		infusedElement = nil,
	}
end

local function free(state: State, now: number, tolerance: number): boolean
	return now >= state.busyUntil - tolerance
end

-- Plays the next hit of the chain. Returns the chain index played, or nil if still recovering.
function Ability.tryAttack(state: State, kit: Heroes.Kit, now: number, tolerance: number): number?
	if not free(state, now, tolerance) then
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

function Ability.tryCharged(state: State, kit: Heroes.Kit, now: number, tolerance: number): boolean
	if not free(state, now, tolerance) then
		return false
	end
	state.comboIndex = 0
	state.lastAttackAt = now
	state.busyUntil = now + kit.charged.recovery
	return true
end

-- A plunge lands at the end of a fall; it is always allowed unless another action is playing.
function Ability.tryPlunge(state: State, now: number, tolerance: number): boolean
	if not free(state, now, tolerance) then
		return false
	end
	state.comboIndex = 0
	state.lastAttackAt = now
	state.busyUntil = now + 0.35
	return true
end

function Ability.tryTechnique(state: State, kit: Heroes.Kit, now: number, tolerance: number): boolean
	if not free(state, now, tolerance) or now < state.techniqueReadyAt - tolerance then
		return false
	end
	state.techniqueReadyAt = now + kit.technique.cooldown
	state.busyUntil = now + kit.technique.recovery
	state.comboIndex = 0
	return true
end

function Ability.finaleReady(state: State, kit: Heroes.Kit, now: number, tolerance: number): boolean
	return state.energy >= kit.finale.energyCost and now >= state.finaleReadyAt - tolerance
end

function Ability.tryFinale(state: State, kit: Heroes.Kit, now: number, tolerance: number): boolean
	if not free(state, now, tolerance) or not Ability.finaleReady(state, kit, now, tolerance) then
		return false
	end
	state.energy = 0
	state.finaleReadyAt = now + kit.finale.cooldown
	state.busyUntil = now + kit.finale.recovery
	state.comboIndex = 0
	return true
end

function Ability.addEnergy(state: State, kit: Heroes.Kit, amount: number)
	state.energy = math.clamp(state.energy + amount, 0, kit.finale.energyCost)
end

-- Swapping out cancels the outgoing hero's recovery, so a swap can cut a combo short.
function Ability.cancelRecovery(state: State)
	state.busyUntil = -math.huge
	state.comboIndex = 0
end

function Ability.infuse(state: State, element: string, hits: number)
	state.infusedElement = element
	state.infusedHits = hits
end

-- The element the next basic attack carries from an infusion, if any. Uses one charge.
function Ability.takeInfusion(state: State): string?
	if state.infusedHits <= 0 or not state.infusedElement then
		return nil
	end
	state.infusedHits -= 1
	local element = state.infusedElement
	if state.infusedHits <= 0 then
		state.infusedElement = nil
	end
	return element
end

return Ability
