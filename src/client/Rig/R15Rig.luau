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

local JointMath = require(script.Parent.JointMath)
local RigTypes = require(script.Parent.Rig)

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

export type R15 = RigTypes.Rig & {
	root: BasePart,
	parts: { [string]: BasePart },
	joints: { Joint },
	pieces: { Piece },
}

local R15Rig = {}

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

local moveParts: { BasePart } = {}
local moveFrames: { CFrame } = {}

local function solve(rig: RigTypes.Rig, pose: Pose.Pose, rootCFrame: CFrame)
	local self = rig :: R15
	if self.destroyed then
		return
	end
	local frames = self.frames
	local poseAny: any = pose
	frames.HumanoidRootPart = rootCFrame

	for _, joint in self.joints do
		local parentFrame = frames[joint.parent]
		if parentFrame then
			local transform = JointMath.transform(joint.name, poseAny, self.motionScale)
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
	for name, part in self.parts do
		local frame = frames[name]
		if frame then
			count += 1
			moveParts[count] = part
			moveFrames[count] = frame
		end
	end
	for _, piece in self.pieces do
		local frame = frames[piece.part]
		if frame then
			count += 1
			moveParts[count] = piece.instance
			moveFrames[count] = frame * piece.offset
		end
	end
	Workspace:BulkMoveTo(moveParts, moveFrames, Enum.BulkMoveMode.FireCFrameChanged)
end

local function frameOf(rig: RigTypes.Rig, partName: string): CFrame
	return rig.frames[partName] or CFrame.identity
end

local function attach(rig: RigTypes.Rig, instance: BasePart, partName: string, offset: CFrame)
	local self = rig :: R15
	instance.Anchored = true
	instance.CanCollide = false
	instance.CanQuery = false
	instance.CanTouch = false
	instance.Massless = true
	instance.Parent = self.model
	table.insert(self.pieces, { instance = instance, part = partName, offset = offset })
end

local function detach(rig: RigTypes.Rig, instance: BasePart)
	local self = rig :: R15
	for index, piece in self.pieces do
		if piece.instance == instance then
			table.remove(self.pieces, index)
			break
		end
	end
end

local function destroy(rig: RigTypes.Rig)
	local self = rig :: R15
	if self.destroyed then
		return
	end
	self.destroyed = true
	self.model:Destroy()
	table.clear(self.pieces)
end

-- Builds a rig from a model made by Players:CreateHumanoidModelFromDescription (or a clone of
-- one). The model is consumed: it is stripped and becomes the rig's model.
function R15Rig.fromModel(source: Model): R15
	local parts: { [string]: BasePart } = {}
	local joints: { Joint } = {}
	local byName: { [string]: Joint } = {}

	local humanoid = source:FindFirstChildOfClass("Humanoid")
	local hipHeight = if humanoid then humanoid.HipHeight + 1 else 3

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
	for _, name in JointMath.Order do
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

	for _, descendant in source:GetDescendants() do
		if descendant:IsA("BasePart") then
			descendant.Anchored = true
			descendant.CanCollide = false
			descendant.CanQuery = false
			descendant.CanTouch = false
			descendant.Massless = true
		end
	end

	local rig: R15 = {
		kind = "r15",
		model = source,
		root = parts.HumanoidRootPart,
		parts = parts,
		joints = joints,
		frames = {},
		pieces = {},
		hipHeight = hipHeight,
		motionScale = hipHeight / 3,
		destroyed = false,
		solve = solve,
		frameOf = frameOf,
		attach = attach,
		detach = detach,
		destroy = destroy,
	}
	return rig
end

-- A rig built from a HumanoidDescription. Yields (network call), so call it from a task.
function R15Rig.fromDescription(description: HumanoidDescription): R15
	local model = game:GetService("Players")
		:CreateHumanoidModelFromDescription(description, Enum.HumanoidRigType.R15)
	return R15Rig.fromModel(model)
end

return R15Rig
