--!strict
--[[
	Rig

	The one interface the animation layer talks to. A rig is something that can be posed: a body
	made of parts (R15Rig) or a skinned mesh with bones (SkinRig). The animator hands it a
	Shared.Anim.Pose and a root CFrame every frame and it moves itself; everything else it offers
	is for attaching things to it (weapons, effects) and cleaning up.
]]

local Pose = require(game:GetService("ReplicatedStorage").Shared.Anim.Pose)

export type Rig = {
	kind: string,
	model: Model,
	-- Height of the hips above the soles, in studs.
	hipHeight: number,
	-- How far clip motion is stretched: this rig's hip height over the clips' nominal 3 studs.
	motionScale: number,
	-- Last solved world CFrame per body part name (R15 names: Head, RightHand ...).
	frames: { [string]: CFrame },
	destroyed: boolean,
	-- Poses the rig with the root at rootCFrame.
	solve: (rig: Rig, pose: Pose.Pose, rootCFrame: CFrame) -> (),
	-- World CFrame of a named body part (a bone for skinned rigs) from the last solve.
	frameOf: (rig: Rig, partName: string) -> CFrame,
	-- Keeps a rigid piece (weapon, accessory, glow) following a body part at an offset.
	attach: (rig: Rig, instance: BasePart, partName: string, offset: CFrame) -> (),
	detach: (rig: Rig, instance: BasePart) -> (),
	destroy: (rig: Rig) -> (),
}

return {}
