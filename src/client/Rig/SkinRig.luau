--!strict
--[[
	SkinRig

	Poses a skinned character mesh (a MeshPart with Bones) with the same Shared.Anim poses that
	drive R15Rig, so every clip, gait and combat animation works on both kinds of character.

	The skeleton can be built any way (an auto-rig, a Blender rig): all that is needed is a map
	from its bone names to the 15 R15 parts. Two things are remembered per mapped bone:

	  * F, its rest orientation relative to the character's axes (+x right, +y up, -z forward). A
	    joint rotation Q expressed in character axes becomes the bone's Transform by conjugation,
	    F^-1 * Q * F, which is what makes the bone swing the way the pose says whatever axes its
	    creator gave it.
	  * L, how far a limb leans from hanging straight down at rest. Poses describe limbs in the R15
	    layout (arms and legs hang straight), but auto-rigs are usually built in an A-pose. A joint
	    rotation becomes L_parent * Q * L^-1, so the identity pose straightens the limbs and every
	    clip lands where it does on an R15 body.

	Unmapped bones (fingers, hair, skirts) follow their parents.

	The mesh is moved with the character: its hip bone sits at the root CFrame, so poses and
	clips line up exactly as they do on an R15 body.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Pose = require(ReplicatedStorage.Shared.Anim.Pose)

local JointMath = require(script.Parent.JointMath)
local RigTypes = require(script.Parent.Rig)

type Mapped = {
	bone: Bone,
	-- Bone rest rotation relative to the character axes, and its inverse.
	f: CFrame,
	finv: CFrame,
	-- Rotation that leans a hanging limb into this bone's rest direction, and its inverse.
	lean: CFrame,
	leanInverse: CFrame,
	-- The lean of the bone this one hangs from (identity for the hips, torso, head).
	parentLean: CFrame,
}

type Piece = {
	instance: BasePart,
	part: string,
	offset: CFrame,
}

export type Skin = RigTypes.Rig & {
	mesh: MeshPart,
	mapped: { [string]: Mapped }, -- by R15 part name
	-- Mesh-space rotation of the character axes, and the CFrame that seats the hip bone at the root.
	charRotation: CFrame,
	seat: CFrame,
	pieces: { Piece },
}

export type Options = {
	-- bone name -> R15 part name (LowerTorso, UpperTorso, Head, LeftUpperArm ...)
	map: { [string]: string },
	-- Name of the skinned MeshPart; defaults to the first one with bones.
	meshName: string?,
}

local SkinRig = {}

-- Limb bones lean towards the bone they lead to; hands follow their forearm, feet stay flat.
local LEADS_TO = {
	LeftUpperArm = "LeftLowerArm",
	LeftLowerArm = "LeftHand",
	RightUpperArm = "RightLowerArm",
	RightLowerArm = "RightHand",
	LeftUpperLeg = "LeftLowerLeg",
	LeftLowerLeg = "LeftFoot",
	RightUpperLeg = "RightLowerLeg",
	RightLowerLeg = "RightFoot",
}
local FOLLOWS_LEAN = {
	LeftHand = "LeftLowerArm",
	RightHand = "RightLowerArm",
}

-- Which body part each part hangs from, to find the parent's lean.
local PARENT_PART = {}
for joint, part in JointMath.Child do
	local parentJointPart = JointMath.Parent[joint]
	PARENT_PART[part] = parentJointPart
end

local DOWN = Vector3.new(0, -1, 0)

local function leanRotation(direction: Vector3): CFrame
	if direction.Magnitude < 1e-4 then
		return CFrame.identity
	end
	local unit = direction.Unit
	local dot = DOWN:Dot(unit)
	if dot > 0.99999 then
		return CFrame.identity
	elseif dot < -0.99999 then
		return CFrame.Angles(math.pi, 0, 0)
	end
	return CFrame.fromAxisAngle(DOWN:Cross(unit).Unit, math.acos(math.clamp(dot, -1, 1)))
end

local function boneWorldRest(mesh: MeshPart, bone: Bone): CFrame
	-- Bone.WorldCFrame is the bone's resting pose in world space, relative to the mesh part.
	return mesh.CFrame:ToObjectSpace(bone.WorldCFrame)
end

local moveParts: { BasePart } = {}
local moveFrames: { CFrame } = {}

local function partFrame(self: Skin, partName: string): CFrame?
	local entry = self.mapped[partName]
	if not entry then
		return nil
	end
	return entry.bone.TransformedWorldCFrame * entry.finv * entry.lean
end

local function solve(rig: RigTypes.Rig, pose: Pose.Pose, rootCFrame: CFrame)
	local self = rig :: Skin
	if self.destroyed then
		return
	end
	local poseAny: any = pose
	-- Seat the mesh: the hip bone's rest position lands on the root.
	local meshCFrame = rootCFrame * self.seat
	self.frames.HumanoidRootPart = rootCFrame

	for _, joint in JointMath.Order do
		local partName = JointMath.Child[joint]
		local entry = self.mapped[partName]
		if entry then
			local q = JointMath.transform(joint, poseAny, self.motionScale) or CFrame.identity
			entry.bone.Transform = entry.finv * entry.parentLean * q * entry.leanInverse * entry.f
		end
	end

	self.mesh.CFrame = meshCFrame
	if #self.pieces == 0 then
		return
	end
	-- Pieces ride on the posed bones, so the mesh has to be in place first.
	table.clear(moveParts)
	table.clear(moveFrames)
	local count = 0
	for _, piece in self.pieces do
		local frame = self.frames[piece.part]
		if self.mapped[piece.part] then
			frame = partFrame(self, piece.part)
			self.frames[piece.part] = frame
		end
		if frame then
			count += 1
			moveParts[count] = piece.instance
			moveFrames[count] = frame * piece.offset
		end
	end
	if count > 0 then
		Workspace:BulkMoveTo(moveParts, moveFrames, Enum.BulkMoveMode.FireCFrameChanged)
	end
end

local function frameOf(rig: RigTypes.Rig, partName: string): CFrame
	local self = rig :: Skin
	return partFrame(self, partName) or rig.frames[partName] or CFrame.identity
end

local function attach(rig: RigTypes.Rig, instance: BasePart, partName: string, offset: CFrame)
	local self = rig :: Skin
	instance.Anchored = true
	instance.CanCollide = false
	instance.CanQuery = false
	instance.CanTouch = false
	instance.Massless = true
	instance.Parent = self.model
	table.insert(self.pieces, { instance = instance, part = partName, offset = offset })
end

local function detach(rig: RigTypes.Rig, instance: BasePart)
	local self = rig :: Skin
	for index, piece in self.pieces do
		if piece.instance == instance then
			table.remove(self.pieces, index)
			break
		end
	end
end

local function destroy(rig: RigTypes.Rig)
	local self = rig :: Skin
	if self.destroyed then
		return
	end
	self.destroyed = true
	self.model:Destroy()
	table.clear(self.pieces)
end

-- Builds a rig from a model holding one skinned MeshPart. The model becomes the rig's model.
function SkinRig.fromModel(model: Model, options: Options): Skin
	local mesh: MeshPart? = nil
	for _, descendant in model:GetDescendants() do
		if
			descendant:IsA("MeshPart") and (options.meshName == nil or descendant.Name == options.meshName)
		then
			if descendant:FindFirstChildWhichIsA("Bone", true) then
				mesh = descendant
				break
			end
		end
	end
	assert(mesh, "SkinRig: no skinned MeshPart (a MeshPart with Bones) in the model")
	local skinned = mesh :: MeshPart
	skinned.Anchored = true
	skinned.CanCollide = false
	skinned.CanQuery = false
	skinned.CanTouch = false
	skinned.Massless = true

	local byPart: { [string]: Bone } = {}
	for _, descendant in skinned:GetDescendants() do
		if descendant:IsA("Bone") then
			local part = options.map[descendant.Name]
			if part then
				byPart[part] = descendant
			end
		end
	end
	for _, needed in { "LowerTorso", "UpperTorso", "Head", "LeftUpperArm", "RightUpperArm" } do
		assert(byPart[needed], `SkinRig: no bone is mapped to {needed}`)
	end

	-- Character axes in mesh space, from where the skeleton's own landmarks are.
	local rest: { [string]: CFrame } = {}
	for part, bone in byPart do
		rest[part] = boneWorldRest(skinned, bone)
	end
	local right = (rest.RightUpperArm.Position - rest.LeftUpperArm.Position)
	right = Vector3.new(right.X, 0, right.Z).Unit
	local upGuess = rest.Head.Position - rest.LowerTorso.Position
	local back = right:Cross(upGuess.Unit).Unit
	local up = back:Cross(right).Unit
	local charRotation = CFrame.fromMatrix(Vector3.zero, right, up, back)
	local charInverse = charRotation:Inverse()

	-- How far each limb leans from straight down, in character axes.
	local leans: { [string]: CFrame } = {}
	for part, leadsTo in LEADS_TO do
		if rest[part] and rest[leadsTo] then
			local direction = charInverse * (rest[leadsTo].Position - rest[part].Position)
			leans[part] = leanRotation(direction)
		end
	end
	for part, source in FOLLOWS_LEAN do
		leans[part] = leans[source]
	end

	local mapped: { [string]: Mapped } = {}
	for part, bone in byPart do
		local f = (charInverse * rest[part]).Rotation
		local lean = leans[part] or CFrame.identity
		local parentPart = PARENT_PART[part]
		local parentLean = if parentPart then (leans[parentPart] or CFrame.identity) else CFrame.identity
		mapped[part] = {
			bone = bone,
			f = f,
			finv = f:Inverse(),
			lean = lean,
			leanInverse = lean:Inverse(),
			parentLean = parentLean,
		}
	end

	local hipPosition = rest.LowerTorso.Position
	local bottom = -skinned.Size.Y / 2
	local hipHeight = hipPosition.Y - bottom
	-- seat: mesh local point q -> root-relative character coordinates R^-1 (q - hips).
	local seat = charInverse * CFrame.new(-hipPosition)

	local rig: Skin = {
		kind = "skin",
		model = model,
		mesh = skinned,
		mapped = mapped,
		charRotation = charRotation,
		seat = seat,
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

return SkinRig
