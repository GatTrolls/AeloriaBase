--!strict
--[[
	Defense

	The defensive layer's rules: dodge charges, Slips (perfect dodges) and Lifts (parries).
	Pure Luau; covered by tests/Defense.spec.luau.

	  * Dodge: three in a row, then a short cooldown. A quiet moment resets the chain.
	  * Slip: a dodge just before a hit lands.
	  * Lift: an attack just before a gold-flash attack lands interrupts it.

	Timing is judged on the server's clock, which sees a player's input late by about half
	their ping, while the player reacted to an enemy they saw late by the other half. So every
	enemy strike is decided at `resolveAt` = the moment it lands + a latency allowance, and an
	input that arrives in between still counts.
]]

local CombatConfig = require("../Config/CombatConfig")

local Config = CombatConfig.Defense

export type DodgeState = {
	chainCount: number,
	lastDodgeAt: number,
	lockedUntil: number,
}

local Defense = {}

function Defense.newDodge(): DodgeState
	return { chainCount = 0, lastDodgeAt = -math.huge, lockedUntil = -math.huge }
end

-- Dodges left before the cooldown, as the HUD shows them.
function Defense.chargesLeft(state: DodgeState, now: number): number
	if now < state.lockedUntil then
		return 0
	end
	if now - state.lastDodgeAt > Config.DodgeChainResetSeconds then
		return Config.DodgeCharges
	end
	return Config.DodgeCharges - state.chainCount
end

function Defense.tryDodge(state: DodgeState, now: number): boolean
	if now < state.lockedUntil or now - state.lastDodgeAt < Config.DodgeMinGapSeconds then
		return false
	end
	if now - state.lastDodgeAt > Config.DodgeChainResetSeconds then
		state.chainCount = 0
	end
	state.chainCount += 1
	state.lastDodgeAt = now
	if state.chainCount >= Config.DodgeCharges then
		state.chainCount = 0
		state.lockedUntil = now + Config.DodgeLockoutSeconds
	end
	return true
end

-- When an enemy strike landing at `strikeAt` is decided.
function Defense.resolveAt(strikeAt: number): number
	return strikeAt + Config.LatencyAllowance
end

-- Whether a dodge at `dodgeAt` avoids a strike: it was invulnerable when the strike landed,
-- or the dodge arrived between the strike landing and the decision.
function Defense.evades(dodgeAt: number, strikeAt: number, resolveAt: number): boolean
	if dodgeAt <= strikeAt then
		return strikeAt - dodgeAt <= Config.DodgeInvulnerableSeconds
	end
	return dodgeAt <= resolveAt
end

function Defense.isSlip(dodgeAt: number, strikeAt: number, resolveAt: number, assist: boolean?): boolean
	local window = if assist then Config.SlipWindowAssist else Config.SlipWindow
	return dodgeAt >= strikeAt - window and dodgeAt <= resolveAt
end

function Defense.isLift(attackAt: number, strikeAt: number, resolveAt: number, assist: boolean?): boolean
	local window = if assist then Config.LiftWindowAssist else Config.LiftWindow
	return attackAt >= strikeAt - window and attackAt <= resolveAt
end

return Defense
