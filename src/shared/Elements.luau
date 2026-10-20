--!strict
--[[
	Elements

	The elemental aura and reaction engine. Pure Luau, so it runs on the server and in the
	Lune tests (tests/Elements.spec.luau).

	Model:
	  * A hit can carry an element and a number of units (1 = light, 2 = medium, 4 = heavy).
	  * A target holds at most one aura. It decays linearly from the moment it is applied.
	  * A new element meeting a different aura looks up "Trigger>Aura" in ElementConfig. If it
	    reacts, the aura loses `units * consume`, and the trigger does not stay on the target.
	  * Same element, or no reaction: the aura is refreshed to the larger of what is left and
	    the taxed new units.
	  * Internal cooldowns stop fast multi-hit attacks from applying an element on every hit.

	Target state is mutated in place, because combat calls this many times a second and
	allocating a new table per hit would add GC pressure for no benefit.
]]

-- String require works in both Roblox and Lune, so this module stays testable outside Studio.
local ElementConfig = require("./Config/ElementConfig")

export type Aura = {
	element: string,
	units: number,
	ratePerSecond: number,
	appliedAt: number,
}

export type TargetState = {
	aura: Aura?,
	status: { [string]: number }, -- status id -> time it ends
}

export type ApplyResult = {
	reaction: ElementConfig.ReactionDef?,
	-- Multiply the triggering hit by this (amplify reactions); 1 otherwise.
	hitMultiplier: number,
	-- Extra damage scale for transform reactions; 0 otherwise. Damage.transformDamage uses it.
	transformScale: number,
	-- Element to copy to nearby targets (Sweep), if any.
	spreadElement: string?,
	-- Element of the shield to give the attacker (Shield), if any.
	shieldElement: string?,
	auraAfter: string?,
}

export type IcdTracker = { [string]: { hits: number, windowStart: number } }

local Elements = {}

function Elements.newTarget(): TargetState
	return { aura = nil, status = {} }
end

function Elements.auraUnits(aura: Aura, now: number): number
	return math.max(0, aura.units - aura.ratePerSecond * (now - aura.appliedAt))
end

local function setAura(state: TargetState, element: string, units: number, now: number)
	if units <= 0 then
		state.aura = nil
		return
	end
	local duration = ElementConfig.AuraBaseSeconds + ElementConfig.AuraSecondsPerUnit * units
	state.aura = {
		element = element,
		units = units,
		ratePerSecond = units / duration,
		appliedAt = now,
	}
end

-- Current aura element, or nil if it has decayed away.
function Elements.currentAura(state: TargetState, now: number): string?
	local aura = state.aura
	if aura and Elements.auraUnits(aura, now) > 0 then
		return aura.element
	end
	state.aura = nil
	return nil
end

function Elements.hasStatus(state: TargetState, statusId: string, now: number): boolean
	local endsAt = state.status[statusId]
	return endsAt ~= nil and endsAt > now
end

function Elements.apply(state: TargetState, element: string, units: number, now: number): ApplyResult
	local result: ApplyResult = {
		reaction = nil,
		hitMultiplier = 1,
		transformScale = 0,
		spreadElement = nil,
		shieldElement = nil,
		auraAfter = nil,
	}

	local existing = state.aura
	local remaining = if existing then Elements.auraUnits(existing, now) else 0
	local auraElement = if existing and remaining > 0 then existing.element else nil

	local reaction = auraElement
		and auraElement ~= element
		and ElementConfig.Reactions[`{element}>{auraElement}`]

	if reaction and auraElement then
		result.reaction = reaction
		if reaction.kind == "amplify" then
			result.hitMultiplier = reaction.multiplier
		elseif reaction.kind == "transform" then
			result.transformScale = reaction.multiplier
			if reaction.spreads then
				result.spreadElement = auraElement
			end
		elseif reaction.kind == "shield" then
			result.shieldElement = auraElement
		elseif reaction.kind == "status" then
			local seconds = (reaction.statusSecondsPerUnit or 0) * units
			state.status[reaction.id] = math.max(state.status[reaction.id] or 0, now + seconds)
		end
		setAura(state, auraElement, remaining - units * reaction.consume, now)
	elseif not ElementConfig.NonAttaching[element] then
		local taxed = units * ElementConfig.AuraTax
		if auraElement == element then
			setAura(state, element, math.max(remaining, taxed), now)
		elseif auraElement == nil then
			setAura(state, element, taxed, now)
		end
		-- A different aura with no reaction is left alone.
	end

	result.auraAfter = Elements.currentAura(state, now)
	return result
end

function Elements.newIcd(): IcdTracker
	return {}
end

-- Whether a hit from `sourceKey` (for example "userId:skillId") applies its element.
-- Call once per hit; it records the hit.
function Elements.icdAllows(tracker: IcdTracker, sourceKey: string, now: number): boolean
	local entry = tracker[sourceKey]
	if not entry or now - entry.windowStart >= ElementConfig.IcdSeconds then
		tracker[sourceKey] = { hits = 1, windowStart = now }
		return true
	end
	entry.hits += 1
	return (entry.hits - 1) % ElementConfig.IcdHits == 0
end

return Elements
