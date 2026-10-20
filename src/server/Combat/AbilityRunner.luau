--!strict
--[[
	AbilityRunner

	Runs the steps of a Technique, Finale or Relay (see the step kinds in Config/Heroes.luau).
	Each step is scheduled at its delay from the start of the action, uses the caster's position
	and aim when the action started (moved along by any dash before it), and tells every client
	what happened so they can draw it.

	Techniques give Finale energy per enemy hit, up to the kit's cap per cast. Relay hits fill
	Composure. Zones (healing pools, molten glass, frozen constellations) keep ticking on their own
	until they expire.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage.Shared
local Ability = require(Shared.Combat.Ability)
local CombatConfig = require(Shared.Config.CombatConfig)
local Damage = require(Shared.Damage)
local Elements = require(Shared.Elements)
local Heroes = require(Shared.Config.Heroes)
local Net = require(Shared.Net)

local HitResolver = require(script.Parent.HitResolver)
local Services = script.Parent.Parent.Services
local EnemyService = require(Services.EnemyService)
local PartyService = require(Services.PartyService)

export type Part = "technique" | "finale" | "relay"

type Context = {
	player: Player,
	kit: Heroes.Kit,
	part: Part,
	origin: Vector3,
	forward: Vector3,
	incomingHeroId: string?,
	-- Shared by every step of one cast: energy given so far and the enemies already counted.
	tally: { given: number, hit: { [any]: boolean } },
}

type Zone = {
	context: Context,
	step: Heroes.Step,
	center: Vector3,
	endsAt: number,
	nextTick: number,
}

local AbilityRunner = {}

local feedbackRemote: RemoteEvent? = nil
local zones: { Zone } = {}
local zoneLoop: RBXScriptConnection? = nil
local rng = Random.new()

local function now(): number
	return Workspace:GetServerTimeNow()
end

local function feedback(message: { [string]: any })
	if not feedbackRemote then
		feedbackRemote = Net.event(Net.Names.CombatFeedback)
	end
	(feedbackRemote :: RemoteEvent):FireAllClients(message)
end

local function stepElement(context: Context, step: Heroes.Step): string?
	if step.element == "none" then
		return nil
	end
	return step.element or context.kit.element
end

local function centerOf(context: Context, step: Heroes.Step): Vector3
	return context.origin + context.forward * (step.forward or 0)
end

-- Technique hits give Finale energy per new enemy, up to the cap for one cast.
local function giveEnergy(context: Context, enemy: EnemyService.Enemy)
	local tally = context.tally
	if context.part ~= "technique" or tally.hit[enemy] then
		return
	end
	tally.hit[enemy] = true
	local technique = context.kit.technique
	local amount = math.min(technique.energyPerTarget, technique.maxEnergyPerCast - tally.given)
	if amount > 0 then
		tally.given += amount
		PartyService.addEnergy(context.player, amount)
	end
end

local function hitEnemies(context: Context, step: Heroes.Step, targets: { EnemyService.Enemy })
	local results = {}
	for _, enemy in targets do
		giveEnergy(context, enemy)
		table.insert(
			results,
			HitResolver.resolve(context.player, context.kit, enemy, {
				multiplier = step.multiplier or 1,
				poise = step.poise or 0,
				heavy = step.heavy == true,
				element = stepElement(context, step),
				basic = false,
				composure = if context.part == "relay" then CombatConfig.Combat.Composure.Relay else nil,
			})
		)
	end
	if #targets > 0 then
		PartyService.pushState(context.player)
	end
	return results
end

local function send(context: Context, step: Heroes.Step, extra: { [string]: any })
	extra.kind = "step"
	extra.step = step.kind
	extra.attacker = context.player
	extra.heroId = context.kit.id
	extra.part = context.part
	extra.element = stepElement(context, step)
	extra.forward = context.forward
	feedback(extra)
end

local function healAmount(context: Context, attackShare: number, hpShare: number)
	return function(member)
		return Damage.heal(context.kit.stats.attack, attackShare, member.maxHp, hpShare)
	end
end

local function healTarget(context: Context, target: string?): string
	if target == "incoming" then
		return context.incomingHeroId or "active"
	end
	return target or "active"
end

local function rootOf(player: Player): BasePart?
	local character = player.Character
	return character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
end

local function tickZones()
	local t = now()
	for index = #zones, 1, -1 do
		local zone = zones[index]
		local context = zone.context
		if t >= zone.endsAt or not context.player.Parent then
			table.remove(zones, index)
		elseif t >= zone.nextTick then
			zone.nextTick = t + (zone.step.interval or 1)
			local step = zone.step
			if step.tickHit then
				local results = hitEnemies(context, {
					kind = "hit",
					multiplier = step.tickHit.multiplier,
					poise = step.tickHit.poise,
					element = step.element,
				}, EnemyService.query(zone.center, step.radius or 5))
				if #results > 0 then
					send(
						context,
						step,
						{ center = zone.center, radius = step.radius, tick = true, hits = results }
					)
				end
			end
			local heal = step.tickHeal
			local root = rootOf(context.player)
			if heal and root and (root.Position - zone.center).Magnitude <= (step.radius or 5) + 1 then
				local restored = PartyService.heal(
					context.player,
					"active",
					healAmount(context, heal.attackShare, heal.hpShare)
				)
				if restored > 0 then
					send(
						context,
						step,
						{ center = zone.center, tick = true, healed = restored, position = root.Position }
					)
				end
			end
		end
	end
	if #zones == 0 and zoneLoop then
		zoneLoop:Disconnect()
		zoneLoop = nil
	end
end

local function dashEnd(context: Context, length: number): Vector3
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	local exclude: { Instance } = {}
	for _, player in Players:GetPlayers() do
		if player.Character then
			table.insert(exclude, player.Character)
		end
	end
	local enemies = Workspace:FindFirstChild("Enemies")
	if enemies then
		table.insert(exclude, enemies)
	end
	params.FilterDescendantsInstances = exclude
	local hit = Workspace:Raycast(context.origin, context.forward * length, params)
	if hit then
		return hit.Position - context.forward * 1.5
	end
	return context.origin + context.forward * length
end

local function runStep(context: Context, step: Heroes.Step)
	local kind = step.kind
	if not context.player.Parent then
		return
	end

	if kind == "hit" then
		local center = centerOf(context, step)
		local radius = (step.radius or 5) + CombatConfig.Combat.ReachToleranceStuds
		local targets = if step.shape == "arc"
			then EnemyService.query(context.origin, radius, context.forward, step.arc)
			else EnemyService.query(center, radius)
		send(context, step, {
			center = center,
			radius = step.radius,
			shape = step.shape,
			arc = step.arc,
			origin = context.origin,
			heavy = step.heavy,
			hits = hitEnemies(context, step, targets),
		})
	elseif kind == "line" then
		local length = step.length or 10
		local targets = EnemyService.queryLine(
			context.origin - context.forward * length,
			context.forward,
			length,
			(step.width or 3) + CombatConfig.Combat.ReachToleranceStuds
		)
		send(context, step, {
			from = context.origin - context.forward * length,
			to = context.origin,
			hits = hitEnemies(context, step, targets),
		})
	elseif kind == "pull" then
		local center = centerOf(context, step)
		for _, enemy in EnemyService.query(center, step.radius or 8) do
			local inward = (center - enemy.root.Position) * Vector3.new(1, 0, 1)
			if inward.Magnitude > 1.5 then
				EnemyService.push(enemy, inward.Unit * (step.strength or 20) + Vector3.new(0, 8, 0))
			end
		end
		send(context, step, { center = center, radius = step.radius })
	elseif kind == "rain" then
		local center = centerOf(context, step)
		local count = step.count or 8
		for index = 1, count do
			task.delay((index - 1) * (step.interval or 0.1), function()
				local angle = rng:NextNumber() * math.pi * 2
				local distance = math.sqrt(rng:NextNumber()) * (step.radius or 8)
				local point = center + Vector3.new(math.cos(angle) * distance, 0, math.sin(angle) * distance)
				local impact = step.impactRadius or 3
				send(context, step, {
					center = point,
					radius = impact,
					hits = hitEnemies(context, step, EnemyService.query(point, impact)),
				})
			end)
		end
	elseif kind == "zone" then
		local center = centerOf(context, step)
		local t = now()
		table.insert(zones, {
			context = context,
			step = step,
			center = center,
			endsAt = t + (step.seconds or 5),
			nextTick = t,
		})
		if not zoneLoop then
			zoneLoop = RunService.Heartbeat:Connect(tickZones)
		end
		send(context, step, { center = center, radius = step.radius, seconds = step.seconds })
	elseif kind == "heal" then
		local restored = PartyService.heal(
			context.player,
			healTarget(context, step.target),
			healAmount(context, step.attackShare or 0, step.hpShare or 0)
		)
		local root = rootOf(context.player)
		send(context, step, {
			target = step.target,
			healed = restored,
			position = if root then root.Position else context.origin,
		})
	elseif kind == "shield" then
		PartyService.addShield(context.player, step.target or "active", function(member)
			return member.maxHp * (step.hpShare or 0.1)
		end)
		send(context, step, { target = step.target })
	elseif kind == "effect" then
		local center = centerOf(context, step)
		local t = now()
		local effect = step.effect or "Slowed"
		local affected = {}
		if effect == "Marked" then
			local enemy = EnemyService.nearest(center, step.radius or 15)
			if enemy then
				affected = { enemy }
			end
		else
			affected = EnemyService.query(center, step.radius or 6)
		end
		local positions = {}
		for _, enemy in affected do
			Elements.setEffect(enemy.elements, effect, step.seconds or 4, t)
			enemy.model:SetAttribute(effect, true)
			task.delay(step.seconds or 4, function()
				if enemy.model.Parent and not Elements.hasEffect(enemy.elements, effect, now()) then
					enemy.model:SetAttribute(effect, nil)
				end
			end)
			table.insert(positions, enemy.root.Position)
		end
		send(context, step, { center = center, radius = step.radius, effect = effect, positions = positions })
	elseif kind == "infuse" then
		local record = PartyService.get(context.player)
		local heroId = if step.target == "incoming" then context.incomingHeroId else context.kit.id
		local ability = record and heroId and record.abilities[heroId]
		if ability then
			Ability.infuse(ability, context.kit.element, step.hits or 3)
			PartyService.pushState(context.player)
		end
		send(context, step, { heroIdTarget = heroId })
	end
end

-- Runs one Technique, Finale or Relay. `origin` and `forward` are the caster's position and flat
-- aim when it started.
function AbilityRunner.run(
	player: Player,
	kit: Heroes.Kit,
	part: Part,
	origin: Vector3,
	forward: Vector3,
	incomingHeroId: string?
)
	local steps = if part == "technique"
		then kit.technique.steps
		elseif part == "finale" then kit.finale.steps
		else kit.relay.steps
	local context: Context = {
		player = player,
		kit = kit,
		part = part,
		origin = origin,
		forward = forward,
		incomingHeroId = incomingHeroId,
		tally = { given = 0, hit = {} },
	}
	feedback({
		kind = "ability",
		attacker = player,
		heroId = kit.id,
		part = part,
		origin = origin,
		forward = forward,
	})

	for _, step in steps do
		if step.kind == "dash" then
			-- The dash moves every later step's origin straight away; the client moves the
			-- character itself.
			local from = context.origin
			context.origin = dashEnd(context, step.length or 10)
			send(context, step, { from = from, to = context.origin, seconds = step.seconds })
		else
			-- Later dashes must not move a step that was scheduled before them, so each step
			-- keeps its own copy of the context (the tally table stays shared).
			local snapshot = table.clone(context)
			local delay = step.delay or 0
			if delay > 0 then
				task.delay(delay, runStep, snapshot, step)
			else
				runStep(snapshot, step)
			end
		end
	end
end

return AbilityRunner
