--!strict
--[[
	Clip

	A clip is a list of timed poses. Sampling it at a time gives the blended pose; events mark
	moments gameplay or effects care about ("hit" when the weapon connects, "trailOn", "step").

	  {
	      name = "sword_1",
	      length = 0.55,
	      loop = false,
	      keys = {
	          { t = 0, pose = { ... } },
	          { t = 0.08, ease = "snap", pose = { ... } },   -- eases from the key before
	          { t = 0.55, ease = "inout", pose = { ... } },
	      },
	      events = { { t = 0.08, name = "hit" } },
	  }

	A key's ease shapes the move that ends on that key. Keys must be in time order. Looping clips
	treat the last key as the same moment as the first, so their final pose should match it.

	Pure Luau with no Roblox APIs; covered by tests/Anim.spec.luau.
]]

local Ease = require(script.Parent.Ease)
local Pose = require(script.Parent.Pose)

export type Key = {
	t: number,
	pose: Pose.Pose,
	ease: string?,
}

export type Event = {
	t: number,
	name: string,
}

export type Clip = {
	name: string,
	length: number,
	loop: boolean,
	keys: { Key },
	events: { Event }?,
}

local Clip = {}

-- The pose at `time` seconds. Looping clips wrap; others hold their last pose.
function Clip.sample(clip: Clip, time: number): Pose.Pose
	local keys = clip.keys
	local count = #keys
	if count == 0 then
		return {}
	end
	local t = time
	if clip.loop and clip.length > 0 then
		t = time % clip.length
	end
	if count == 1 or t <= keys[1].t then
		return Pose.copy(keys[1].pose)
	end
	if t >= keys[count].t then
		-- A looping clip returns to its first pose across the seam; others hold the end.
		if clip.loop and clip.length > keys[count].t then
			local u = (t - keys[count].t) / (clip.length - keys[count].t)
			return Pose.lerp(keys[count].pose, keys[1].pose, Ease.apply(keys[1].ease, u))
		end
		return Pose.copy(keys[count].pose)
	end
	-- Find the segment the time falls into.
	local index = 1
	for i = 1, count - 1 do
		if t >= keys[i].t and t < keys[i + 1].t then
			index = i
			break
		end
	end
	local a, b = keys[index], keys[index + 1]
	local span = b.t - a.t
	local u = if span > 0 then (t - a.t) / span else 1
	return Pose.lerp(a.pose, b.pose, Ease.apply(b.ease, u))
end

-- Events that fall in the half-open window (from, to], with looping handled: a window that
-- crosses the end of a looping clip also catches events at the start.
function Clip.eventsBetween(clip: Clip, from: number, to: number): { Event }
	local found: { Event } = {}
	local events = clip.events
	if not events or to <= from then
		return found
	end
	if clip.loop and clip.length > 0 then
		local startCycle = math.floor(from / clip.length)
		local endCycle = math.floor(to / clip.length)
		for cycle = startCycle, endCycle do
			local offset = cycle * clip.length
			for _, event in events do
				local at = offset + event.t
				if at > from and at <= to then
					table.insert(found, event)
				end
			end
		end
	else
		for _, event in events do
			if event.t > from and event.t <= to then
				table.insert(found, event)
			end
		end
	end
	return found
end

-- Whether the clip has played all the way through (looping clips never finish).
function Clip.isFinished(clip: Clip, time: number): boolean
	return not clip.loop and time >= clip.length
end

-- Time of the first event with this name, or nil.
function Clip.eventTime(clip: Clip, name: string): number?
	for _, event in clip.events or {} do
		if event.name == name then
			return event.t
		end
	end
	return nil
end

-- Checks a clip's shape; returns a problem description or nil. Used by tests so a typo in clip
-- data fails in CI instead of looking wrong in game.
function Clip.validate(clip: Clip): string?
	if #clip.keys == 0 then
		return "no keys"
	end
	local last = -1
	for index, key in clip.keys do
		if key.t < last then
			return `key {index} is out of order`
		end
		last = key.t
		if key.ease and not Ease.has(key.ease) then
			return `key {index} has unknown ease "{key.ease}"`
		end
		local pose: any = key.pose
		for name in pose do
			local known = false
			for _, channel in Pose.channels do
				if channel.name == name then
					known = true
					break
				end
			end
			if not known then
				return `key {index} has unknown channel "{name}"`
			end
		end
	end
	if clip.keys[#clip.keys].t > clip.length + 1e-6 then
		return "a key is after the clip's length"
	end
	for _, event in clip.events or {} do
		if event.t < 0 or event.t > clip.length + 1e-6 then
			return `event "{event.name}" is outside the clip`
		end
	end
	return nil
end

return Clip
