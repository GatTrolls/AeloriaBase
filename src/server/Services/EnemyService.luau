--!strict
--[[
	EnemyService

	Spawns enemies at the arena's "EnemySpawn" markers and runs them. Decisions come from
	Shared.Combat.EnemyBrain; this service turns them into movement, telegraphs and strikes.

	  * Every wind-up shows a telegraph on the ground for its full duration.
	  * Only CombatConfig.Combat.MaxEnemyAttackers enemies may wind up at once, so a group takes
	    turns instead of swinging together.
	  * Players who are inside a dodge's invulnerability window when a strike lands evade it.
	  * Brains run at 15 Hz in one loop for all enemies; Humanoid movement does the rest.

	Enemy HP, aura and state are published as attributes on the model for the client UI.
]]

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage.Shared
local CombatConfig = require(Shared.Config.CombatConfig)
local Damage = require(Shared.Damage)
local Elements = require(Shared.Elements)
local Enemies = require(Shared.Config.Enemies)
local EnemyBrain = require(Shared.Combat.EnemyBrain)
local Net = require(Shared.Net)

local ArenaService = require(script.Parent.ArenaService)
local MovementService = require(script.Parent.MovementService)
local PartyService = require(script.Parent.PartyService)

export type Enemy = {
	def: Enemies.EnemyDef,
	model: Model,
	root: BasePart,
	humanoid: Humanoid,
	brain: EnemyBrain.Brain,
	hp: number,
	elements: Elements.TargetState,
	icd: Elements.IcdTracker,
	spawnCFrame: CFrame,
	telegraph: BasePart?,
	target: Player?,
	alive: boolean,
}

local EnemyService = {}

local BRAIN_HZ = 15
local enemies: { Enemy } = {}
local folder: Folder
local feedbackRemote: RemoteEvent
local rng = Random.new()

local function now(): number
	return Workspace:GetServerTimeNow()
end

local function toColor(rgb: { number }): Color3
	return Color3.fromRGB(rgb[1], rgb[2], rgb[3])
end

local function bodyPart(
	model: Model,
	root: BasePart,
	name: string,
	size: Vector3,
	offset: CFrame,
	color: Color3,
	material: Enum.Material?
): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Size = size
	p.Color = color
	p.Material = material or Enum.Material.SmoothPlastic
	p.CanCollide = false
	p.Massless = true
	p.CFrame = root.CFrame * offset
	local joint = Instance.new("WeldConstraint")
	joint.Part0 = root
	joint.Part1 = p
	joint.Parent = p
	p.Parent = model
	return p
end

-- A grey-box body built from parts: legs, body, head, glowing eyes and a club.
local function buildModel(def: Enemies.EnemyDef, cframe: CFrame): (Model, BasePart, Humanoid)
	local model = Instance.new("Model")
	model.Name = def.id

	local root = Instance.new("Part")
	root.Name = "HumanoidRootPart"
	root.Size = Vector3.new(2.6, 2.6, 1.6)
	root.Transparency = 1
	root.CFrame = cframe + Vector3.new(0, 2.8, 0)
	root.Parent = model
	model.PrimaryPart = root

	local color = toColor(def.color)
	local dark = color:Lerp(Color3.new(0, 0, 0), 0.35)
	bodyPart(model, root, "Legs", Vector3.new(2.4, 1.6, 1.6), CFrame.new(0, -2, 0), dark)
	bodyPart(model, root, "Body", Vector3.new(3.2, 3, 2.2), CFrame.new(0, 0.3, 0), color)
	bodyPart(model, root, "Head", Vector3.new(2.2, 2, 2), CFrame.new(0, 2.8, 0), color)
	for _, x in { -0.5, 0.5 } do
		bodyPart(
			model,
			root,
			"Eye",
			Vector3.new(0.4, 0.3, 0.1),
			CFrame.new(x, 3, -1.02),
			Color3.fromRGB(255, 80, 60),
			Enum.Material.Neon
		)
	end
	bodyPart(
		model,
		root,
		"Club",
		Vector3.new(0.7, 0.7, 4),
		CFrame.new(2, 0.2, -1.2),
		dark,
		Enum.Material.Wood
	)

	local humanoid = Instance.new("Humanoid")
	-- R15 so HipHeight holds the body above the ground without leg joints.
	humanoid.RigType = Enum.HumanoidRigType.R15
	humanoid.HipHeight = 1.5
	humanoid.WalkSpeed = def.moveSpeed
	humanoid.MaxHealth = 100
	humanoid.Health = 100
	humanoid.RequiresNeck = false
	humanoid.BreakJointsOnDeath = false
	humanoid.HealthDisplayType = Enum.HumanoidHealthDisplayType.AlwaysOff
	humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
	humanoid:SetStateEnabled(Enum.HumanoidStateType.Dead, false)
	humanoid.Parent = model

	model:SetAttribute("DisplayName", def.displayName)
	model:SetAttribute("MaxHealth", def.stats.maxHp)
	model:SetAttribute("Health", def.stats.maxHp)
	model:SetAttribute("Aura", "")
	model:SetAttribute("State", "idle")
	return model, root, humanoid
end

local function clearTelegraph(enemy: Enemy)
	if enemy.telegraph then
		enemy.telegraph:Destroy()
		enemy.telegraph = nil
	end
end

local function flat(v: Vector3): Vector3
	return Vector3.new(v.X, 0, v.Z)
end

local function face(enemy: Enemy, position: Vector3)
	local from = enemy.root.Position
	local direction = flat(position - from)
	if direction.Magnitude > 0.1 then
		enemy.root.CFrame = CFrame.lookAt(from, from + direction)
	end
end

-- A ground disc that fills in over the wind-up: the outer ring shows the reach, the inner disc
-- shows how long until the strike.
local function showTelegraph(enemy: Enemy)
	clearTelegraph(enemy)
	local radius = enemy.def.strike.radius
	local floorY = enemy.root.Position.Y - enemy.humanoid.HipHeight - enemy.root.Size.Y / 2 + 0.08
	local center = flat(enemy.root.Position + enemy.root.CFrame.LookVector * radius * 0.45)
		+ Vector3.new(0, floorY, 0)

	local ring = Instance.new("Part")
	ring.Name = "Telegraph"
	ring.Shape = Enum.PartType.Cylinder
	ring.Anchored = true
	ring.CanCollide = false
	ring.CanQuery = false
	ring.CanTouch = false
	ring.Material = Enum.Material.Neon
	ring.Color = Color3.fromRGB(255, 70, 50)
	ring.Transparency = 0.75
	ring.Size = Vector3.new(0.1, radius * 2, radius * 2)
	ring.CFrame = CFrame.new(center) * CFrame.Angles(0, 0, math.rad(90))

	local fill = ring:Clone()
	fill.Name = "Fill"
	fill.Transparency = 0.45
	fill.Size = Vector3.new(0.12, 0.2, 0.2)
	fill.Parent = ring
	TweenService:Create(fill, TweenInfo.new(enemy.def.windupSeconds, Enum.EasingStyle.Linear), {
		Size = Vector3.new(0.12, radius * 2, radius * 2),
	}):Play()

	ring.Parent = folder
	enemy.telegraph = ring
end

local function closestTarget(enemy: Enemy): (Player?, number?)
	local best, bestDistance = nil, math.huge
	for _, player in Players:GetPlayers() do
		local character = player.Character
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
		if humanoid and root and humanoid.Health > 0 then
			local distance = (root.Position - enemy.root.Position).Magnitude
			if distance < bestDistance then
				best, bestDistance = player, distance
			end
		end
	end
	if best then
		return best, bestDistance
	end
	return nil, nil
end

local function strike(enemy: Enemy)
	local strikeDef = enemy.def.strike
	local origin = enemy.root.Position
	local forward = enemy.root.CFrame.LookVector
	local t = now()
	local victims = {}

	for _, player in Players:GetPlayers() do
		local character = player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		if root and humanoid and humanoid.Health > 0 then
			local offset = flat(root.Position - origin)
			local inReach = offset.Magnitude <= strikeDef.radius and math.abs(root.Position.Y - origin.Y) < 6
			local angle = if offset.Magnitude > 0.5
				then math.deg(math.acos(math.clamp(forward:Dot(offset.Unit), -1, 1)))
				else 0
			if inReach and angle <= strikeDef.arc / 2 then
				if MovementService.isInvulnerable(player, t) then
					table.insert(victims, { player = player, evaded = true })
				else
					local kit = PartyService.active(player)
					local result = Damage.computeHit({
						attack = enemy.def.stats.attack,
						skillMultiplier = strikeDef.multiplier,
						critRate = 0,
						critDamage = 0,
						attackerLevel = enemy.def.stats.level,
						targetLevel = if kit then kit.stats.defenseLevel else 1,
						resistance = 0,
					}, function()
						return rng:NextNumber()
					end)
					local taken = PartyService.damage(player, result.amount)
					table.insert(victims, { player = player, amount = taken })
				end
			end
		end
	end

	feedbackRemote:FireAllClients({
		kind = "enemyStrike",
		position = origin,
		radius = strikeDef.radius,
		victims = victims,
	})
end

-- Encases a frozen enemy in ice so the status reads from across the arena.
local function setFrozenLook(enemy: Enemy, frozen: boolean)
	local existing = enemy.model:FindFirstChild("FrozenHighlight")
	if frozen and not existing then
		local ice = Instance.new("Highlight")
		ice.Name = "FrozenHighlight"
		ice.FillColor = Color3.fromRGB(170, 235, 255)
		ice.OutlineColor = Color3.fromRGB(230, 250, 255)
		ice.FillTransparency = 0.35
		ice.Parent = enemy.model
	elseif not frozen and existing then
		existing:Destroy()
	end
end

local function setState(enemy: Enemy, state: string)
	enemy.model:SetAttribute("State", state)
end

local function spawnEnemy(def: Enemies.EnemyDef, spawnCFrame: CFrame): Enemy
	local model, root, humanoid = buildModel(def, spawnCFrame)
	local enemy: Enemy = {
		def = def,
		model = model,
		root = root,
		humanoid = humanoid,
		brain = EnemyBrain.new(def),
		hp = def.stats.maxHp,
		elements = Elements.newTarget(),
		icd = Elements.newIcd(),
		spawnCFrame = spawnCFrame,
		telegraph = nil,
		target = nil,
		alive = true,
	}
	model.Parent = folder
	root:SetNetworkOwner(nil)
	CollectionService:AddTag(model, "Enemy")
	table.insert(enemies, enemy)
	return enemy
end

local function die(enemy: Enemy)
	enemy.alive = false
	EnemyBrain.kill(enemy.brain, now())
	clearTelegraph(enemy)
	setState(enemy, "dead")
	CollectionService:RemoveTag(enemy.model, "Enemy")
	enemy.humanoid:Move(Vector3.zero)
	for _, descendant in enemy.model:GetDescendants() do
		if descendant:IsA("BasePart") and descendant ~= enemy.root then
			TweenService:Create(descendant, TweenInfo.new(0.6), { Transparency = 1 }):Play()
		end
	end
	task.delay(0.7, function()
		enemy.model:Destroy()
	end)
	task.delay(enemy.def.respawnSeconds, function()
		local index = table.find(enemies, enemy)
		if index then
			table.remove(enemies, index)
		end
		spawnEnemy(enemy.def, enemy.spawnCFrame)
	end)
end

-- Alive enemies whose body is within `radius` of `center`, and within `arcDegrees` of `forward`
-- when both are given.
function EnemyService.query(
	center: Vector3,
	radius: number,
	forward: Vector3?,
	arcDegrees: number?
): { Enemy }
	local found = {}
	for _, enemy in enemies do
		if enemy.alive then
			local offset = enemy.root.Position - center
			local horizontal = flat(offset)
			-- Measure to the edge of the body, not its centre, so big enemies are easy to hit.
			local reach = horizontal.Magnitude - 1.4
			if reach <= radius and math.abs(offset.Y) < 8 then
				local inArc = true
				if forward and arcDegrees and arcDegrees < 360 and horizontal.Magnitude > 1.5 then
					local angle =
						math.deg(math.acos(math.clamp(flat(forward).Unit:Dot(horizontal.Unit), -1, 1)))
					inArc = angle <= arcDegrees / 2
				end
				if inArc then
					table.insert(found, enemy)
				end
			end
		end
	end
	return found
end

-- Applies confirmed damage and poise. The caller (CombatService) has already resolved
-- elements and the damage formula.
function EnemyService.applyHit(enemy: Enemy, amount: number, poise: number): boolean
	if not enemy.alive then
		return false
	end
	enemy.hp = math.max(0, enemy.hp - amount)
	enemy.model:SetAttribute("Health", enemy.hp)
	local staggered = EnemyBrain.hit(enemy.brain, poise, now())
	if staggered then
		clearTelegraph(enemy)
		enemy.humanoid:Move(Vector3.zero)
		setState(enemy, "stagger")
		-- A small knock-back sells the break.
		enemy.root.AssemblyLinearVelocity = -enemy.root.CFrame.LookVector * 18 + Vector3.new(0, 8, 0)
		feedbackRemote:FireAllClients({ kind = "stagger", position = enemy.root.Position })
	end
	if enemy.hp <= 0 then
		die(enemy)
	end
	return staggered
end

function EnemyService.refreshAura(enemy: Enemy)
	enemy.model:SetAttribute("Aura", Elements.currentAura(enemy.elements, now()) or "")
end

function EnemyService.getAll(): { Enemy }
	return enemies
end

function EnemyService.spawn(defId: string, cframe: CFrame): Enemy
	return spawnEnemy(Enemies[defId], cframe)
end

-- Where a chasing enemy should stand. Enemies that can attack close in; the rest wait in a ring
-- just outside reach, so a group surrounds the player readably instead of piling on top of them.
-- Neighbours push each other apart so the ring stays spread out.
local WAIT_RING_EXTRA = 6
local PERSONAL_SPACE = 5

local function approachPoint(enemy: Enemy, targetPosition: Vector3, engaging: boolean): Vector3
	local away = flat(enemy.root.Position - targetPosition)
	local direction = if away.Magnitude > 0.1 then away.Unit else Vector3.xAxis
	local distance = if engaging then enemy.def.attackRange * 0.7 else enemy.def.attackRange + WAIT_RING_EXTRA

	local push = Vector3.zero
	for _, other in enemies do
		if other ~= enemy and other.alive then
			local apart = flat(enemy.root.Position - other.root.Position)
			local gap = apart.Magnitude
			if gap > 0.01 and gap < PERSONAL_SPACE then
				push += apart.Unit * (PERSONAL_SPACE - gap)
			end
		end
	end
	return targetPosition + direction * distance + push
end

local function stepAll()
	local t = now()
	local attackers = 0
	for _, enemy in enemies do
		if enemy.alive and EnemyBrain.holdsAttackToken(enemy.brain) then
			attackers += 1
		end
	end

	for _, enemy in enemies do
		if not enemy.alive then
			continue
		end
		local target, distance = closestTarget(enemy)
		enemy.target = target
		local frozen = Elements.hasStatus(enemy.elements, "Freeze", t)
		local wasFrozen = enemy.model:GetAttribute("Frozen") == true
		if frozen ~= wasFrozen then
			enemy.model:SetAttribute("Frozen", frozen)
			enemy.humanoid.WalkSpeed = if frozen then 0 else enemy.def.moveSpeed
			setFrozenLook(enemy, frozen)
		end

		local event = EnemyBrain.step(enemy.brain, {
			now = t,
			targetDistance = distance,
			canTakeAttackToken = attackers < CombatConfig.Combat.MaxEnemyAttackers,
			frozen = frozen,
		})

		local targetRoot = target
			and target.Character
			and target.Character:FindFirstChild("HumanoidRootPart") :: BasePart?
		if event == "windup" then
			attackers += 1
			enemy.humanoid:Move(Vector3.zero)
			if targetRoot then
				face(enemy, targetRoot.Position)
			end
			showTelegraph(enemy)
		elseif event == "strike" then
			clearTelegraph(enemy)
			strike(enemy)
		elseif event == "lost" then
			enemy.humanoid:MoveTo(enemy.spawnCFrame.Position)
		end

		if enemy.brain.state == "chase" and targetRoot and not frozen then
			local engaging = attackers < CombatConfig.Combat.MaxEnemyAttackers
			local goal = approachPoint(enemy, targetRoot.Position, engaging)
			if flat(goal - enemy.root.Position).Magnitude > 1 then
				enemy.humanoid:MoveTo(goal)
			else
				enemy.humanoid:Move(Vector3.zero)
				face(enemy, targetRoot.Position)
			end
		end
		setState(enemy, if frozen then "frozen" else enemy.brain.state)
		EnemyService.refreshAura(enemy)
	end
end

function EnemyService:Init()
	feedbackRemote = Net.event(Net.Names.CombatFeedback)
	folder = Instance.new("Folder")
	folder.Name = "Enemies"
	folder.Parent = Workspace
end

function EnemyService:Start()
	local arena = ArenaService.getArena()
	for _, marker in CollectionService:GetTagged("EnemySpawn") do
		if marker:IsA("BasePart") and marker:IsDescendantOf(arena) then
			local position = marker.Position
			spawnEnemy(Enemies.grunt_melee, CFrame.lookAt(position, Vector3.new(0, position.Y, -70)))
		end
	end

	local accumulator = 0
	RunService.Heartbeat:Connect(function(dt)
		accumulator += dt
		if accumulator >= 1 / BRAIN_HZ then
			accumulator = 0
			stepAll()
		end
	end)
end

return EnemyService
