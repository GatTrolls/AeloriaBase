--!strict
--[[
	Elements

	The status and reaction engine. Pure Luau, so it runs on the server and in the Lune tests
	(tests/Elements.spec.luau).

	Model:
	  * Flame, Tide, Frost and Volt leave a status on the target (Burning, Wet, Chilled,
	    Charged) for a few seconds. A target holds one status at a time.
	  * The same element again refreshes the status.
	  * A different element on a status triggers a reaction and uses the status up. Every pair
	    of the four status elements has a reaction.
	  * Gale, Terra and Astral never stay. On a status they trigger Sweep, Geode or Starburst;
	    on a clean target they do nothing elemental.
	  * Basic attacks apply their element at most once every 2.5 seconds per source and target;
	    Techniques, Finales and Relays always apply.
	  * Starburst works once per enemy every 2 seconds.

	The engine also keeps timed effects that reactions and abilities leave on a target (Locked,
	Brittle, Rattled, Slowed and so on) and per-element resistance cuts from Sweep.

	Target state is mutated in place, because combat calls this many times a second and a new
	table per hit would add garbage-collection pressure for no benefit.
]]

local ElementConfig = require("./Config/ElementConfig")

export type Status = {
	element: string,
	expiresAt: number,
}

export type TargetState = {
	status: Status?,
	-- effect id -> time it ends
	effects: { [string]: number },
	-- element -> time a Sweep resistance cut ends
	resistanceCuts: { [string]: number },
	-- source key -> last time its basic attack applied an element here
	lastBasicApply: { [string]: number },
	lastStarburstAt: number,
}

export type ApplyOptions = {
	-- Basic attacks are limited by BasicApplySeconds; everything else always applies.
	basic: boolean?,
	-- Who is attacking with what, for example "123:hero_main". Required for basic attacks.
	sourceKey: string?,
}

export type ApplyResult = {
	-- Whether the element landed at all (a basic attack inside its cooldown does not).
	applied: boolean,
	reaction: ElementConfig.ReactionDef?,
	-- The status element the reaction used up.
	consumed: string?,
	-- Multiply the triggering hit by this (Scald, Thaw); 1 otherwise.
	hitMultiplier: number,
	-- The element on the target after this hit, if any.
	statusAfter: string?,
}

local Elements = {}

function Elements.newTarget(): TargetState
	return {
		status = nil,
		effects = {},
		resistanceCuts = {},
		lastBasicApply = {},
		lastStarburstAt = -math.huge,
	}
end

function Elements.isStatusElement(element: string): boolean
	return ElementConfig.Statuses[element] ~= nil
end

-- The element of the target's current status, or nil if it has none or it has run out.
function Elements.statusOf(target: TargetState, now: number): string?
	local status = target.status
	if status and status.expiresAt > now then
		return status.element
	end
	target.status = nil
	return nil
end

function Elements.setEffect(target: TargetState, effectId: string, seconds: number, now: number)
	target.effects[effectId] = math.max(target.effects[effectId] or 0, now + seconds)
end

function Elements.clearEffect(target: TargetState, effectId: string)
	target.effects[effectId] = nil
end

function Elements.hasEffect(target: TargetState, effectId: string, now: number): boolean
	local endsAt = target.effects[effectId]
	return endsAt ~= nil and endsAt > now
end

-- How much Sweep has cut the target's resistance to an element (0 when it hasn't).
function Elements.resistanceCut(target: TargetState, element: string, now: number): number
	local endsAt = target.resistanceCuts[element]
	if endsAt and endsAt > now then
		return ElementConfig.TriggerReactions.Gale.resistanceCut or 0
	end
	return 0
end

-- Puts a status on the target directly, without reacting. Used when Sweep spreads a status.
function Elements.setStatus(target: TargetState, element: string, now: number)
	local def = ElementConfig.Statuses[element]
	if def then
		target.status = { element = element, expiresAt = now + def.seconds }
	end
end

-- If the target is Locked, breaks the ice and returns true. The caller adds the shatter damage.
function Elements.shatter(target: TargetState, now: number): boolean
	if Elements.hasEffect(target, "Locked", now) then
		target.effects.Locked = nil
		return true
	end
	return false
end

local function result(applied: boolean, target: TargetState, now: number): ApplyResult
	return {
		applied = applied,
		reaction = nil,
		consumed = nil,
		hitMultiplier = 1,
		statusAfter = Elements.statusOf(target, now),
	}
end

function Elements.apply(
	target: TargetState,
	element: string,
	now: number,
	options: ApplyOptions?
): ApplyResult
	local opts: ApplyOptions = options or {}
	if opts.basic then
		local key = opts.sourceKey or "?"
		local last = target.lastBasicApply[key]
		if last and now - last < ElementConfig.BasicApplySeconds then
			return result(false, target, now)
		end
		target.lastBasicApply[key] = now
	end

	local current = Elements.statusOf(target, now)
	local statusDef = ElementConfig.Statuses[element]

	if not current then
		if statusDef then
			target.status = { element = element, expiresAt = now + statusDef.seconds }
		end
		return result(true, target, now)
	end

	if current == element then
		local status = target.status :: Status
		status.expiresAt = math.max(status.expiresAt, now + (statusDef :: ElementConfig.StatusDef).seconds)
		return result(true, target, now)
	end

	local reaction = ElementConfig.reactionFor(element, current)
	if not reaction then
		return result(true, target, now)
	end

	if reaction.kind == "starburst" then
		if now - target.lastStarburstAt < (reaction.cooldownSeconds or 0) then
			-- Too soon for another Starburst on this enemy: the hit lands, the status stays.
			return result(true, target, now)
		end
		target.lastStarburstAt = now
	end

	-- Every reaction uses the status up.
	target.status = nil

	if reaction.kind == "lock" then
		Elements.setEffect(target, "Locked", reaction.seconds or 0, now)
	elseif reaction.kind == "weaken" then
		Elements.setEffect(target, "Brittle", reaction.seconds or 0, now)
	elseif reaction.kind == "spread" then
		target.resistanceCuts[current] = now + (reaction.seconds or 0)
	end

	return {
		applied = true,
		reaction = reaction,
		consumed = current,
		hitMultiplier = if reaction.kind == "amplify" then reaction.multiplier or 1 else 1,
		statusAfter = nil,
	}
end

return Elements
