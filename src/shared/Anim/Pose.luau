--!strict
--[[
	Pose

	A pose is a sparse table of joint channels for a standard 15-part humanoid (the Roblox R15
	layout). Anything a pose leaves out is at rest, so clips only list what moves. Poses are
	plain data, which keeps clips diffable, blendable and testable without Roblox.

	Conventions (character space, the way the character faces):
	  +x is the character's right, +y is up, -z is forward.

	Channels
	  hipPos            { x, y, z } studs. Moves the whole body off the root: a crouch is y < 0.
	  hipRot            { pitch, yaw, roll } degrees. Tilts the pelvis (and everything above it).
	  waist, neck       { pitch, yaw, roll } degrees. Pitch + leans forward (nose down), yaw + turns
	                    right, roll + leans right.
	  armR, armL        { aim = { x, y, z }, twist }. Where the upper arm points (it hangs at 0,-1,0)
	                    and how it rolls about its own length, in degrees. The same twist sign means
	                    the same movement on both arms.
	  legR, legL        the same for the upper legs.
	  elbowR, elbowL    degrees the forearm folds forward (0 straight).
	  kneeR, kneeL      degrees the shin folds back (0 straight).
	  wristR, wristL    { x, y, z } degrees, raw rotation about the joint's axes.
	  ankleR, ankleL    { x, y, z } degrees, raw rotation about the joint's axes.

	Pure Luau with no Roblox APIs; covered by tests/Anim.spec.luau.
]]

export type Vec3 = { number }
export type Limb = { aim: Vec3, twist: number? }

export type Pose = {
	hipPos: Vec3?,
	hipRot: Vec3?,
	waist: Vec3?,
	neck: Vec3?,
	armR: Limb?,
	armL: Limb?,
	elbowR: number?,
	elbowL: number?,
	wristR: Vec3?,
	wristL: Vec3?,
	legR: Limb?,
	legL: Limb?,
	kneeR: number?,
	kneeL: number?,
	ankleR: Vec3?,
	ankleL: Vec3?,
}

type Kind = "vec" | "limb" | "num" | "angles"

local Pose = {}

-- Every channel, in the order joints are solved.
Pose.channels = table.freeze({
	{ name = "hipPos", kind = "vec" :: Kind },
	{ name = "hipRot", kind = "angles" :: Kind },
	{ name = "waist", kind = "angles" :: Kind },
	{ name = "neck", kind = "angles" :: Kind },
	{ name = "armR", kind = "limb" :: Kind },
	{ name = "armL", kind = "limb" :: Kind },
	{ name = "elbowR", kind = "num" :: Kind },
	{ name = "elbowL", kind = "num" :: Kind },
	{ name = "wristR", kind = "angles" :: Kind },
	{ name = "wristL", kind = "angles" :: Kind },
	{ name = "legR", kind = "limb" :: Kind },
	{ name = "legL", kind = "limb" :: Kind },
	{ name = "kneeR", kind = "num" :: Kind },
	{ name = "kneeL", kind = "num" :: Kind },
	{ name = "ankleR", kind = "angles" :: Kind },
	{ name = "ankleL", kind = "angles" :: Kind },
})

-- Channels that move the arms, torso and head: the usual mask for an upper-body action.
Pose.upperBody = table.freeze({
	"waist",
	"neck",
	"armR",
	"armL",
	"elbowR",
	"elbowL",
	"wristR",
	"wristL",
})

local REST_AIM: Vec3 = { 0, -1, 0 }

local function restOf(kind: Kind): any
	if kind == "vec" or kind == "angles" then
		return { 0, 0, 0 }
	elseif kind == "limb" then
		return { aim = REST_AIM, twist = 0 }
	end
	return 0
end

local function normalize(v: Vec3): Vec3
	local x, y, z = v[1], v[2], v[3]
	local length = math.sqrt(x * x + y * y + z * z)
	if length < 1e-6 then
		return REST_AIM
	end
	return { x / length, y / length, z / length }
end

Pose.normalize = normalize

-- Spherical interpolation between two directions; falls back to a straight lerp when they are
-- nearly the same, and picks a sideways swing when they are exactly opposite.
local function slerp(a: Vec3, b: Vec3, t: number): Vec3
	local ax, ay, az = a[1], a[2], a[3]
	local bx, by, bz = b[1], b[2], b[3]
	local dot = math.clamp(ax * bx + ay * by + az * bz, -1, 1)
	if dot > 0.9995 then
		return normalize({ ax + (bx - ax) * t, ay + (by - ay) * t, az + (bz - az) * t })
	end
	if dot < -0.9995 then
		-- Opposite directions have no single shortest path: swing through the side.
		local mx, my, mz = 1, 0, 0
		if math.abs(ay) < 0.9 then
			-- a is not vertical, so a sideways axis perpendicular to it is well defined
			mx, my, mz = -az, 0, ax
		end
		local mid = normalize({ mx, my, mz })
		return if t < 0.5 then slerp(a, mid, t * 2) else slerp(mid, b, (t - 0.5) * 2)
	end
	local angle = math.acos(dot)
	local sinAngle = math.sin(angle)
	local wa = math.sin((1 - t) * angle) / sinAngle
	local wb = math.sin(t * angle) / sinAngle
	return { ax * wa + bx * wb, ay * wa + by * wb, az * wa + bz * wb }
end

Pose.slerp = slerp

local function lerpNumber(a: number, b: number, t: number): number
	return a + (b - a) * t
end

local function lerpVec(a: Vec3, b: Vec3, t: number): Vec3
	return { a[1] + (b[1] - a[1]) * t, a[2] + (b[2] - a[2]) * t, a[3] + (b[3] - a[3]) * t }
end

local function lerpLimb(a: Limb, b: Limb, t: number): Limb
	return {
		aim = slerp(a.aim, b.aim, t),
		twist = lerpNumber(a.twist or 0, b.twist or 0, t),
	}
end

local function mix(kind: Kind, a: any, b: any, t: number): any
	if kind == "vec" or kind == "angles" then
		return lerpVec(a, b, t)
	elseif kind == "limb" then
		return lerpLimb(a, b, t)
	end
	return lerpNumber(a, b, t)
end

-- Angle blend for layering: the difference is wrapped to the shortest way round, so a clip that
-- ends a full spin at -360 degrees fades out without unwinding.
local function wrapDelta(from: number, to: number): number
	local delta = (to - from) % 360
	if delta > 180 then
		delta -= 360
	end
	return delta
end

local function lerpAngles(a: Vec3, b: Vec3, t: number): Vec3
	return {
		a[1] + wrapDelta(a[1], b[1]) * t,
		a[2] + wrapDelta(a[2], b[2]) * t,
		a[3] + wrapDelta(a[3], b[3]) * t,
	}
end

-- A pose of the same channels with everything at rest, filled in. Handy as a blend base.
function Pose.rest(): Pose
	local pose: any = {}
	for _, channel in Pose.channels do
		pose[channel.name] = restOf(channel.kind)
	end
	return pose
end

function Pose.limb(x: number, y: number, z: number, twist: number?): Limb
	return { aim = normalize({ x, y, z }), twist = twist or 0 }
end

-- Blends a towards b by t. A channel only one pose mentions blends from or to rest.
function Pose.lerp(a: Pose, b: Pose, t: number): Pose
	local out: any = {}
	local pa: any, pb: any = a, b
	for _, channel in Pose.channels do
		local name = channel.name
		local va, vb = pa[name], pb[name]
		if va ~= nil or vb ~= nil then
			if va == nil then
				va = restOf(channel.kind)
			end
			if vb == nil then
				vb = restOf(channel.kind)
			end
			out[name] = mix(channel.kind, va, vb, t)
		end
	end
	return out
end

-- Layers `over` on top of `base` with the given weight, optionally limited to some channels.
-- Channels `over` doesn't mention keep the base value.
function Pose.layer(base: Pose, over: Pose, weight: number, mask: { string }?): Pose
	local allowed: { [string]: boolean }? = nil
	if mask then
		allowed = {}
		for _, name in mask do
			allowed[name] = true
		end
	end
	local out: any = {}
	local pb: any, po: any = base, over
	for _, channel in Pose.channels do
		local name = channel.name
		local vb, vo = pb[name], po[name]
		if vo ~= nil and (allowed == nil or allowed[name]) then
			local from = vb or restOf(channel.kind)
			if channel.kind == "angles" then
				out[name] = lerpAngles(from, vo, weight)
			else
				out[name] = mix(channel.kind, from, vo, weight)
			end
		else
			out[name] = vb
		end
	end
	return out
end

-- Adds a small offset pose on top (breathing, leaning into a turn, a look-at). Numbers and
-- vectors add; limbs add to the aim direction and twist.
function Pose.add(base: Pose, delta: Pose, weight: number): Pose
	local out: any = {}
	local pb: any, pd: any = base, delta
	for _, channel in Pose.channels do
		local name = channel.name
		local vb, vd = pb[name], pd[name]
		if vd == nil then
			out[name] = vb
		else
			local kind = channel.kind
			local start = vb or restOf(kind)
			if kind == "vec" or kind == "angles" then
				out[name] = {
					start[1] + vd[1] * weight,
					start[2] + vd[2] * weight,
					start[3] + vd[3] * weight,
				}
			elseif kind == "limb" then
				out[name] = {
					aim = normalize({
						start.aim[1] + vd.aim[1] * weight,
						start.aim[2] + vd.aim[2] * weight,
						start.aim[3] + vd.aim[3] * weight,
					}),
					twist = (start.twist or 0) + (vd.twist or 0) * weight,
				}
			else
				out[name] = start + vd * weight
			end
		end
	end
	return out
end

-- How far a pose is from rest, scaled: 0 is rest, 1 is the pose itself. Softens any clip.
function Pose.scaled(pose: Pose, amount: number): Pose
	local out: any = {}
	local source: any = pose
	for _, channel in Pose.channels do
		local value = source[channel.name]
		if value ~= nil then
			out[channel.name] = mix(channel.kind, restOf(channel.kind), value, amount)
		end
	end
	return out
end

local function mirrorVec(v: Vec3, signs: Vec3): Vec3
	return { v[1] * signs[1], v[2] * signs[2], v[3] * signs[3] }
end

local function mirrorLimb(limb: Limb): Limb
	return { aim = { -limb.aim[1], limb.aim[2], limb.aim[3] }, twist = limb.twist }
end

local SWAPS = {
	{ "armR", "armL" },
	{ "elbowR", "elbowL" },
	{ "wristR", "wristL" },
	{ "legR", "legL" },
	{ "kneeR", "kneeL" },
	{ "ankleR", "ankleL" },
}

-- The left-right mirror image of a pose: right and left swap, sideways motion and yaw flip.
-- Lets one authored swing serve as its backhand.
function Pose.mirror(pose: Pose): Pose
	local out: any = {}
	local source: any = pose
	if source.hipPos then
		out.hipPos = mirrorVec(source.hipPos, { -1, 1, 1 })
	end
	for _, name in { "hipRot", "waist", "neck" } do
		if source[name] then
			-- pitch stays; yaw and roll flip
			out[name] = mirrorVec(source[name], { 1, -1, -1 })
		end
	end
	for _, pair in SWAPS do
		local right, left = pair[1], pair[2]
		local kind = if string.sub(right, 1, 3) == "arm" or string.sub(right, 1, 3) == "leg"
			then "limb"
			else "other"
		for _, from in { { right, left }, { left, right } } do
			local value = source[from[1]]
			if value ~= nil then
				if kind == "limb" then
					out[from[2]] = mirrorLimb(value)
				elseif type(value) == "table" then
					out[from[2]] = mirrorVec(value, { 1, -1, -1 })
				else
					out[from[2]] = value
				end
			end
		end
	end
	return out
end

function Pose.copy(pose: Pose): Pose
	local out: any = {}
	local source: any = pose
	for _, channel in Pose.channels do
		local value = source[channel.name]
		if value ~= nil then
			out[channel.name] = mix(channel.kind, value, value, 0)
		end
	end
	return out
end

return Pose
