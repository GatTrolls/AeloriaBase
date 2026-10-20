--!strict
--[[
	MovementController

	Sprint, dodge, wall climb and glide on the player's own character. Movement plays instantly
	for feel; every stamina cost is asked for from MovementService, which can refuse or end it.

	  Dodge / sprint: tap Left Shift, B on a gamepad, or the dodge button to dodge; hold it to
	  sprint. Dodging while standing still steps backwards.
	  Climb: run into a wall. Jump leaps upward (costs stamina); dodge lets go.
	  Glide: jump again while falling from high enough. Jump again or land to stop.
]]

local ContextActionService = game:GetService("ContextActionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local StarterPlayer = game:GetService("StarterPlayer")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local CombatConfig = require(ReplicatedStorage.Shared.Config.CombatConfig)
local Net = require(ReplicatedStorage.Shared.Net)

local Movement = CombatConfig.Movement
local StaminaConfig = CombatConfig.Stamina
local player = Players.LocalPlayer

type Mode = "ground" | "climb" | "glide"

local MovementController = {}

local intentRemote: RemoteEvent
local stamina = StaminaConfig.Max
local mode: Mode = "ground"
local sprinting = false
local dodgeHeld = false
local dodgeHeldSince = 0
local lastDodgeAt = -math.huge
local dodgeUntil = 0
local pushingWallSince: number? = nil
local leapUntil = 0
local velocity: LinearVelocity? = nil
local orientation: AlignOrientation? = nil
local glider: BasePart? = nil
local listeners: { () -> () } = {}

local rayParams = RaycastParams.new()
rayParams.FilterType = Enum.RaycastFilterType.Exclude

local function parts(): (Model?, Humanoid?, BasePart?)
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	return character, humanoid, root
end

local function notify()
	for _, listener in listeners do
		task.spawn(listener)
	end
end

function MovementController.getStamina(): (number, number)
	return stamina, StaminaConfig.Max
end

function MovementController.getMode(): Mode
	return mode
end

function MovementController.onChanged(listener: () -> ())
	table.insert(listeners, listener)
end

function MovementController.isDodging(): boolean
	return os.clock() < dodgeUntil
end

-- One LinearVelocity and AlignOrientation per character, switched on only while a move needs them.
local function ensureMovers(root: BasePart)
	if velocity and velocity.Parent == root then
		return
	end
	local attachment = root:FindFirstChild("FarbornMoverAttachment") :: Attachment?
		or Instance.new("Attachment")
	attachment.Name = "FarbornMoverAttachment"
	attachment.Parent = root

	local lv = Instance.new("LinearVelocity")
	lv.Name = "FarbornVelocity"
	lv.Attachment0 = attachment
	lv.RelativeTo = Enum.ActuatorRelativeTo.World
	lv.MaxForce = math.huge
	lv.Enabled = false
	lv.Parent = root
	velocity = lv

	local ao = Instance.new("AlignOrientation")
	ao.Name = "FarbornOrientation"
	ao.Mode = Enum.OrientationAlignmentMode.OneAttachment
	ao.Attachment0 = attachment
	ao.RigidityEnabled = true
	ao.Enabled = false
	ao.Parent = root
	orientation = ao
end

local function setVelocityVector(value: Vector3)
	local lv = velocity :: LinearVelocity
	lv.VelocityConstraintMode = Enum.VelocityConstraintMode.Vector
	lv.VectorVelocity = value
	lv.Enabled = true
end

local function stopMovers()
	if velocity then
		velocity.Enabled = false
	end
	if orientation then
		orientation.Enabled = false
	end
end

local function setSprint(on: boolean)
	if sprinting == on then
		return
	end
	sprinting = on
	intentRemote:FireServer("sprint", on)
end

local function endClimb()
	if mode ~= "climb" then
		return
	end
	mode = "ground"
	stopMovers()
	local _, humanoid = parts()
	if humanoid then
		humanoid.PlatformStand = false
		humanoid:ChangeState(Enum.HumanoidStateType.Freefall)
	end
	intentRemote:FireServer("climb", false)
	notify()
end

local function endGlide()
	if mode ~= "glide" then
		return
	end
	mode = "ground"
	stopMovers()
	if glider then
		glider:Destroy()
		glider = nil
	end
	intentRemote:FireServer("glide", false)
	notify()
end

local function startClimb(normal: Vector3)
	local _, humanoid, root = parts()
	if not humanoid or not root or stamina <= 0 then
		return
	end
	setSprint(false)
	endGlide()
	ensureMovers(root)
	mode = "climb"
	humanoid.PlatformStand = true
	local ao = orientation :: AlignOrientation
	ao.CFrame = CFrame.lookAt(Vector3.zero, -normal)
	ao.Enabled = true
	setVelocityVector(Vector3.zero)
	intentRemote:FireServer("climb", true)
	notify()
end

local function startGlide()
	local character, humanoid, root = parts()
	if not character or not humanoid or not root or stamina <= 0 then
		return
	end
	ensureMovers(root)
	mode = "glide"
	-- A simple wing so the glide reads at a glance.
	local wing = Instance.new("Part")
	wing.Name = "Glider"
	wing.Size = Vector3.new(7, 0.15, 2.2)
	wing.Material = Enum.Material.Fabric
	wing.Color = Color3.fromRGB(240, 230, 210)
	wing.CanCollide = false
	wing.CanQuery = false
	wing.Massless = true
	wing.CFrame = root.CFrame * CFrame.new(0, 2.6, 0.4)
	local joint = Instance.new("WeldConstraint")
	joint.Part0 = root
	joint.Part1 = wing
	joint.Parent = wing
	wing.Parent = character
	glider = wing
	intentRemote:FireServer("glide", true)
	notify()
end

local function dodge()
	local _, humanoid, root = parts()
	if not humanoid or not root or humanoid.Health <= 0 then
		return
	end
	if mode == "climb" then
		endClimb()
		return
	end
	if mode == "glide" then
		return
	end
	local t = os.clock()
	if t - lastDodgeAt < Movement.DodgeCooldownSeconds or stamina < StaminaConfig.DodgeCost then
		return
	end
	lastDodgeAt = t
	dodgeUntil = t + Movement.DodgeSeconds
	ensureMovers(root)

	local direction = humanoid.MoveDirection * Vector3.new(1, 0, 1)
	if direction.Magnitude < 0.1 then
		direction = -root.CFrame.LookVector * Vector3.new(1, 0, 1)
	end
	direction = direction.Unit
	root.CFrame = CFrame.lookAt(
		root.Position,
		root.Position + (if humanoid.MoveDirection.Magnitude > 0.1 then direction else -direction)
	)

	local lv = velocity :: LinearVelocity
	lv.VelocityConstraintMode = Enum.VelocityConstraintMode.Plane
	lv.PrimaryTangentAxis = Vector3.xAxis
	lv.SecondaryTangentAxis = Vector3.zAxis
	lv.PlaneVelocity = Vector2.new(direction.X, direction.Z) * Movement.DodgeSpeed
	lv.Enabled = true

	-- Afterimage: a quick white flash that fades, so the dodge reads even without animation.
	local character = player.Character
	if character then
		local flash = Instance.new("Highlight")
		flash.FillColor = Color3.new(1, 1, 1)
		flash.FillTransparency = 0.4
		flash.OutlineTransparency = 1
		flash.Parent = character
		task.delay(Movement.DodgeInvulnerableSeconds, function()
			flash:Destroy()
		end)
	end

	stamina = math.max(0, stamina - StaminaConfig.DodgeCost)
	intentRemote:FireServer("dodge")
	notify()
	task.delay(Movement.DodgeSeconds, function()
		if
			mode == "ground"
			and velocity
			and velocity.VelocityConstraintMode == Enum.VelocityConstraintMode.Plane
		then
			velocity.Enabled = false
		end
	end)
end

-- Holding dodge longer than SprintHoldSeconds switches to sprinting.
function MovementController.setDodgeHeld(held: boolean)
	if held and not dodgeHeld then
		dodgeHeld = true
		dodgeHeldSince = os.clock()
		dodge()
	elseif not held and dodgeHeld then
		dodgeHeld = false
		setSprint(false)
	end
end

local controls: any = nil

-- The default control module turns keyboard, stick and thumbstick input into one vector. Depending
-- on the Roblox version it lives in PlayerScripts or in StarterPlayer; false means it was not found.
local function getControls(): any
	if controls == nil then
		local playerScripts = player:FindFirstChildOfClass("PlayerScripts")
		local module = (playerScripts and playerScripts:FindFirstChild("PlayerModule"))
			or StarterPlayer:FindFirstChild("PlayerModule")
		local ok, result = false, nil
		if module and module:IsA("ModuleScript") then
			ok, result = pcall(function()
				return (require :: any)(module):GetControls()
			end)
		end
		controls = if ok and result then result else false
	end
	return controls
end

-- Movement input relative to the player: X is right and Z is back, so forward is -Z, on every
-- device. Falls back to the Humanoid's world move direction as seen from the camera.
local function moveInput(humanoid: Humanoid): Vector3
	local active = getControls()
	if active then
		return active:GetMoveVector()
	end
	local camera = Workspace.CurrentCamera.CFrame
	local look = (camera.LookVector * Vector3.new(1, 0, 1)).Unit
	local world = humanoid.MoveDirection
	return Vector3.new(world:Dot(camera.RightVector), 0, -world:Dot(look))
end

local function climbStep(humanoid: Humanoid, root: BasePart)
	local character = player.Character :: Model
	rayParams.FilterDescendantsInstances = { character, Workspace:FindFirstChild("Enemies") :: Instance }
	local look = root.CFrame.LookVector
	local wall = Workspace:Raycast(root.Position, look * 3, rayParams)
	if not wall or math.abs(wall.Normal.Y) > 0.4 then
		-- Reached the top: hop up and over the ledge.
		endClimb()
		root.AssemblyLinearVelocity = Vector3.new(0, 30, 0) + look * 12
		return
	end

	local normal = wall.Normal
	local right = normal:Cross(Vector3.yAxis).Unit
	local up = right:Cross(normal).Unit
	local input = moveInput(humanoid)

	local ao = orientation :: AlignOrientation
	ao.CFrame = CFrame.lookAt(Vector3.zero, -normal)

	local move = (up * -input.Z - right * input.X) * Movement.ClimbSpeed
	if os.clock() < leapUntil then
		move = up * Movement.ClimbLeapSpeed
	end
	-- Hold the character a fixed distance from the wall.
	local gap = (root.Position - wall.Position):Dot(normal) - root.Size.Z / 2 - 0.35
	setVelocityVector(move - normal * gap * 8)

	if input.Z > 0.3 and humanoid.FloorMaterial ~= Enum.Material.Air then
		endClimb()
	end
end

local function groundStep(humanoid: Humanoid, root: BasePart)
	if sprinting and humanoid.MoveDirection.Magnitude < 0.1 then
		setSprint(false)
	end
	if
		dodgeHeld
		and not sprinting
		and os.clock() - dodgeHeldSince >= Movement.SprintHoldSeconds
		and humanoid.MoveDirection.Magnitude > 0.1
		and stamina > 0
	then
		setSprint(true)
	end

	-- Start climbing when running into a steep surface.
	local direction = humanoid.MoveDirection
	if direction.Magnitude < 0.5 or MovementController.isDodging() then
		pushingWallSince = nil
		return
	end
	rayParams.FilterDescendantsInstances =
		{ player.Character :: Model, Workspace:FindFirstChild("Enemies") :: Instance }
	local wall = Workspace:Raycast(root.Position, direction.Unit * 2.2, rayParams)
	local steep = wall and math.abs(wall.Normal.Y) < 0.3 and direction.Unit:Dot(-wall.Normal) > 0.7
	if not steep then
		pushingWallSince = nil
		return
	end
	local airborne = humanoid.FloorMaterial == Enum.Material.Air
	pushingWallSince = pushingWallSince or os.clock()
	if airborne or os.clock() - (pushingWallSince :: number) > 0.25 then
		pushingWallSince = nil
		startClimb((wall :: RaycastResult).Normal)
	end
end

local function glideStep(humanoid: Humanoid, root: BasePart)
	if humanoid.FloorMaterial ~= Enum.Material.Air then
		endGlide()
		return
	end
	local direction = humanoid.MoveDirection * Vector3.new(1, 0, 1)
	if direction.Magnitude < 0.1 then
		direction = root.CFrame.LookVector * Vector3.new(1, 0, 1) * 0.6
	end
	setVelocityVector(direction * Movement.GlideForwardSpeed - Vector3.new(0, Movement.GlideFallSpeed, 0))
end

local function heightAboveGround(root: BasePart): number
	rayParams.FilterDescendantsInstances = { player.Character :: Model }
	local hit = Workspace:Raycast(root.Position, Vector3.new(0, -200, 0), rayParams)
	return if hit then root.Position.Y - hit.Position.Y else math.huge
end

local lastJumpRequestAt = 0

local function onJumpRequest()
	local _, humanoid, root = parts()
	if not humanoid or not root then
		return
	end
	-- JumpRequest can fire several times for one press (holding the key, or a tap on mobile), and
	-- each one would toggle the glider.
	local t = os.clock()
	if t - lastJumpRequestAt < 0.25 then
		return
	end
	lastJumpRequestAt = t
	if mode == "climb" then
		if stamina >= StaminaConfig.ClimbLeapCost and os.clock() > leapUntil then
			leapUntil = os.clock() + 0.3
			stamina -= StaminaConfig.ClimbLeapCost
			intentRemote:FireServer("leap")
		end
		return
	end
	if mode == "glide" then
		endGlide()
		return
	end
	if humanoid.FloorMaterial == Enum.Material.Air and heightAboveGround(root) > Movement.GlideMinHeight then
		startGlide()
	end
end

local function onServerState(message: { [string]: any })
	if type(message.stamina) == "number" then
		stamina = message.stamina
	end
	if message.exhausted then
		setSprint(false)
		sprinting = false
		endClimb()
		endGlide()
	end
	local denied = message.denied
	if denied == "sprint" then
		sprinting = false
	elseif denied == "climb" then
		endClimb()
	elseif denied == "glide" then
		endGlide()
	end
	notify()
end

function MovementController:Init()
	intentRemote = Net.event(Net.Names.MoveIntent)
end

function MovementController:Start()
	Net.event(Net.Names.MoveState).OnClientEvent:Connect(onServerState)

	ContextActionService:BindAction("FarbornDodge", function(_, state)
		if state == Enum.UserInputState.Begin then
			MovementController.setDodgeHeld(true)
		elseif state == Enum.UserInputState.End or state == Enum.UserInputState.Cancel then
			MovementController.setDodgeHeld(false)
		end
		return Enum.ContextActionResult.Sink
	end, false, Enum.KeyCode.LeftShift, Enum.KeyCode.ButtonB)

	UserInputService.JumpRequest:Connect(onJumpRequest)

	player.CharacterAdded:Connect(function()
		mode = "ground"
		sprinting = false
		velocity = nil
		orientation = nil
		glider = nil
		notify()
	end)

	RunService.Heartbeat:Connect(function()
		local _, humanoid, root = parts()
		if not humanoid or not root or humanoid.Health <= 0 then
			return
		end
		if mode == "climb" then
			climbStep(humanoid, root)
		elseif mode == "glide" then
			glideStep(humanoid, root)
		else
			groundStep(humanoid, root)
		end
	end)
end

return MovementController
