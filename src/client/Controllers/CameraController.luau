--!strict
--[[
	CameraController

	Third-person over-the-shoulder camera with lock-on, owned entirely by this controller
	(CameraType Scriptable) so lock-on can blend in and out without snapping.

	  * Mouse: the cursor is locked to the centre and mouse movement turns the camera. Hold Left
	    Alt (or open a menu) to free the cursor.
	  * Gamepad: right stick turns, R3 toggles lock-on.
	  * Touch: drag on the right side of the screen to turn, pinch to zoom.
	  * Lock-on: T, middle mouse or R3 picks the enemy closest to the centre of view.

	The camera pulls in when a wall is between it and the character.
]]

local CollectionService = game:GetService("CollectionService")
local ContextActionService = game:GetService("ContextActionService")
local GuiService = game:GetService("GuiService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local CombatConfig = require(ReplicatedStorage.Shared.Config.CombatConfig)

local Config = CombatConfig.Camera
local player = Players.LocalPlayer

local CameraController = {}

local yaw = 0
local pitch = math.rad(-12)
local distance = Config.Distance
local focus: Vector3? = nil
local gamepadLook = Vector2.zero
local cursorFree = false
local lockTarget: Model? = nil
local shakeAmount = 0
local touchLookInput: InputObject? = nil
local reticle: BillboardGui? = nil

local rayParams = RaycastParams.new()
rayParams.FilterType = Enum.RaycastFilterType.Exclude

local function rootOf(model: Model?): BasePart?
	return model and model:FindFirstChild("HumanoidRootPart") :: BasePart?
end

local function isValidTarget(model: Model?): boolean
	if not model or not model.Parent or not CollectionService:HasTag(model, "Enemy") then
		return false
	end
	local health = model:GetAttribute("Health")
	return type(health) == "number" and health > 0
end

local function rotation(): CFrame
	return CFrame.Angles(0, yaw, 0) * CFrame.Angles(pitch, 0, 0)
end

-- The flat direction the player is aiming: at the locked target, or where the camera looks.
function CameraController.getAimDirection(): Vector3
	local character = player.Character
	local root = rootOf(character)
	local target = rootOf(lockTarget)
	if root and target and isValidTarget(lockTarget) then
		local offset = (target.Position - root.Position) * Vector3.new(1, 0, 1)
		if offset.Magnitude > 0.1 then
			return offset.Unit
		end
	end
	local look = rotation().LookVector * Vector3.new(1, 0, 1)
	return if look.Magnitude > 0.01 then look.Unit else Vector3.new(0, 0, -1)
end

function CameraController.getLockTarget(): Model?
	return if isValidTarget(lockTarget) then lockTarget else nil
end

function CameraController.shake(amount: number)
	shakeAmount = math.max(shakeAmount, amount)
end

local function setReticle(target: Model?)
	if reticle then
		reticle:Destroy()
		reticle = nil
	end
	local root = rootOf(target)
	if not root then
		return
	end
	local gui = Instance.new("BillboardGui")
	gui.Name = "LockOnReticle"
	gui.Size = UDim2.fromOffset(34, 34)
	gui.AlwaysOnTop = true
	gui.Adornee = root
	local mark = Instance.new("TextLabel")
	mark.BackgroundTransparency = 1
	mark.Size = UDim2.fromScale(1, 1)
	mark.Text = "◇"
	mark.TextScaled = true
	mark.TextColor3 = Color3.fromRGB(255, 235, 170)
	mark.Font = Enum.Font.GothamBold
	mark.Parent = gui
	gui.Parent = player:WaitForChild("PlayerGui")
	reticle = gui
end

function CameraController.toggleLockOn()
	if lockTarget then
		lockTarget = nil
		setReticle(nil)
		return
	end
	local root = rootOf(player.Character)
	if not root then
		return
	end
	local look = rotation().LookVector
	local best, bestScore = nil, math.huge
	for _, model in CollectionService:GetTagged("Enemy") do
		local enemyRoot = rootOf(model)
		if enemyRoot and isValidTarget(model) then
			local offset = enemyRoot.Position - root.Position
			local d = offset.Magnitude
			if d <= Config.LockOnRange then
				local angle = math.acos(math.clamp(look:Dot(offset.Unit), -1, 1))
				local score = angle * 30 + d
				if score < bestScore then
					best, bestScore = model, score
				end
			end
		end
	end
	lockTarget = best
	setReticle(best)
end

local function update(dt: number)
	local camera = Workspace.CurrentCamera
	camera.CameraType = Enum.CameraType.Scriptable

	local mouseLocked = not cursorFree and not GuiService.MenuIsOpen and UserInputService.KeyboardEnabled
	UserInputService.MouseBehavior = if mouseLocked
		then Enum.MouseBehavior.LockCenter
		else Enum.MouseBehavior.Default
	UserInputService.MouseIconEnabled = not mouseLocked

	if mouseLocked then
		local delta = UserInputService:GetMouseDelta()
		yaw -= delta.X * Config.MouseSensitivity
		pitch -= delta.Y * Config.MouseSensitivity
	end
	if gamepadLook.Magnitude > 0.15 then
		local speed = math.rad(Config.GamepadDegreesPerSecond) * dt
		yaw -= gamepadLook.X * speed
		pitch += gamepadLook.Y * speed * 0.7
	end

	local character = player.Character
	local root = rootOf(character)
	if not root then
		return
	end

	if lockTarget and not isValidTarget(lockTarget) then
		lockTarget = nil
		setReticle(nil)
	end
	local targetRoot = rootOf(lockTarget)
	if targetRoot then
		local offset = targetRoot.Position - root.Position
		if offset.Magnitude > Config.LockOnRange * 1.4 then
			lockTarget = nil
			setReticle(nil)
		else
			local desiredYaw = math.atan2(-offset.X, -offset.Z)
			local diff = (desiredYaw - yaw + math.pi) % (2 * math.pi) - math.pi
			local alpha = 1 - math.exp(-Config.LockOnTurnSpeed * dt)
			yaw += diff * alpha
			pitch += (math.rad(-14) - pitch) * alpha
		end
	end

	pitch = math.clamp(pitch, math.rad(Config.MinPitchDegrees), math.rad(Config.MaxPitchDegrees))

	local desiredFocus = root.Position + Vector3.new(0, Config.FocusHeight, 0)
	local current = focus or desiredFocus
	if (desiredFocus - current).Magnitude > 30 then
		current = desiredFocus
	end
	focus = current:Lerp(desiredFocus, 1 - math.exp(-18 * dt))

	local rot = rotation()
	local pivot = (focus :: Vector3) + rot.RightVector * Config.ShoulderOffsetX
	local wanted = pivot + rot.LookVector * -distance

	rayParams.FilterDescendantsInstances =
		{ character :: Instance, Workspace:FindFirstChild("Enemies") :: Instance }
	local hit = Workspace:Raycast(pivot, wanted - pivot, rayParams)
	local cameraPosition = if hit then hit.Position + (pivot - wanted).Unit * 0.6 else wanted

	if shakeAmount > 0.01 then
		cameraPosition += Vector3.new(math.random() - 0.5, math.random() - 0.5, math.random() - 0.5) * shakeAmount
		shakeAmount *= math.exp(-14 * dt)
	end

	camera.CFrame = CFrame.lookAt(cameraPosition, cameraPosition + rot.LookVector)
	camera.Focus = CFrame.new(focus :: Vector3)
end

function CameraController:Start()
	local camera = Workspace.CurrentCamera
	yaw = select(2, camera.CFrame:ToEulerAnglesYXZ())

	ContextActionService:BindAction("FarbornLockOn", function(_, state)
		if state == Enum.UserInputState.Begin then
			CameraController.toggleLockOn()
		end
		return Enum.ContextActionResult.Sink
	end, false, Enum.KeyCode.T, Enum.UserInputType.MouseButton3, Enum.KeyCode.ButtonR3)

	ContextActionService:BindAction("FarbornFreeCursor", function(_, state)
		cursorFree = state == Enum.UserInputState.Begin
		return Enum.ContextActionResult.Pass
	end, false, Enum.KeyCode.LeftAlt)

	UserInputService.InputChanged:Connect(function(input, processed)
		if input.KeyCode == Enum.KeyCode.Thumbstick2 then
			gamepadLook = Vector2.new(input.Position.X, input.Position.Y)
		elseif input.UserInputType == Enum.UserInputType.MouseWheel and not processed then
			distance = math.clamp(distance - input.Position.Z * 1.5, Config.MinDistance, Config.MaxDistance)
		elseif input == touchLookInput then
			yaw -= input.Delta.X * Config.TouchSensitivity
			pitch -= input.Delta.Y * Config.TouchSensitivity
		end
	end)

	-- Touches that start on the right of the screen, away from any button, turn the camera.
	UserInputService.TouchStarted:Connect(function(input, processed)
		if processed or touchLookInput then
			return
		end
		if input.Position.X > Workspace.CurrentCamera.ViewportSize.X * 0.4 then
			touchLookInput = input
		end
	end)
	UserInputService.TouchEnded:Connect(function(input)
		if input == touchLookInput then
			touchLookInput = nil
		end
	end)
	local pinchStartDistance = distance
	UserInputService.TouchPinch:Connect(function(_, scale, _, state, processed)
		if processed then
			return
		end
		if state == Enum.UserInputState.Begin then
			pinchStartDistance = distance
		elseif state == Enum.UserInputState.Change then
			distance =
				math.clamp(pinchStartDistance / math.max(scale, 0.05), Config.MinDistance, Config.MaxDistance)
		end
	end)

	local function faceCharacter(character: Model)
		focus = nil
		lockTarget = nil
		setReticle(nil)
		local root = character:WaitForChild("HumanoidRootPart", 5) :: BasePart?
		if root then
			local look = root.CFrame.LookVector
			yaw = math.atan2(-look.X, -look.Z)
			pitch = math.rad(-12)
		end
	end
	player.CharacterAdded:Connect(faceCharacter)
	if player.Character then
		task.spawn(faceCharacter, player.Character)
	end

	RunService:BindToRenderStep("FarbornCamera", Enum.RenderPriority.Camera.Value + 1, update)
end

return CameraController
