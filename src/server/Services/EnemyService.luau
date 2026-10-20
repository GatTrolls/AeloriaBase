--!strict
--[[
	EnemyService

	Spawns enemies at every "EnemySpawn" marker in the place and runs them. Decisions come from
	Shared.Combat.EnemyBrain; this service turns them into movement, telegraphs and strikes, and
	keeps everything else an enemy carries: HP, elemental state, damage over time and effects.

	  * Every wind-up shows its telegraph for its full length: a glint whose colour says how to
	    answer (white normal, gold Liftable, red dodge only) and the attack's shape on the ground.
	  * Only CombatConfig.Combat.MaxEnemyAttackers enemies may wind up at once; the rest wait in a
	    ring just out of reach.
	  * A strike is decided a moment after it lands (Shared.Combat.Defense.resolveAt), so inputs
	    still in flight count: a dodge in time evades, a dodge just before the hit is a Slip, and an
	    attack just before a gold hit is a Lift that cancels it.
	  * Lock and Finales freeze enemies, a Slip slows them, Chilled and Slowed make them walk slower.
	  * Brains run at 15 Hz in one loop for all enemies; Humanoid movement does the rest.

	Enemy HP, status, Composure and state are published as attributes on the model for the UI.
]]

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage.Shared
local CombatConfig = require(Shared.Config.CombatConfig)
local Content = require(Shared.Content)
local Damage = require(Shared.Damage)
local Defense = require(Shared.Combat.Defense)
local ElementConfig = require(Shared.Config.ElementConfig)
local Elements = require(Shared.Elements)
local Enemies = require(Shared.Config.Enemies)
local EnemyBrain = require(Shared.Combat.EnemyBrain)
local Net = require(Shared.Net)

local ActionLog = require(script.Parent.Parent.Combat.ActionLog)
local ArenaService = require(script.Parent.ArenaService)
local PartyService = require(script.Parent.PartyService)

export type Burning = {
	amount: number,
	nextTick: number,
}

export type Enemy = {
	def: Enemies.EnemyDef,
	model: Model,
	root: BasePart,
	humanoid: Humanoid,
	brain: EnemyBrain.Brain,
	hp: number,
	elements: Elements.TargetState,
	burning: Burning?,
	spawnCFrame: CFrame,
	telegraph: BasePart?,
	target: Player?,
	alive: boolean,
	-- Pile-On swaps used during the current Rattled window.
	pileOns: number,
}

local EnemyService = {}

local BRAIN_HZ = 15
local WAIT_RING_EXTRA = 6
local PERSONAL_SPACE = 5
local TELEGRAPH_COLORS: { [string]: Color3 } = {
	normal = Color3.fromRGB(255, 245, 230),
	gold = Color3.fromRGB(255, 200, 60),
	red = Color3.fromRGB(255, 60, 50),
}

local enemies: { Enemy } = {}
local folder: Folder
local feedbackRemote: RemoteEvent
local rng = Random.new()
local Defend = CombatConfig.Defense

local function now(): number
	return Workspace:GetServerTimeNow()
end

local function toColor(rgb: { number }): Color3
	return Color3.fromRGB(rgb[1], rgb[2], rgb[3])
end

local function flat(v: Vector3): Vector3
	return Vector3.new(v.X, 0, v.Z)
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

-- A grey-box body built from parts: legs, body, head, glowing eyes and a club. Large enemies
-- are the same body scaled up.
local function buildModel(def: Enemies.EnemyDef, cframe: CFrame): (Model, BasePart, Humanoid)
	local s = if def.size == "large" then 1.7 else 1
	local model = Instance.new("Model")
	model.Name = def.id

	local root = Instance.new("Part")
	root.Name = "HumanoidRootPart"
	root.Size = Vector3.new(2.6, 2.6, 1.6) * s
	root.Transparency = 1
	root.CFrame = cframe + Vector3.new(0, 2.8 * s, 0)
	root.Parent = model
	model.PrimaryPart = root

	local color = toColor(def.color)
	local dark = color:Lerp(Color3.new(0, 0, 0), 0.35)
	local eye = if def.tier == "elite" then Color3.fromRGB(255, 200, 60) else Color3.fromRGB(255, 80, 60)
	bodyPart(model, root, "Legs", Vector3.new(2.4, 1.6, 1.6) * s, CFrame.new(0, -2 * s, 0), dark)
	bodyPart(model, root, "Body", Vector3.new(3.2, 3, 2.2) * s, CFrame.new(0, 0.3 * s, 0), color)
	bodyPart(model, root, "Head", Vector3.new(2.2, 2, 2) * s, CFrame.new(0, 2.8 * s, 0), color)
	for _, x in { -0.5, 0.5 } do
		bodyPart(
			model,
			root,
			"Eye",
			Vector3.new(0.4, 0.3, 0.1) * s,
			CFrame.new(x * s, 3 * s, -1.02 * s),
			eye,
			Enum.Material.Neon
		)
	end
	bodyPart(
		model,
		root,
		"Club",
		Vector3.new(0.7, 0.7, 4) * s,
		CFrame.new(2 * s, 0.2 * s, -1.2 * s),
		dark,
		Enum.Material.Wood
	)

	local humanoid = Instance.new("Humanoid")
	-- R15 so HipHeight holds the body above the ground without leg joints.
	humanoid.RigType = Enum.HumanoidRigType.R15
	humanoid.HipHeight = 1.5 * s
	humanoid.WalkSpeed = def.moveSpeed
	humanoid.MaxHealth = 100
	humanoid.Health = 100
	humanoid.RequiresNeck = false
	humanoid.BreakJointsOnDeath = false
	humanoid.HealthDisplayType = Enum.HumanoidHealthDisplayType.AlwaysOff
	humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
	humanoid:SetStateEnabled(Enum.HumanoidStateType.Dead, false)
	humanoid.Parent = model

	model:SetAttribute("EnemyId", def.id)
	model:SetAttribute("DisplayName", Content.enemyName(def.id))
	model:SetAttribute("Tier", def.tier)
	model:SetAttribute("MaxHealth", def.stats.maxHp)
	model:SetAttribute("Health", def.stats.maxHp)
	model:SetAttribute("Status", "")
	model:SetAttribute("State", "idle")
	if def.composure then
		model:SetAttribute("MaxComposure", def.composure)
		model:SetAttribute("Composure", 0)
	end
	return model, root, humanoid
end

local function floorY(enemy: Enemy): number
	return enemy.root.Position.Y - enemy.humanoid.HipHeight - enemy.root.Size.Y / 2
end

local function clearTelegraph(enemy: Enemy)
	if enemy.telegraph then
		enemy.telegraph:Destroy()
		enemy.telegraph = nil
	end
	enemy.model:SetAttribute("Telegraph", nil)
end

local function face(enemy: Enemy, position: Vector3)
	local from = enemy.root.Position
	local direction = flat(position - from)
	if direction.Magnitude > 0.1 then
		enemy.root.CFrame = CFrame.lookAt(from, from + direction)
	end
end

-- Where an attack is centred: on the enemy for circles, a little ahead for arcs.
local function attackCenter(enemy: Enemy, attack: Enemies.AttackDef): Vector3
	if attack.shape == "circle" then
		return enemy.root.Position
	end
	return enemy.root.Position + enemy.root.CFrame.LookVector * attack.radius * 0.45
end

-- The ground shape of an attack: an outer ring for its reach and an inner disc that fills over the
-- wind-up, in the telegraph's colour. The glint above the enemy is drawn by the client from the
-- "Telegraph" attribute.
local function showTelegraph(enemy: Enemy, attack: Enemies.AttackDef)
	clearTelegraph(enemy)
	local radius = if attack.shape == "circle" then attack.radius else attack.radius * 0.6
	local center = flat(attackCenter(enemy, attack)) + Vector3.new(0, floorY(enemy) + 0.08, 0)
	local color = TELEGRAPH_COLORS[attack.telegraph]

	local ring = Instance.new("Part")
	ring.Name = "Telegraph"
	ring.Shape = Enum.PartType.Cylinder
	ring.Anchored = true
	ring.CanCollide = false
	ring.CanQuery = false
	ring.CanTouch = false
	ring.Material = Enum.Material.Neon
	ring.Color = color
	ring.Transparency = 0.75
	ring.Size = Vector3.new(0.1, radius * 2, radius * 2)
	ring.CFrame = CFrame.new(center) * CFrame.Angles(0, 0, math.rad(90))

	local fill = ring:Clone()
	fill.Name = "Fill"
	fill.Transparency = 0.45
	fill.Size = Vector3.new(0.12, 0.2, 0.2)
	fill.Parent = ring
	TweenService:Create(fill, TweenInfo.new(attack.windupSeconds, Enum.EasingStyle.Linear), {
		Size = Vector3.new(0.12, radius * 2, radius * 2),
	}):Play()

	ring.Parent = folder
	enemy.telegraph = ring
	enemy.model:SetAttribute("Telegraph", attack.telegraph)
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

local function playersInAttack(
	enemy: Enemy,
	attack: Enemies.AttackDef
): { { player: Player, root: BasePart } }
	local origin = enemy.root.Position
	local forward = enemy.root.CFrame.LookVector
	local found = {}
	for _, player in Players:GetPlayers() do
		local character = player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		if root and humanoid and humanoid.Health > 0 then
			local offset = flat(root.Position - origin)
			local inReach = offset.Magnitude <= attack.radius and math.abs(root.Position.Y - origin.Y) < 8
			local inArc = true
			if attack.shape == "arc" and offset.Magnitude > 0.5 then
				local angle = math.deg(math.acos(math.clamp(forward:Dot(offset.Unit), -1, 1)))
				inArc = angle <= (attack.arc or 360) / 2
			end
			if inReach and inArc then
				table.insert(found, { player = player, root = root })
			end
		end
	end
	return found
end

local function setState(enemy: Enemy, state: string)
	enemy.model:SetAttribute("State", state)
end

local function publishComposure(enemy: Enemy)
	if enemy.def.composure then
		enemy.model:SetAttribute("Composure", enemy.brain.composure)
		enemy.model:SetAttribute("Rattled", EnemyBrain.isRattled(enemy.brain))
	end
end

-- Slows every enemy near a Slip for a moment.
local function slipSlow(position: Vector3, t: number)
	for _, other in enemies do
		if other.alive and (other.root.Position - position).Magnitude <= Defend.SlipSlowRadius then
			Elements.setEffect(other.elements, "Slipped", Defend.SlipSlowSeconds, t)
		end
	end
end

local function slip(player: Player, root: BasePart, t: number)
	local log = ActionLog.get(player)
	log.slipCounterUntil = t + Defend.SlipCounterSeconds
	log.coverUntil = t + Defend.CoverSeconds
	slipSlow(root.Position, t)
	PartyService.addEnergy(player, Defend.SlipEnergy)
	PartyService.pushState(player)
	feedbackRemote:FireAllClients({ kind = "slip", attacker = player, position = root.Position })
end

-- Decides a strike that landed at `strikeAt`, after the latency allowance.
local function resolveStrike(enemy: Enemy, attack: Enemies.AttackDef, strikeAt: number)
	clearTelegraph(enemy)
	-- Killed, staggered or Rattled in the meantime: the attack never lands.
	if not enemy.alive or enemy.brain.state ~= "recover" then
		return
	end
	local resolveAt = Defense.resolveAt(strikeAt)
	local inReach = playersInAttack(enemy, attack)

	if attack.telegraph == "gold" then
		for _, entry in inReach do
			local log = ActionLog.get(entry.player)
			if Defense.isLift(log.lastAttackAt, strikeAt, resolveAt, log.assist) then
				EnemyBrain.interrupt(enemy.brain, Defend.LiftStaggerSeconds, now())
				EnemyService.addComposure(enemy, CombatConfig.Combat.Composure.Lift)
				PartyService.addEnergy(entry.player, Defend.LiftEnergy)
				PartyService.pushState(entry.player)
				feedbackRemote:FireAllClients({
					kind = "lift",
					attacker = entry.player,
					position = enemy.root.Position,
				})
				return
			end
		end
	end

	local victims = {}
	for _, entry in inReach do
		local player = entry.player
		local log = ActionLog.get(player)
		if Defense.evades(log.lastDodgeAt, strikeAt, resolveAt) then
			if Defense.isSlip(log.lastDodgeAt, strikeAt, resolveAt, log.assist) then
				slip(player, entry.root, now())
			end
			table.insert(victims, { player = player, evaded = true })
		else
			local kit = PartyService.active(player)
			local result = Damage.computeHit({
				attack = enemy.def.stats.attack,
				multiplier = attack.multiplier,
				critRate = 0,
				critDamage = 0,
				attackerLevel = enemy.def.stats.level,
				defense = if kit then kit.stats.defense else 0,
				resistance = 0,
			}, function()
				return rng:NextNumber()
			end)
			local taken = PartyService.damage(player, result.amount)
			table.insert(victims, { player = player, amount = taken })
		end
	end

	feedbackRemote:FireAllClients({
		kind = "enemyStrike",
		position = enemy.root.Position,
		radius = attack.radius,
		telegraph = attack.telegraph,
		victims = victims,
	})
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
		burning = nil,
		spawnCFrame = spawnCFrame,
		telegraph = nil,
		target = nil,
		alive = true,
		pileOns = 0,
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
			local reach = horizontal.Magnitude - enemy.root.Size.X * 0.55
			if reach <= radius and math.abs(offset.Y) < 8 + enemy.root.Size.Y then
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

-- Alive enemies along a straight line from `origin`, within `width` studs of it.
function EnemyService.queryLine(origin: Vector3, direction: Vector3, length: number, width: number): { Enemy }
	local dir = flat(direction)
	dir = if dir.Magnitude > 0.01 then dir.Unit else Vector3.new(0, 0, -1)
	local found = {}
	for _, enemy in enemies do
		if enemy.alive then
			local offset = flat(enemy.root.Position - origin)
			local along = offset:Dot(dir)
			local across = (offset - dir * along).Magnitude - enemy.root.Size.X * 0.55
			if along >= -1 and along <= length + 1 and across <= width then
				table.insert(found, enemy)
			end
		end
	end
	return found
end

function EnemyService.nearest(position: Vector3, radius: number): Enemy?
	local best, bestDistance = nil, radius
	for _, enemy in enemies do
		if enemy.alive then
			local distance = (enemy.root.Position - position).Magnitude
			if distance <= bestDistance then
				best, bestDistance = enemy, distance
			end
		end
	end
	return best
end

-- Applies confirmed damage and poise. Returns true if the hit made the enemy flinch.
function EnemyService.applyDamage(enemy: Enemy, amount: number, poise: number): boolean
	if not enemy.alive then
		return false
	end
	enemy.hp = math.max(0, enemy.hp - amount)
	enemy.model:SetAttribute("Health", enemy.hp)
	local flinched = poise > 0 and EnemyBrain.hit(enemy.brain, poise, now())
	if flinched then
		clearTelegraph(enemy)
		enemy.humanoid:Move(Vector3.zero)
	end
	if enemy.hp <= 0 then
		die(enemy)
	end
	return flinched
end

-- Fills an elite's Composure. Returns true if it broke and the enemy is now Rattled.
function EnemyService.addComposure(enemy: Enemy, amount: number): boolean
	if not enemy.alive then
		return false
	end
	local broke = EnemyBrain.addComposure(enemy.brain, amount, now())
	if broke then
		clearTelegraph(enemy)
		enemy.humanoid:Move(Vector3.zero)
		enemy.pileOns = 0
		feedbackRemote:FireAllClients({ kind = "rattled", position = enemy.root.Position })
	end
	publishComposure(enemy)
	return broke
end

function EnemyService.isRattled(enemy: Enemy): boolean
	return enemy.alive and EnemyBrain.isRattled(enemy.brain)
end

-- Rattled enemies near a position, for Pile-On.
function EnemyService.rattledNear(position: Vector3, radius: number): { Enemy }
	local found = {}
	for _, enemy in enemies do
		if EnemyService.isRattled(enemy) and (enemy.root.Position - position).Magnitude <= radius then
			table.insert(found, enemy)
		end
	end
	return found
end

-- Pushes a small enemy (pulls, knock-backs). Large enemies don't budge.
function EnemyService.push(enemy: Enemy, velocity: Vector3)
	if enemy.alive and enemy.def.size == "small" then
		enemy.root.AssemblyLinearVelocity = velocity
	end
end

function EnemyService.setBurning(enemy: Enemy, amount: number)
	local t = now()
	local current = enemy.burning
	if current then
		current.amount = math.max(current.amount, amount)
	else
		enemy.burning = { amount = amount, nextTick = t + ElementConfig.BurningTickSeconds }
	end
end

-- Freezes enemies near a position for a moment (Finales).
function EnemyService.halt(position: Vector3, radius: number, seconds: number)
	local t = now()
	for _, enemy in enemies do
		if enemy.alive and (enemy.root.Position - position).Magnitude <= radius then
			Elements.setEffect(enemy.elements, "Halted", seconds, t)
		end
	end
end

function EnemyService.refreshStatus(enemy: Enemy)
	enemy.model:SetAttribute("Status", Elements.statusOf(enemy.elements, now()) or "")
	enemy.model:SetAttribute("Locked", Elements.hasEffect(enemy.elements, "Locked", now()))
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
local function approachPoint(enemy: Enemy, targetPosition: Vector3, engaging: boolean): Vector3
	local away = flat(enemy.root.Position - targetPosition)
	local direction = if away.Magnitude > 0.1 then away.Unit else Vector3.xAxis
	local reach = EnemyBrain.reach(enemy.def)
	local distance = if engaging then reach * 0.7 else reach + WAIT_RING_EXTRA

	local push = Vector3.zero
	for _, other in enemies do
		if other ~= enemy and other.alive then
			local apart = flat(enemy.root.Position - other.root.Position)
			local gap = apart.Magnitude
			local space = PERSONAL_SPACE + (other.root.Size.X + enemy.root.Size.X) * 0.25
			if gap > 0.01 and gap < space then
				push += apart.Unit * (space - gap)
			end
		end
	end
	return targetPosition + direction * distance + push
end

local function tickBurning(enemy: Enemy, t: number)
	local burning = enemy.burning
	if not burning then
		return
	end
	if Elements.statusOf(enemy.elements, t) ~= "Flame" then
		enemy.burning = nil
		return
	end
	if t >= burning.nextTick then
		burning.nextTick = t + ElementConfig.BurningTickSeconds
		local position = enemy.root.Position
		EnemyService.applyDamage(enemy, burning.amount, 0)
		feedbackRemote:FireAllClients({
			kind = "dot",
			position = position,
			amount = burning.amount,
			element = "Flame",
		})
	end
end

local function moveSpeedFor(enemy: Enemy, t: number): number
	local speed = enemy.def.moveSpeed
	if Elements.statusOf(enemy.elements, t) == "Frost" then
		speed *= 1 - ElementConfig.ChilledSlow
	end
	if Elements.hasEffect(enemy.elements, "Slowed", t) then
		speed *= CombatConfig.Combat.SlowedFactor
	end
	return speed
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
		tickBurning(enemy, t)
		if not enemy.alive then
			continue
		end

		local target, distance = closestTarget(enemy)
		enemy.target = target
		local elements = enemy.elements
		local locked = Elements.hasEffect(elements, "Locked", t) and enemy.def.tier ~= "elite"
		local frozen = locked
			or Elements.hasEffect(elements, "Halted", t)
			or Elements.hasEffect(elements, "Slipped", t)
		local wasFrozen = enemy.model:GetAttribute("Frozen") == true
		if frozen ~= wasFrozen then
			enemy.model:SetAttribute("Frozen", frozen)
		end
		enemy.humanoid.WalkSpeed = if frozen then 0 else moveSpeedFor(enemy, t)

		local event = EnemyBrain.step(enemy.brain, {
			now = t,
			targetDistance = distance,
			canTakeAttackToken = attackers < CombatConfig.Combat.MaxEnemyAttackers,
			frozen = frozen,
			roll = rng:NextNumber(),
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
			showTelegraph(enemy, enemy.brain.attack :: Enemies.AttackDef)
		elseif event == "strike" then
			local attack = enemy.brain.attack
			if attack then
				task.delay(Defend.LatencyAllowance, resolveStrike, enemy, attack, t)
			end
		elseif event == "recovered" then
			publishComposure(enemy)
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
		elseif enemy.brain.state ~= "chase" then
			enemy.humanoid:Move(Vector3.zero)
		end
		setState(enemy, if frozen then "frozen" else enemy.brain.state)
		EnemyService.refreshStatus(enemy)
	end
end

function EnemyService:Init()
	feedbackRemote = Net.event(Net.Names.CombatFeedback)
	folder = Instance.new("Folder")
	folder.Name = "Enemies"
	folder.Parent = Workspace
end

function EnemyService:Start()
	-- Make sure the arena (and its markers) exists, then spawn at every marker in the place,
	-- including any level blockouts built in Studio.
	ArenaService.getArena()
	for _, marker in CollectionService:GetTagged("EnemySpawn") do
		if marker:IsA("BasePart") and marker:IsDescendantOf(Workspace) then
			local position = marker.Position
			local defId = marker:GetAttribute("Enemy")
			local def = Enemies[if type(defId) == "string" then defId else "grunt_melee"]
				or Enemies.grunt_melee
			spawnEnemy(def, CFrame.lookAt(position, Vector3.new(0, position.Y, -70)))
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
