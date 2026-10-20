--!strict
--[[
	Locomotion

	Procedural poses for moving around: idle breathing, a walk-to-sprint gait that scales
	smoothly with speed, airborne poses, gliding and climbing. They are formulas, not keyframes,
	so a character at any speed looks right and feet match the ground speed.

	The gait phase is a 0..1 cycle (one left and one right step) that the animator advances by
	distance travelled divided by Locomotion.cycleLength(speed), which keeps strides planted.

	Pure Luau with no Roblox APIs; covered by tests/Anim.spec.luau.
]]

local Pose = require(script.Parent.Pose)

local TAU = math.pi * 2

local Locomotion = {}

local function smooth(t: number): number
	local u = math.clamp(t, 0, 1)
	return u * u * (3 - 2 * u)
end

local function lerp(a: number, b: number, t: number): number
	return a + (b - a) * t
end

local function rad(degrees: number): number
	return math.rad(degrees)
end

-- An upper limb or leg that swings forward by `pitch` degrees and out to the side by `out`
-- degrees (positive is away from the body for either side).
local function swing(pitch: number, out: number, side: number, twist: number?): Pose.Limb
	local p, o = rad(pitch), rad(out) * side
	-- Start from "hanging" (0,-1,0): swing forward about the sideways axis, then out.
	local x = math.sin(o)
	local y = -math.cos(p) * math.cos(o)
	local z = -math.sin(p) * math.cos(o)
	return { aim = Pose.normalize({ x, y, z }), twist = twist or 0 }
end

Locomotion.swing = swing

-- Studs covered by one full gait cycle (a left and a right step) at this speed.
function Locomotion.cycleLength(speed: number): number
	return lerp(5.2, 8.6, smooth(speed / 28))
end

-- Relaxed standing: arms hang a little forward and out, knees soft.
function Locomotion.stance(): Pose.Pose
	return {
		armR = swing(4, 7, 1),
		armL = swing(4, 7, -1),
		elbowR = 10,
		elbowL = 10,
		legR = swing(0, 3.5, 1),
		legL = swing(0, 3.5, -1),
		kneeR = 3,
		kneeL = 3,
	}
end

-- Idle: breathing, a slow weight shift and a hint of life in the hands. `t` is seconds.
function Locomotion.idle(t: number): Pose.Pose
	local breathe = math.sin(t * 1.9)
	local sway = math.sin(t * 0.55)
	local lookSlow = math.sin(t * 0.37)
	return {
		hipPos = { sway * 0.015, breathe * 0.012 - 0.01, 0 },
		hipRot = { 0, sway * 1.2, sway * 1.4 },
		waist = { 1.2 + breathe * 0.9, -sway * 1.4, -sway * 0.8 },
		neck = { -0.8 - breathe * 0.6, lookSlow * 3, 0 },
		armR = swing(4 + breathe * 1.2, 7 + breathe * 1.2, 1),
		armL = swing(4 + breathe * 1.2, 7 + breathe * 1.2, -1),
		elbowR = 10 + breathe * 1.5,
		elbowL = 10 + breathe * 1.5,
		wristR = { 4, 0, 0 },
		wristL = { 4, 0, 0 },
		legR = swing(0, 3.5 + sway * 0.8, 1),
		legL = swing(0, 3.5 - sway * 0.8, -1),
		kneeR = 3 + sway * 0.8,
		kneeL = 3 - sway * 0.8,
	}
end

-- The gait pose at `speed` studs/second and cycle phase 0..1. Right leg is forward at 0.25.
function Locomotion.gait(speed: number, phase: number): Pose.Pose
	local walk = smooth(speed / 16)
	local sprint = smooth((speed - 16) / 10)

	local legSwing = lerp(lerp(8, 36, walk), 56, sprint)
	local armSwing = lerp(lerp(8, 30, walk), 52, sprint)
	local kneePeak = lerp(lerp(18, 58, walk), 96, sprint)
	local elbowBase = lerp(lerp(12, 34, walk), 88, sprint)
	local lean = lerp(lerp(0, 5, walk), 17, sprint)
	local bob = lerp(lerp(0.01, 0.1, walk), 0.2, sprint)
	local twistSwing = lerp(lerp(1, 5, walk), 11, sprint)

	local a = phase * TAU
	local right = math.sin(a) -- 1 when the right leg is furthest forward
	local left = -right

	-- Knees fold most as the leg swings through underneath the body.
	local function knee(leg: number, legDelta: number): number
		-- legDelta is the leg's forward-swing direction: positive while it swings forward.
		local through = math.max(0, legDelta) * (1 - math.abs(leg) * 0.55)
		local stance = 0.22 * math.max(0, -leg)
		return kneePeak * (through + stance) + 4
	end
	local rightDelta = math.cos(a) -- derivative of sin
	local leftDelta = -rightDelta

	-- Two vertical bounces per cycle, lowest as each foot takes weight.
	local bounce = -bob * (0.5 - 0.5 * math.cos(2 * a)) + bob * 0.5

	return {
		hipPos = { right * 0.03 * walk, bounce, 0 },
		hipRot = { 0, right * twistSwing, -right * 2.2 * walk },
		waist = { lean, -right * twistSwing * 1.35, right * 1.2 * walk },
		neck = { -lean * 0.65, right * twistSwing * 0.7, 0 },
		legR = swing(right * legSwing, 2.5, 1),
		legL = swing(left * legSwing, 2.5, -1),
		kneeR = knee(right, rightDelta),
		kneeL = knee(left, leftDelta),
		ankleR = { -right * 10 * walk, 0, 0 },
		ankleL = { -left * 10 * walk, 0, 0 },
		-- Arms counter-swing against the legs.
		armR = swing(-right * armSwing, 6 + sprint * 4, 1, right * 6),
		armL = swing(-left * armSwing, 6 + sprint * 4, -1, left * 6),
		elbowR = elbowBase + math.max(0, -right) * 14 * walk,
		elbowL = elbowBase + math.max(0, -left) * 14 * walk,
	}
end

-- Idle and gait cross-faded by speed, so a character easing to a stop settles into breathing.
-- `idle` is the hero's own idle style (Shared.Anim.Idles); the default is Locomotion.idle.
function Locomotion.ground(speed: number, phase: number, t: number, idle: ((number) -> Pose.Pose)?): Pose.Pose
	local idlePose = idle or Locomotion.idle
	local weight = smooth((speed - 0.4) / 3.2)
	if weight <= 0 then
		return idlePose(t)
	end
	local gait = Locomotion.gait(speed, phase)
	if weight >= 1 then
		return gait
	end
	return Pose.lerp(idlePose(t), gait, weight)
end

-- Airborne: rising tucks the legs and lifts the arms, falling spreads them. `vy` is vertical
-- speed in studs/second (positive up); `t` is seconds in the air.
function Locomotion.air(vy: number, t: number): Pose.Pose
	local rising = smooth((vy + 4) / 22)
	local flutter = math.sin(t * 9) * 2
	return {
		hipPos = { 0, 0, 0 },
		hipRot = { lerp(6, -4, rising), 0, 0 },
		waist = { lerp(8, -2, rising), 0, 0 },
		neck = { lerp(-6, 4, rising), 0, 0 },
		armR = swing(lerp(40, -50, rising), lerp(38, 22, rising), 1, 10),
		armL = swing(lerp(30, -35, rising), lerp(34, 16, rising), -1, 10),
		elbowR = lerp(24, 50, rising) + flutter,
		elbowL = lerp(30, 40, rising) - flutter,
		legR = swing(lerp(-6, 24, rising), 6, 1),
		legL = swing(lerp(18, -8, rising), 6, -1),
		kneeR = lerp(12, 62, rising),
		kneeL = lerp(46, 30, rising),
		ankleR = { 14, 0, 0 },
		ankleL = { 8, 0, 0 },
	}
end

-- Landing squash: `amount` 0..1 is how hard the landing was.
function Locomotion.land(amount: number): Pose.Pose
	local a = math.clamp(amount, 0, 1)
	return {
		hipPos = { 0, -0.55 * a, 0 },
		hipRot = { 10 * a, 0, 0 },
		waist = { 18 * a, 0, 0 },
		neck = { -10 * a, 0, 0 },
		armR = swing(30 * a, 22 + 14 * a, 1),
		armL = swing(30 * a, 22 + 14 * a, -1),
		elbowR = 24 * a,
		elbowL = 24 * a,
		legR = swing(32 * a, 9, 1),
		legL = swing(28 * a, 9, -1),
		kneeR = 62 * a,
		kneeL = 58 * a,
		ankleR = { -18 * a, 0, 0 },
		ankleL = { -18 * a, 0, 0 },
	}
end

-- Gliding: body pitched forward like a swimmer, arms swept wide, legs trailing. `bank` is a
-- lean into turns in -1..1 (positive turns right), `t` seconds for the flutter.
function Locomotion.glide(bank: number, t: number): Pose.Pose
	local flap = math.sin(t * 5.5)
	return {
		hipPos = { 0, -0.05, 0 },
		hipRot = { 62, 0, bank * 28 },
		waist = { -10 + flap * 2, 0, bank * 10 },
		neck = { -48, 0, -bank * 8 },
		armR = swing(-28, 78 + flap * 4, 1, 30),
		armL = swing(-28, 78 - flap * 4, -1, 30),
		elbowR = 8,
		elbowL = 8,
		legR = swing(-22 + flap * 3, 8 + bank * 6, 1),
		legL = swing(-16 - flap * 3, 8 - bank * 6, -1),
		kneeR = 14,
		kneeL = 20,
		ankleR = { 40, 0, 0 },
		ankleL = { 40, 0, 0 },
	}
end

-- Climbing a wall: hands and feet alternate up the face. `phase` advances with distance climbed;
-- `moving` is 0..1 and eases the reach to a hang when the climber stops.
function Locomotion.climb(phase: number, moving: number): Pose.Pose
	local a = phase * TAU
	local right = math.sin(a)
	local left = -right
	local m = math.clamp(moving, 0, 1)
	-- Arms reach up in turn; the reaching hand is higher and the other pulls down.
	local reachR = 112 + right * 34 * m
	local reachL = 112 + left * 34 * m
	return {
		hipPos = { 0, 0, 0.35 },
		hipRot = { 0, right * 4 * m, 0 },
		waist = { 6, -right * 6 * m, 0 },
		neck = { -22, 0, 0 },
		armR = swing(reachR, 20, 1, 10),
		armL = swing(reachL, 20, -1, 10),
		elbowR = 22 + math.max(0, -right) * 46 * m,
		elbowL = 22 + math.max(0, -left) * 46 * m,
		wristR = { -20, 0, 0 },
		wristL = { -20, 0, 0 },
		legR = swing(lerp(32, 52, (1 + right) / 2) * (0.4 + 0.6 * m) + 14, 14, 1),
		legL = swing(lerp(32, 52, (1 + left) / 2) * (0.4 + 0.6 * m) + 14, 14, -1),
		kneeR = 58 + math.max(0, right) * 26 * m,
		kneeL = 58 + math.max(0, left) * 26 * m,
		ankleR = { -30, 0, 0 },
		ankleL = { -30, 0, 0 },
	}
end

return Locomotion
