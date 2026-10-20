--!strict
--[[
	RigAnimator

	Turns "what this character is doing" into a pose every frame:

	  1. A base layer from locomotion: idle, gait that scales with speed, airborne, gliding,
	     climbing and so on (Shared.Anim.Locomotion).
	  2. Action layers on top: one-shot clips (attacks, abilities, dodges, hurt reactions) that fade
	     in and out and can be limited to some channels, such as the upper body while running.
	  3. Small procedural layers: leaning into acceleration, looking at a target.

	It owns no Roblox instances except through its rig. Controllers decide *what* plays; this
	module decides how it blends and moves.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Clip = require(ReplicatedStorage.Shared.Anim.Clip)
local Locomotion = require(ReplicatedStorage.Shared.Anim.Locomotion)
local Pose = require(ReplicatedStorage.Shared.Anim.Pose)

local R15Rig = require(script.Parent.R15Rig)

export type Locomotion = {
	-- "ground" | "air" | "glide" | "climb" | "plunge" | "frozen"
	state: string,
	-- Horizontal speed, studs/second.
	speed: number,
	-- Vertical speed, studs/second, positive up.
	vy: number,
	-- Lean into turns while gliding, -1..1.
	bank: number,
	-- Climb speed 0..1.
	climbing: number,
}

export type Action = {
	clip: Clip.Clip,
	time: number,
	speed: number,
	-- Channels the action drives; nil drives the whole body.
	mask: { string }?,
	fadeIn: number,
	fadeOut: number,
	-- 0..1 how strongly the action replaces the base layer at its peak.
	weight: number,
	onEvent: ((string) -> ())?,
	-- Total seconds to hold the final pose after the clip ends before fading out.
	hold: number,
	done: boolean,
	holdLeft: number,
	id: number,
}

export type Animator = {
	rig: R15Rig.Rig,
	t: number,
	phase: number,
	locomotion: Locomotion,
	actions: { Action },
	nextId: number,
	-- Procedural layers.
	lean: { number }, -- smoothed { forward, side } degrees
	look: { number }, -- smoothed { yaw, pitch } degrees
	lookTarget: Vector3?,
	lastRoot: CFrame?,
	lastVelocity: Vector3,
	pose: Pose.Pose,
	-- Called with the solved pose after every update (cloth, trails and weapons hook in here).
	onSolved: ((Animator) -> ())?,
}

local RigAnimator = {}

local function smoothStep(current: number, target: number, rate: number, dt: number): number
	return current + (target - current) * (1 - math.exp(-rate * dt))
end

function RigAnimator.new(rig: R15Rig.Rig): Animator
	return {
		rig = rig,
		t = 0,
		phase = 0,
		locomotion = { state = "ground", speed = 0, vy = 0, bank = 0, climbing = 0 },
		actions = {},
		nextId = 1,
		lean = { 0, 0 },
		look = { 0, 0 },
		lookTarget = nil,
		lastRoot = nil,
		lastVelocity = Vector3.zero,
		pose = {},
		onSolved = nil,
	}
end

function RigAnimator.setLocomotion(
	animator: Animator,
	state: string,
	speed: number,
	vy: number,
	extra: { bank: number?, climbing: number? }?
)
	local l = animator.locomotion
	l.state = state
	l.speed = speed
	l.vy = vy
	l.bank = if extra and extra.bank then extra.bank else 0
	l.climbing = if extra and extra.climbing then extra.climbing else 0
end

function RigAnimator.setLookTarget(animator: Animator, target: Vector3?)
	animator.lookTarget = target
end

export type PlayOptions = {
	speed: number?,
	mask: { string }?,
	fadeIn: number?,
	fadeOut: number?,
	weight: number?,
	hold: number?,
	onEvent: ((string) -> ())?,
	-- Start part-way through (a late join to someone else's attack).
	startAt: number?,
	-- Cancels other actions with this tag first (so attack 2 replaces attack 1's tail).
	replace: boolean?,
}

-- Starts a one-shot clip. Returns an id that stop() understands.
function RigAnimator.play(animator: Animator, clip: Clip.Clip, options: PlayOptions?): number
	local o = options or {}
	if o.replace ~= false then
		-- A new full-body action replaces older ones that share its mask kind; others blend out.
		for _, other in animator.actions do
			if (other.mask == nil) == (o.mask == nil) then
				other.done = true
				other.holdLeft = 0
				other.fadeOut = math.min(other.fadeOut, 0.08)
			end
		end
	end
	local id = animator.nextId
	animator.nextId += 1
	local action: Action = {
		clip = clip,
		time = o.startAt or 0,
		speed = o.speed or 1,
		mask = o.mask,
		fadeIn = o.fadeIn or 0.04,
		fadeOut = o.fadeOut or 0.12,
		weight = o.weight or 1,
		onEvent = o.onEvent,
		hold = o.hold or 0,
		done = false,
		holdLeft = o.hold or 0,
		id = id,
	}
	table.insert(animator.actions, action)
	return id
end

function RigAnimator.stop(animator: Animator, id: number?)
	for _, action in animator.actions do
		if id == nil or action.id == id then
			action.done = true
			action.holdLeft = 0
		end
	end
end

function RigAnimator.isPlaying(animator: Animator, id: number): boolean
	for _, action in animator.actions do
		if action.id == id and not action.done then
			return true
		end
	end
	return false
end

-- 0..1 weight of an action at its current time, from its fades.
local function actionWeight(action: Action): number
	local clip = action.clip
	local weight = action.weight
	if action.fadeIn > 0 then
		weight *= math.clamp(action.time / (action.fadeIn * action.speed), 0, 1)
	end
	local remaining = clip.length - action.time
	if action.done then
		-- Fading out after a stop or when finished: tracked through holdLeft going negative.
		local out = -action.holdLeft
		weight *= math.clamp(1 - out / math.max(action.fadeOut, 0.001), 0, 1)
	elseif action.fadeOut > 0 and not clip.loop and action.holdLeft <= 0 then
		weight *= math.clamp(remaining / (action.fadeOut * action.speed), 0, 1)
	end
	return weight
end

local function basePose(animator: Animator): Pose.Pose
	local l = animator.locomotion
	local state = l.state
	if state == "air" then
		return Locomotion.air(l.vy, animator.t)
	elseif state == "glide" then
		return Locomotion.glide(l.bank, animator.t)
	elseif state == "climb" then
		return Locomotion.climb(animator.phase, l.climbing)
	elseif state == "plunge" then
		return Locomotion.air(-60, animator.t)
	end
	return Locomotion.ground(l.speed, animator.phase, animator.t)
end

-- Advances time and the gait, blends every layer, solves the rig at `rootCFrame`.
function RigAnimator.update(animator: Animator, dt: number, rootCFrame: CFrame)
	animator.t += dt
	local l = animator.locomotion

	-- Gait phase advances by distance, so feet keep pace with the ground.
	if l.state == "ground" and l.speed > 0.4 then
		animator.phase = (animator.phase + dt * l.speed / Locomotion.cycleLength(l.speed)) % 1
	elseif l.state == "climb" then
		animator.phase = (animator.phase + dt * (0.4 + l.climbing * 1.1)) % 1
	elseif l.state == "ground" then
		-- Ease the cycle to a standstill rather than freezing mid-stride.
		animator.phase += (math.round(animator.phase * 2) / 2 - animator.phase) * math.min(1, dt * 6)
	end

	local pose = basePose(animator)

	-- Acceleration lean: the body tilts into speed changes (world velocity delta in root space).
	local velocity = Vector3.zero
	if animator.lastRoot then
		velocity = (rootCFrame.Position - animator.lastRoot.Position) / math.max(dt, 1e-3)
	end
	local accel = (velocity - animator.lastVelocity) / math.max(dt, 1e-3)
	animator.lastVelocity = velocity
	animator.lastRoot = rootCFrame
	local localAccel = rootCFrame:VectorToObjectSpace(accel)
	local leanForward = math.clamp(-localAccel.Z * 0.12, -9, 9)
	local leanSide = math.clamp(localAccel.X * 0.1, -8, 8)
	animator.lean[1] = smoothStep(animator.lean[1], if l.state == "ground" then leanForward else 0, 8, dt)
	animator.lean[2] = smoothStep(animator.lean[2], if l.state == "ground" then leanSide else 0, 8, dt)

	-- Action layers, oldest first so newer ones win.
	for index = #animator.actions, 1, -1 do
		local action = animator.actions[index]
		local previous = action.time
		action.time += dt * action.speed
		if action.onEvent then
			for _, event in
				Clip.eventsBetween(action.clip, previous, math.min(action.time, action.clip.length + 1e-4))
			do
				action.onEvent(event.name)
			end
		end
		if not action.done and not action.clip.loop and action.time >= action.clip.length then
			if action.holdLeft > 0 then
				action.holdLeft -= dt
				action.time = action.clip.length
			else
				action.done = true
				action.holdLeft = 0
			end
		end
		if action.done then
			action.holdLeft -= dt
			if -action.holdLeft >= action.fadeOut then
				table.remove(animator.actions, index)
			end
		end
	end
	for _, action in animator.actions do
		local weight = actionWeight(action)
		if weight > 0 then
			local sample = Clip.sample(action.clip, math.min(action.time, action.clip.length))
			pose = Pose.layer(pose, sample, weight, action.mask)
		end
	end

	-- Procedural layers.
	local additive: Pose.Pose = {
		waist = { animator.lean[1], 0, animator.lean[2] },
	}
	pose = Pose.add(pose, additive, 1)

	if animator.lookTarget then
		local toTarget = rootCFrame:PointToObjectSpace(animator.lookTarget)
		local yaw = math.deg(math.atan2(toTarget.X, -toTarget.Z))
		local pitch =
			math.deg(math.atan2(-toTarget.Y, math.max(0.1, Vector3.new(toTarget.X, 0, toTarget.Z).Magnitude)))
		animator.look[1] = smoothStep(animator.look[1], math.clamp(yaw, -55, 55), 9, dt)
		animator.look[2] = smoothStep(animator.look[2], math.clamp(pitch, -25, 25), 9, dt)
	else
		animator.look[1] = smoothStep(animator.look[1], 0, 6, dt)
		animator.look[2] = smoothStep(animator.look[2], 0, 6, dt)
	end
	pose = Pose.add(pose, { neck = { animator.look[2], animator.look[1], 0 } }, 1)

	animator.pose = pose
	R15Rig.solve(animator.rig, pose, rootCFrame)
	if animator.onSolved then
		animator.onSolved(animator)
	end
end

function RigAnimator.destroy(animator: Animator)
	R15Rig.destroy(animator.rig)
	table.clear(animator.actions)
end

return RigAnimator
