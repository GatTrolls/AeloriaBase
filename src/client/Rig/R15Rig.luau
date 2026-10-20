--!strict
--[[
	R15Rig

	A visual-only 15-part humanoid that we pose ourselves. The body comes from a
	HumanoidDescription (so scales and colours are Roblox's own), then everything that would
	fight our animation is stripped: the Humanoid, its Animator, scripts and physics joints.
	What's left is the parts and the joint layout, which we solve by forward kinematics every
	frame from a Shared.Anim.Pose:

	    child.CFrame = parent.CFrame * C0 * Transform * C1:Inverse()

	Parts are anchored and moved together with BulkMoveTo, so a rig costs one engine call per
	frame and behaves the same in Studio's edit mode, in play and for other players' characters.

	Extra pieces (hair, capes, armour, weapons) are rigid parts that follow a body part at a
	fixed offset; see attach().
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Pose = require(ReplicatedStorage.Shared.Anim.Pose)

type Joint = {
	name: string,
	parent: string,
	child: string,
	c0: CFrame,
	c1Inverse: CFrame,
}

type Piece = {
	instance: BasePart,
	part: string,
	offset: CFrame,
}

export type Rig = {
	model: Model,
	root: BasePart,
	parts: { [string]: BasePart },
	joints: { Joint },
	-- Last solved world CFrame per body part, for attachments and effects.
	frames: { [string]: CFrame },
	pieces: { Piece },
	-- Height of the soles under the root's centre, from the source Humanoid's HipHeight.
	hipHeight: number,
	destroyed: boolean,
}

local R15Rig = {}

-- Joint solve order: parents before children.
local ORDER = {
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
}

local REST_AIM = Vector3.new(0, -1, 0)

-- Rotation that turns a hanging limb (pointing down) to point along `direction`.
local function aimRotation(direction: Vector3): CFrame
	local unit = direction.Magnitude > 1e-4 and direction.Unit or REST_AIM
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

-- Joint transform for the pose; nil means the joint stays at rest.
local function transformFor(joint: string, pose: any): CFrame?
	if joint == "Root" then
		local pos, rot = pose.hipPos, pose.hipRot
		if pos == nil and rot == nil then
			return nil
		end
		local cf = if pos then CFrame.new(vec(pos)) else CFrame.identity
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

local STRIP_CLASSES = {
	"Humanoid",
	"Animator",
	"LocalScript",
	"Script",
	"AnimationConstraint",
	"BallSocketConstraint",
	"HingeConstraint",
	"NoCollisionConstraint",
	"Motor6D",
	"Animation",
	"NumberValue",
	"StringValue",
	"Vector3Value",
	"BindableFunction",
	"Status",
	"HumanoidDescription",
	"WrapTarget",
	"WrapLayer",
	"FaceControls",
	"BodyColors",
	"CharacterMesh",
}

-- Builds a rig from a model made by Players:CreateHumanoidModelFromDescription (or a clone of
-- one). The model is consumed: it is stripped and re-parented under the returned rig.
function R15Rig.fromModel(source: Model): Rig
	local parts: { [string]: BasePart } = {}
	local joints: { Joint } = {}
	local byName: { [string]: Joint } = {}

	local humanoid = source:FindFirstChildOfClass("Humanoid")
	local hipHeight = if humanoid then humanoid.HipHeight else 2

	for _, descendant in source:GetDescendants() do
		if descendant:IsA("AnimationConstraint") then
			local a0, a1 = descendant.Attachment0, descendant.Attachment1
			if a0 and a1 and a0.Parent and a1.Parent then
				byName[descendant.Name] = {
					name = descendant.Name,
					parent = a0.Parent.Name,
					child = a1.Parent.Name,
					c0 = a0.CFrame,
					c1Inverse = a1.CFrame:Inverse(),
				}
			end
		elseif descendant:IsA("Motor6D") then
			if descendant.Part0 and descendant.Part1 then
				byName[descendant.Name] = {
					name = descendant.Name,
					parent = descendant.Part0.Name,
					child = descendant.Part1.Name,
					c0 = descendant.C0,
					c1Inverse = descendant.C1:Inverse(),
				}
			end
		end
	end
	for _, name in ORDER do
		local joint = byName[name]
		if joint then
			table.insert(joints, joint)
		end
	end

	for _, child in source:GetChildren() do
		if child:IsA("BasePart") then
			parts[child.Name] = child
		end
	end

	-- Strip everything that isn't a part, an attachment or a decal/appearance.
	for _, descendant in source:GetDescendants() do
		for _, className in STRIP_CLASSES do
			if descendant:IsA(className) then
				descendant:Destroy()
				break
			end
		end
	end

	local all: { BasePart } = {}
	for _, descendant in source:GetDescendants() do
		if descendant:IsA("BasePart") then
			descendant.Anchored = true
			descendant.CanCollide = false
			descendant.CanQuery = false
			descendant.CanTouch = false
			descendant.Massless = true
			table.insert(all, descendant)
		end
	end

	local root = parts.HumanoidRootPart
	local rig: Rig = {
		model = source,
		root = root,
		parts = parts,
		joints = joints,
		frames = {},
		pieces = {},
		hipHeight = hipHeight,
		destroyed = false,
	}
	return rig
end

-- A rig built from a HumanoidDescription. Yields (network call), so call it from a task.
function R15Rig.fromDescription(description: HumanoidDescription): Rig
	local model = game:GetService("Players")
		:CreateHumanoidModelFromDescription(description, Enum.HumanoidRigType.R15)
	return R15Rig.fromModel(model)
end

-- Makes a rigid piece follow a body part. `offset` is relative to that part's CFrame.
function R15Rig.attach(rig: Rig, instance: BasePart, partName: string, offset: CFrame)
	instance.Anchored = true
	instance.CanCollide = false
	instance.CanQuery = false
	instance.CanTouch = false
	instance.Massless = true
	instance.Parent = rig.model
	table.insert(rig.pieces, { instance = instance, part = partName, offset = offset })
end

function R15Rig.detach(rig: Rig, instance: BasePart)
	for index, piece in rig.pieces do
		if piece.instance == instance then
			table.remove(rig.pieces, index)
			break
		end
	end
end

local moveParts: { BasePart } = {}
local moveFrames: { CFrame } = {}

-- Solves the pose for a root placed at `rootCFrame` and moves every part and piece.
function R15Rig.solve(rig: Rig, pose: Pose.Pose, rootCFrame: CFrame)
	if rig.destroyed then
		return
	end
	local frames = rig.frames
	local poseAny: any = pose
	frames.HumanoidRootPart = rootCFrame

	for _, joint in rig.joints do
		local parentFrame = frames[joint.parent]
		if parentFrame then
			local transform = transformFor(joint.name, poseAny)
			local frame = parentFrame * joint.c0
			if transform then
				frame = frame * transform
			end
			frames[joint.child] = frame * joint.c1Inverse
		end
	end

	table.clear(moveParts)
	table.clear(moveFrames)
	local count = 0
	for name, part in rig.parts do
		local frame = frames[name]
		if frame then
			count += 1
			moveParts[count] = part
			moveFrames[count] = frame
		end
	end
	for _, piece in rig.pieces do
		local frame = frames[piece.part]
		if frame then
			count += 1
			moveParts[count] = piece.instance
			moveFrames[count] = frame * piece.offset
		end
	end
	Workspace:BulkMoveTo(moveParts, moveFrames, Enum.BulkMoveMode.FireCFrameChanged)
end

-- World CFrame of a body part from the last solve (identity before the first).
function R15Rig.frameOf(rig: Rig, partName: string): CFrame
	return rig.frames[partName] or CFrame.identity
end

function R15Rig.setParent(rig: Rig, parent: Instance?)
	rig.model.Parent = parent
end

function R15Rig.destroy(rig: Rig)
	if rig.destroyed then
		return
	end
	rig.destroyed = true
	rig.model:Destroy()
	table.clear(rig.pieces)
end

return R15Rig
