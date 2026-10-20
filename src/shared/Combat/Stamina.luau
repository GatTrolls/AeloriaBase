--!strict
--[[
	Stamina

	One stamina bar shared by sprint, climb, glide and dodge. The server keeps the real value and
	works it out from timestamps, so it never trusts a number the client sends. Pure Luau; covered
	by tests/Stamina.spec.luau.

	  * A draining activity (sprint, climb, glide) drains continuously while it is on.
	  * Instant costs (dodge, climb leap) are spent in one go and fail if there is not enough.
	  * Regeneration starts RegenDelaySeconds after the last spend or the end of an activity.
	  * Running out ends the activity; `update` reports that so the server can tell the client.
]]

local CombatConfig = require("../Config/CombatConfig")

export type Activity = "none" | "sprint" | "climb" | "glide"

export type State = {
	value: number,
	activity: Activity,
	updatedAt: number,
	-- Regeneration resumes RegenDelaySeconds after this time.
	lastSpendAt: number,
}

local Config = CombatConfig.Stamina

local DRAIN: { [Activity]: number } = {
	none = 0,
	sprint = Config.SprintPerSecond,
	climb = Config.ClimbPerSecond,
	glide = Config.GlidePerSecond,
}

local Stamina = {}

function Stamina.new(now: number): State
	return { value = Config.Max, activity = "none", updatedAt = now, lastSpendAt = -math.huge }
end

function Stamina.isActivity(value: unknown): boolean
	return type(value) == "string" and DRAIN[value :: Activity] ~= nil and value ~= "none"
end

-- Brings the state up to `now`. Returns true if a draining activity ran out of stamina.
function Stamina.update(state: State, now: number): boolean
	local elapsed = now - state.updatedAt
	if elapsed <= 0 then
		return false
	end
	state.updatedAt = now

	if state.activity ~= "none" then
		state.value -= DRAIN[state.activity] * elapsed
		state.lastSpendAt = now
		if state.value <= 0 then
			state.value = 0
			state.activity = "none"
			return true
		end
		return false
	end

	local regenFrom = math.max(now - elapsed, state.lastSpendAt + Config.RegenDelaySeconds)
	if now > regenFrom then
		state.value = math.min(Config.Max, state.value + Config.RegenPerSecond * (now - regenFrom))
	end
	return false
end

-- Starts or stops a draining activity. Starting fails with no stamina left.
function Stamina.setActivity(state: State, activity: Activity, now: number): boolean
	Stamina.update(state, now)
	if activity ~= "none" and state.value <= 0 then
		return false
	end
	if state.activity ~= "none" and activity == "none" then
		state.lastSpendAt = now
	end
	state.activity = activity
	return true
end

-- Spends a fixed cost. Fails, spending nothing, if there is not enough.
function Stamina.spend(state: State, amount: number, now: number): boolean
	Stamina.update(state, now)
	if state.value < amount then
		return false
	end
	state.value -= amount
	state.lastSpendAt = now
	return true
end

return Stamina
