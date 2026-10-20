--!strict
--[[
	Idles

	Every hero stands differently. An idle style is a function of time that returns a pose, built
	the same way as Locomotion.idle (breathing, weight shifts and small gestures on slow, unrelated
	cycles so nothing visibly repeats). Heroes name their style in Config.Heroes; the animator
	cross-fades it with the gait exactly like the default idle.

	Pure Luau with no Roblox APIs.
]]

local Locomotion = require(script.Parent.Locomotion)
local Pose = require(script.Parent.Pose)

local swing = Locomotion.swing

export type Style = (t: number) -> Pose.Pose

local Idles = {}

local function smooth(t: number): number
	local u = math.clamp(t, 0, 1)
	return u * u * (3 - 2 * u)
end

-- A gesture window: rises over `attack` seconds, holds, and falls, once every `period` seconds,
-- starting `offset` seconds into the period. 0 outside the window.
local function pulse(t: number, period: number, offset: number, attack: number, hold: number): number
	local u = (t - offset) % period
	if u < attack then
		return smooth(u / attack)
	elseif u < attack + hold then
		return 1
	elseif u < attack * 2 + hold then
		return 1 - smooth((u - attack - hold) / attack)
	end
	return 0
end

local styles: { [string]: Style } = {}

styles.default = Locomotion.idle

-- A tinkerer: weight on one hip, the working hand resting on the tool belt, the other arm loose.
-- Now and then she glances down at the belt and taps a finger, or rolls a shoulder.
styles.tinkerer = function(t: number): Pose.Pose
	local breathe = math.sin(t * 1.7)
	local sway = math.sin(t * 0.48)
	local glance = pulse(t, 9.5, 2.5, 0.6, 1.4)
	local tap = pulse(t, 9.5, 3.2, 0.12, 0.08) + pulse(t, 9.5, 3.55, 0.12, 0.08)
	local roll = pulse(t, 14, 8, 0.5, 0.3)
	return {
		-- Hip pushed out to her left, torso counter-leaning so the shoulders stay level.
		hipPos = { 0.09 + sway * 0.012, breathe * 0.01 - 0.015, 0 },
		hipRot = { 0, 4 + sway * 1.5, -6 + sway * 1.2 },
		waist = { 2 + breathe * 0.8 + glance * 6, -5 - sway * 1.2, 5 - sway * 0.6 },
		neck = { -1 - breathe * 0.5 + glance * 16, 10 * glance + math.sin(t * 0.33) * 3, -3 * glance },
		-- Right hand on the belt: upper arm back and out, elbow folded, wrist turned in.
		armR = swing(-14 + roll * 10, 24 + roll * 12, 1, 14),
		elbowR = 96 + breathe * 2 + tap * 5,
		wristR = { 12 + tap * 18, -20, 10 },
		-- Left arm hangs loose, a little forward.
		armL = swing(7 + breathe * 1.4, 8 + breathe * 1.2, -1),
		elbowL = 14 + breathe * 1.8,
		wristL = { 6, 0, 0 },
		-- Standing leg straight, free leg soft and a little forward.
		legR = swing(-1, 6 + sway * 0.6, 1),
		legL = swing(5, 9 - sway * 0.8, -1),
		kneeR = 2,
		kneeL = 12 + sway * 1.5,
		ankleR = { 0, 0, 0 },
		ankleL = { -4, 0, 0 },
	}
end

-- A healer: upright and still, hands gently clasped in front, slow breathing, a soft look around.
styles.gentle = function(t: number): Pose.Pose
	local breathe = math.sin(t * 1.5)
	local sway = math.sin(t * 0.4)
	local look = math.sin(t * 0.29)
	return {
		hipPos = { sway * 0.01, breathe * 0.008 - 0.005, 0 },
		hipRot = { 0, sway * 0.8, sway * 0.6 },
		waist = { 1 + breathe * 0.6, -sway * 0.8, 0 },
		neck = { -2 - breathe * 0.4, look * 6, look * 1.5 },
		armR = swing(26, 10, 1, -18),
		armL = swing(26, 10, -1, 18),
		elbowR = 58 + breathe * 2,
		elbowL = 58 + breathe * 2,
		wristR = { 10, 0, -30 },
		wristL = { 10, 0, 30 },
		legR = swing(0, 2.5 + sway * 0.4, 1),
		legL = swing(0, 2.5 - sway * 0.4, -1),
		kneeR = 2 + sway * 0.5,
		kneeL = 2 - sway * 0.5,
	}
end

-- A scholar: arms folded, chin a little up, occasionally shifting weight and tapping a finger.
styles.folded = function(t: number): Pose.Pose
	local breathe = math.sin(t * 1.6)
	local sway = math.sin(t * 0.45)
	local tap = pulse(t, 7, 3, 0.1, 0.1) + pulse(t, 7, 3.3, 0.1, 0.1)
	local nod = pulse(t, 11, 6, 0.8, 0.6)
	return {
		hipPos = { -0.03 + sway * 0.015, breathe * 0.009 - 0.008, 0 },
		hipRot = { 0, -2 + sway * 1.0, 3 + sway * 0.8 },
		waist = { 3 + breathe * 0.7, 3 - sway * 1.0, -2 },
		neck = { -6 + nod * 10 - breathe * 0.4, math.sin(t * 0.3) * 4, nod * 2 },
		armR = swing(38, 4, 1, 40),
		armL = swing(36, 4, -1, -40),
		elbowR = 118 + breathe * 1.5,
		elbowL = 116 + breathe * 1.5,
		wristR = { 0, 10 + tap * 14, -20 },
		wristL = { 0, -10, 20 },
		legR = swing(-2, 7 + sway * 0.5, 1),
		legL = swing(2, 5 - sway * 0.5, -1),
		kneeR = 3,
		kneeL = 8 + sway * 1.0,
		ankleL = { -2, 0, 0 },
	}
end

function Idles.get(name: string?): Style
	return (name and styles[name]) or styles.default
end

Idles.styles = styles

return Idles
