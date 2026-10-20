--!strict
--[[
	JointMath

	Turns a Shared.Anim.Pose into one rotation per joint of the standard 15-part humanoid, in
	the joint's own frame (the R15 layout: each joint's axes are aligned with the character at
	rest). Both rig backends consume these: R15Rig applies them to body parts, SkinRig to the
	bones of a skinned mesh, so every clip works on every kind of character.

	Joint names follow R15: Root, Waist, Neck, RightShoulder, RightElbow, RightWrist,
	LeftShoulder, LeftElbow, LeftWrist, RightHip, RightKnee, RightAnkle, LeftHip, LeftKnee,
	LeftAnkle. Root also carries the body offset (hipPos).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Pose = require(ReplicatedStorage.Shared.Anim.Pose)

local JointMath = {}

-- Joint solve order: parents before children.
JointMath.Order = table.freeze({
	"Root",
	"Waist",
	"Neck",
	"RightShoulder",
	"RightElbow",
	"RightWrist",
	"LeftShoulder",
	"LeftElbow",
	"LeftWrist",
	"RightHip",
	"RightKnee",
	"RightAnkle",
	"LeftHip",
	"LeftKnee",
	"LeftAnkle",
})

-- The body part each joint moves (its child), and that part's parent joint's part.
JointMath.Child = table.freeze({
	Root = "LowerTorso",
	Waist = "UpperTorso",
	Neck = "Head",
	RightShoulder = "RightUpperArm",
	RightElbow = "RightLowerArm",
	RightWrist = "RightHand",
	LeftShoulder = "LeftUpperArm",
	LeftElbow = "LeftLowerArm",
	LeftWrist = "LeftHand",
	RightHip = "RightUpperLeg",
	RightKnee = "RightLowerLeg",
	RightAnkle = "RightFoot",
	LeftHip = "LeftUpperLeg",
	LeftKnee = "LeftLowerLeg",
	LeftAnkle = "LeftFoot",
})

JointMath.Parent = table.freeze({
	Root = "HumanoidRootPart",
	Waist = "LowerTorso",
	Neck = "UpperTorso",
	RightShoulder = "UpperTorso",
	RightElbow = "RightUpperArm",
	RightWrist = "RightLowerArm",
	LeftShoulder = "UpperTorso",
	LeftElbow = "LeftUpperArm",
	LeftWrist = "LeftLowerArm",
	RightHip = "LowerTorso",
	RightKnee = "RightUpperLeg",
	RightAnkle = "RightLowerLeg",
	LeftHip = "LowerTorso",
	LeftKnee = "LeftUpperLeg",
	LeftAnkle = "LeftLowerLeg",
})

local REST_AIM = Vector3.new(0, -1, 0)

-- Rotation that turns a hanging limb (pointing down) to point along `direction`.
local function aimRotation(direction: Vector3): CFrame
	local unit = if direction.Magnitude > 1e-4 then direction.Unit else REST_AIM
	local dot = REST_AIM:Dot(unit)
	if dot > 0.99999 then
		return CFrame.identity
	elseif dot < -0.99999 then
		return CFrame.Angles(math.pi, 0, 0)
	end
	local axis = REST_AIM:Cross(unit)
	return CFrame.fromAxisAngle(axis.Unit, math.acos(math.clamp(dot, -1, 1)))
end

local function vec(v: { number }): Vector3
	return Vector3.new(v[1], v[2], v[3])
end

-- Body-turn rotation from {pitch, yaw, roll} degrees (see Shared.Anim.Pose conventions).
local function bodyRotation(v: { number }): CFrame
	return CFrame.Angles(0, math.rad(-v[2]), 0)
		* CFrame.Angles(math.rad(-v[1]), 0, 0)
		* CFrame.Angles(0, 0, math.rad(-v[3]))
end

local function limbTransform(limb: Pose.Limb, side: number): CFrame
	local twist = math.rad((limb.twist or 0) * side)
	return aimRotation(vec(limb.aim)) * CFrame.Angles(0, twist, 0)
end

local function rawRotation(v: { number }): CFrame
	return CFrame.Angles(math.rad(v[1]), math.rad(v[2]), math.rad(v[3]))
end

-- The transform of one joint for a pose, or nil when the pose leaves it at rest. `scale` stretches
-- the body offset for characters whose hips are higher or lower than the clip's nominal 3 studs.
function JointMath.transform(joint: string, pose: any, scale: number?): CFrame?
	if joint == "Root" then
		local pos, rot = pose.hipPos, pose.hipRot
		if pos == nil and rot == nil then
			return nil
		end
		local cf = if pos then CFrame.new(vec(pos) * (scale or 1)) else CFrame.identity
		return if rot then cf * bodyRotation(rot) else cf
	elseif joint == "Waist" then
		return pose.waist and bodyRotation(pose.waist)
	elseif joint == "Neck" then
		return pose.neck and bodyRotation(pose.neck)
	elseif joint == "RightShoulder" then
		return pose.armR and limbTransform(pose.armR, 1)
	elseif joint == "LeftShoulder" then
		return pose.armL and limbTransform(pose.armL, -1)
	elseif joint == "RightElbow" then
		return pose.elbowR and CFrame.Angles(math.rad(pose.elbowR), 0, 0)
	elseif joint == "LeftElbow" then
		return pose.elbowL and CFrame.Angles(math.rad(pose.elbowL), 0, 0)
	elseif joint == "RightWrist" then
		return pose.wristR and rawRotation(pose.wristR)
	elseif joint == "LeftWrist" then
		return pose.wristL and rawRotation(pose.wristL)
	elseif joint == "RightHip" then
		return pose.legR and limbTransform(pose.legR, 1)
	elseif joint == "LeftHip" then
		return pose.legL and limbTransform(pose.legL, -1)
	elseif joint == "RightKnee" then
		return pose.kneeR and CFrame.Angles(math.rad(-pose.kneeR), 0, 0)
	elseif joint == "LeftKnee" then
		return pose.kneeL and CFrame.Angles(math.rad(-pose.kneeL), 0, 0)
	elseif joint == "RightAnkle" then
		return pose.ankleR and rawRotation(pose.ankleR)
	elseif joint == "LeftAnkle" then
		return pose.ankleL and rawRotation(pose.ankleL)
	end
	return nil
end

return JointMath
