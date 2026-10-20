--!strict
--[[
	Effects

	Client-only combat visuals built from parts and UI, so the slice needs no uploaded assets:
	slashes, projectiles, area bursts, streaks, gravity wells, falling stars, lasting zones,
	lightning, hit sparks, damage and heal numbers, reaction labels, telegraph shockwaves,
	procedural arm swings, hit-stop and the Slip slow-motion tint. Everything here is cosmetic and is cleaned up
	automatically.
]]

local Debris = game:GetService("Debris")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local ElementStyle = require(ReplicatedStorage.Shared.Config.ElementStyle)
local Registry = require(script.Parent.Rig.Registry)

local Effects = {}

local container: Folder? = nil

local function folder(): Folder
	if container and container.Parent then
		return container
	end
	local created = Instance.new("Folder")
	created.Name = "ClientEffects"
	created.Parent = Workspace
	container = created
	return created
end

local function rgb(values: { number }): Color3
	return Color3.fromRGB(values[1], values[2], values[3])
end

function Effects.elementColor(element: string?): Color3
	local values = element and ElementStyle.Elements[element]
	return rgb(values or ElementStyle.Physical)
end

local function effectPart(size: Vector3, cframe: CFrame, color: Color3, transparency: number?): Part
	local p = Instance.new("Part")
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.Material = Enum.Material.Neon
	p.Color = color
	p.Size = size
	p.CFrame = cframe
	p.Transparency = transparency or 0
	p.Parent = folder()
	return p
end

local function fadeOut(p: BasePart, seconds: number, goal: { [string]: any }?)
	local properties: { [string]: any } = goal or {}
	properties.Transparency = 1
	TweenService
		:Create(p, TweenInfo.new(seconds, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), properties)
		:Play()
	Debris:AddItem(p, seconds + 0.05)
end

-- A blade arc sweeping across `arc` degrees in front of the attacker.
function Effects.slash(
	origin: Vector3,
	forward: Vector3,
	range: number,
	arc: number,
	color: Color3,
	heavy: boolean?
)
	local base = CFrame.lookAt(origin, origin + forward)
	local direction = if math.random() < 0.5 then 1 else -1
	local half = math.rad(arc / 2)
	local blade = effectPart(
		Vector3.new(0.25, if heavy then 0.5 else 0.3, range),
		base * CFrame.Angles(0, half * direction, 0) * CFrame.new(0, 0, -range / 2),
		color,
		0.15
	)
	local goal = base * CFrame.Angles(0, -half * direction, 0) * CFrame.new(0, 0, -range / 2)
	TweenService:Create(blade, TweenInfo.new(0.12, Enum.EasingStyle.Quad), { CFrame = goal }):Play()
	task.delay(0.08, function()
		fadeOut(blade, 0.15)
	end)
end

-- A glowing orb that flies forward, for catalyst attacks.
function Effects.bolt(origin: Vector3, forward: Vector3, range: number, color: Color3)
	local orb = effectPart(Vector3.new(0.9, 0.9, 0.9), CFrame.new(origin + forward * 1.5), color)
	orb.Shape = Enum.PartType.Ball
	TweenService:Create(orb, TweenInfo.new(0.16, Enum.EasingStyle.Linear), {
		CFrame = CFrame.new(origin + forward * range),
	}):Play()
	task.delay(0.16, function()
		fadeOut(orb, 0.12, { Size = Vector3.new(2.4, 2.4, 2.4) })
	end)
end

-- An expanding ring on the ground plus a column of light, for skills and bursts.
function Effects.area(center: Vector3, radius: number, color: Color3, big: boolean?)
	local ground = center - Vector3.new(0, 2.6, 0)
	local ring =
		effectPart(Vector3.new(0.2, 1, 1), CFrame.new(ground) * CFrame.Angles(0, 0, math.rad(90)), color, 0.2)
	ring.Shape = Enum.PartType.Cylinder
	fadeOut(ring, if big then 0.55 else 0.35, { Size = Vector3.new(0.2, radius * 2, radius * 2) })

	local height = if big then 30 else 14
	local width = radius * 0.5
	local column = effectPart(
		Vector3.new(height, width, width),
		CFrame.new(ground + Vector3.new(0, height / 2, 0)) * CFrame.Angles(0, 0, math.rad(90)),
		color,
		0.35
	)
	column.Shape = Enum.PartType.Cylinder
	fadeOut(column, if big then 0.6 else 0.35, { Size = Vector3.new(height, radius * 1.2, radius * 1.2) })
end

function Effects.spark(position: Vector3, color: Color3, big: boolean?)
	local size = if big then 2.6 else 1.6
	local ball = effectPart(Vector3.new(0.5, 0.5, 0.5), CFrame.new(position), color, 0.1)
	ball.Shape = Enum.PartType.Ball
	fadeOut(ball, 0.18, { Size = Vector3.new(size, size, size) })
end

-- A floating label that drifts up and fades. Used for damage numbers and reaction names.
function Effects.popup(position: Vector3, text: string, color: Color3, scale: number?)
	local anchor = Instance.new("Attachment")
	anchor.WorldPosition = position
		+ Vector3.new((math.random() - 0.5) * 2, 3 + math.random(), (math.random() - 0.5) * 2)
	anchor.Parent = Workspace.Terrain

	local size = 34 * (scale or 1)
	local gui = Instance.new("BillboardGui")
	gui.Size = UDim2.fromOffset(size * 5, size)
	gui.AlwaysOnTop = true
	gui.LightInfluence = 0
	gui.MaxDistance = 140
	gui.Adornee = anchor
	gui.Parent = anchor

	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Size = UDim2.fromScale(1, 1)
	label.Font = Enum.Font.GothamBlack
	label.TextScaled = true
	label.Text = text
	label.TextColor3 = color
	label.TextStrokeTransparency = 0.2
	label.TextStrokeColor3 = Color3.new(0, 0, 0)
	label.Parent = gui

	TweenService:Create(gui, TweenInfo.new(0.8, Enum.EasingStyle.Quad), {
		StudsOffsetWorldSpace = Vector3.new(0, 2.5, 0),
	}):Play()
	task.delay(0.45, function()
		TweenService:Create(label, TweenInfo.new(0.35), { TextTransparency = 1, TextStrokeTransparency = 1 })
			:Play()
	end)
	Debris:AddItem(anchor, 0.85)
end

function Effects.damageNumber(position: Vector3, amount: number, element: string?, crit: boolean)
	local text = tostring(math.floor(amount))
	Effects.popup(
		position,
		if crit then text .. "!" else text,
		Effects.elementColor(element),
		if crit then 1.35 else 1
	)
end

function Effects.reaction(position: Vector3, reactionId: string)
	local style = ElementStyle.Reactions[reactionId]
	if style then
		Effects.popup(position + Vector3.new(0, 1.5, 0), style.label, rgb(style.color), 1.25)
	end
end

-- A shockwave ring where an enemy strike landed.
function Effects.shockwave(position: Vector3, radius: number, color: Color3?)
	local ground = position - Vector3.new(0, 2.7, 0)
	local ring = effectPart(
		Vector3.new(0.25, 1, 1),
		CFrame.new(ground) * CFrame.Angles(0, 0, math.rad(90)),
		color or Color3.fromRGB(255, 90, 60),
		0.3
	)
	ring.Shape = Enum.PartType.Cylinder
	fadeOut(ring, 0.3, { Size = Vector3.new(0.25, radius * 2, radius * 2) })
end

-- Procedural arm swings. Joints (Motor6D or AnimationConstraint) are re-posed by the Animator
-- every frame, so the swing is layered on top of the animated pose in PreSimulation, after the
-- Animator has run. The offset applied last frame is removed first if the Animator left the
-- joint alone, so offsets never pile up.
type Swing = {
	joint: any,
	startedAt: number,
	duration: number,
	heavy: boolean,
	lastSet: CFrame?,
	lastOffset: CFrame?,
}
local swings: { [Instance]: Swing } = {}
local swingConnection: RBXScriptConnection? = nil

local function lerp(a: number, b: number, t: number): number
	return a + (b - a) * t
end

-- Wind up, swing through, settle back. Returns the shoulder rotation for progress 0..1.
local function swingOffset(progress: number, heavy: boolean): CFrame
	local raise = math.rad(if heavy then 150 else 110)
	local follow = math.rad(-35)
	local pitch, roll
	if progress < 0.3 then
		local t = progress / 0.3
		pitch, roll = lerp(0, raise, t), lerp(0, math.rad(-20), t)
	elseif progress < 0.6 then
		local t = (progress - 0.3) / 0.3
		pitch, roll = lerp(raise, follow, t), lerp(math.rad(-20), math.rad(25), t)
	else
		local t = (progress - 0.6) / 0.4
		pitch, roll = lerp(follow, 0, t), lerp(math.rad(25), 0, t)
	end
	return CFrame.Angles(pitch, 0, roll)
end

local function stepSwings()
	local now = os.clock()
	for joint, swing in swings do
		if not joint.Parent then
			swings[joint] = nil
			continue
		end
		local current: CFrame = swing.joint.Transform
		local base = current
		if swing.lastSet and swing.lastOffset and current == swing.lastSet then
			base = current * swing.lastOffset:Inverse()
		end
		local progress = (now - swing.startedAt) / swing.duration
		if progress >= 1 then
			swing.joint.Transform = base
			swings[joint] = nil
			continue
		end
		local offset = swingOffset(progress, swing.heavy)
		local nextTransform = base * offset
		swing.joint.Transform = nextTransform
		swing.lastSet = nextTransform
		swing.lastOffset = offset
	end
	if next(swings) == nil and swingConnection then
		swingConnection:Disconnect()
		swingConnection = nil
	end
end

function Effects.swingArm(character: Model, heavy: boolean?)
	local upperArm = character:FindFirstChild("RightUpperArm")
	local joint = if upperArm
		then upperArm:FindFirstChild("RightShoulder")
		else (
			character:FindFirstChild("Torso")
			and (character:FindFirstChild("Torso") :: Instance):FindFirstChild("Right Shoulder")
		)
	if not joint or not (joint:IsA("Motor6D") or joint:IsA("AnimationConstraint")) then
		return
	end
	swings[joint] = {
		joint = joint,
		startedAt = os.clock(),
		duration = if heavy then 0.45 else 0.32,
		heavy = heavy == true,
		lastSet = nil,
		lastOffset = nil,
	}
	if not swingConnection then
		swingConnection = RunService.PreSimulation:Connect(stepSwings)
	end
end

-- Freezes the character's animations for a moment, which is what makes a hit feel solid.
function Effects.hitStop(character: Model, seconds: number)
	local entry = Registry.get(character)
	if entry then
		entry.freeze(seconds)
	end
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	local animator = humanoid and humanoid:FindFirstChildOfClass("Animator")
	if not animator then
		return
	end
	local tracks = animator:GetPlayingAnimationTracks()
	for _, track in tracks do
		track:AdjustSpeed(0)
	end
	task.delay(seconds, function()
		for _, track in tracks do
			track:AdjustSpeed(1)
		end
	end)
end

function Effects.flash(character: Model, color: Color3, seconds: number)
	local highlight = Instance.new("Highlight")
	highlight.FillColor = color
	highlight.OutlineColor = color
	highlight.FillTransparency = 0.5
	highlight.Parent = Registry.visualModel(character)
	TweenService:Create(highlight, TweenInfo.new(seconds), { FillTransparency = 1, OutlineTransparency = 1 })
		:Play()
	Debris:AddItem(highlight, seconds + 0.05)
end

-- A bright streak between two points: dashes and lines.
function Effects.streak(from: Vector3, to: Vector3, color: Color3, width: number?)
	local length = (to - from).Magnitude
	if length < 0.1 then
		return
	end
	local thickness = width or 1
	local beam = effectPart(
		Vector3.new(thickness, thickness * 0.4, length),
		CFrame.lookAt((from + to) / 2, to),
		color,
		0.2
	)
	fadeOut(beam, 0.3, { Size = Vector3.new(0.1, 0.05, length) })
end

-- A ring that shrinks into its centre: pulls and gravity wells.
function Effects.implode(center: Vector3, radius: number, color: Color3)
	local ground = center - Vector3.new(0, 2.6, 0)
	local ring = effectPart(
		Vector3.new(0.2, radius * 2, radius * 2),
		CFrame.new(ground) * CFrame.Angles(0, 0, math.rad(90)),
		color,
		0.35
	)
	ring.Shape = Enum.PartType.Cylinder
	fadeOut(ring, 0.35, { Size = Vector3.new(0.2, 0.5, 0.5) })
	local core = effectPart(Vector3.new(1, 1, 1), CFrame.new(center), color, 0.1)
	core.Shape = Enum.PartType.Ball
	fadeOut(core, 0.45, { Size = Vector3.new(3, 3, 3) })
end

-- A star that falls from above and bursts where it lands.
function Effects.fallingStar(point: Vector3, radius: number, color: Color3)
	local star = effectPart(Vector3.new(1.2, 1.2, 1.2), CFrame.new(point + Vector3.new(4, 26, -2)), color)
	star.Shape = Enum.PartType.Ball
	local fall =
		TweenService:Create(star, TweenInfo.new(0.22, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
			CFrame = CFrame.new(point),
		})
	fall:Play()
	fall.Completed:Connect(function()
		star:Destroy()
		Effects.area(point, radius, color, false)
	end)
	Debris:AddItem(star, 1)
end

-- A lasting disc on the ground: healing pools, molten glass, frozen constellations.
function Effects.zone(center: Vector3, radius: number, seconds: number, color: Color3)
	local ground = center - Vector3.new(0, 2.65, 0)
	local disc = effectPart(
		Vector3.new(0.15, radius * 2, radius * 2),
		CFrame.new(ground) * CFrame.Angles(0, 0, math.rad(90)),
		color,
		0.6
	)
	disc.Shape = Enum.PartType.Cylinder
	disc.Material = Enum.Material.ForceField
	task.delay(math.max(0, seconds - 0.4), function()
		fadeOut(disc, 0.4)
	end)
	Debris:AddItem(disc, seconds + 0.5)
end

function Effects.healNumber(position: Vector3, amount: number)
	Effects.popup(position, "+" .. tostring(math.floor(amount)), Color3.fromRGB(120, 235, 140), 1)
end

-- A jagged bolt between two points: Conduct.
function Effects.lightning(from: Vector3, to: Vector3, color: Color3)
	local points = { from }
	local segments = 4
	for index = 1, segments - 1 do
		local t = index / segments
		local jitter = Vector3.new(math.random() - 0.5, math.random() - 0.5, math.random() - 0.5) * 2
		table.insert(points, from:Lerp(to, t) + jitter)
	end
	table.insert(points, to)
	for index = 1, #points - 1 do
		Effects.streak(points[index], points[index + 1], color, 0.35)
	end
end

-- A short slow-motion tint for the player who landed a Slip.
function Effects.timeSlow(seconds: number)
	local lighting = game:GetService("Lighting")
	local tint = Instance.new("ColorCorrectionEffect")
	tint.Name = "SlipTint"
	tint.Saturation = -0.6
	tint.TintColor = Color3.fromRGB(215, 230, 255)
	tint.Parent = lighting
	TweenService:Create(tint, TweenInfo.new(seconds, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
		Saturation = 0,
		TintColor = Color3.new(1, 1, 1),
	}):Play()
	Debris:AddItem(tint, seconds + 0.1)
end

return Effects
