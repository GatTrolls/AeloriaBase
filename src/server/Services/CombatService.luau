--!strict
--[[
	CombatService

	Confirms every attack, skill and burst on the server.

	  1. Type, rate and aliveness checks on the request.
	  2. Timing through Shared.Combat.Ability (recovery, cooldown, energy) for the active hero.
	  3. A hitbox query at the server's copy of positions: an arc in front for the chain, a
	     circle for skills and bursts. The client only sends which way it is aiming.
	  4. For each target: element application with internal cooldowns (Shared.Elements), the
	     damage formula (Shared.Damage), reaction side effects, then poise and HP.
	  5. One feedback message to every client: the action for others to animate, and the
	     confirmed hits for damage numbers, reaction text and hit-stop.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage.Shared
local Ability = require(Shared.Combat.Ability)
local CombatConfig = require(Shared.Config.CombatConfig)
local Damage = require(Shared.Damage)
local Elements = require(Shared.Elements)
local Heroes = require(Shared.Config.Heroes)
local Net = require(Shared.Net)
local RateLimit = require(Shared.RateLimit)

local EnemyService = require(script.Parent.EnemyService)
local PartyService = require(script.Parent.PartyService)

type Action = "attack" | "skill" | "burst"

type HitSpec = {
	multiplier: number,
	element: string?,
	units: number,
	poise: number,
	heavy: boolean,
}

local CombatService = {}

local SWEEP_RADIUS = 9

local limiter = RateLimit.new(CombatConfig.RateLimits.CombatAction)
local feedbackRemote: RemoteEvent
local rng = Random.new()

local function now(): number
	return Workspace:GetServerTimeNow()
end

local function isFiniteVector(value: unknown): boolean
	if typeof(value) ~= "Vector3" then
		return false
	end
	local v = value :: Vector3
	return v.X == v.X and v.Y == v.Y and v.Z == v.Z and v.Magnitude < 1e4
end

local function flatUnit(v: Vector3, fallback: Vector3): Vector3
	local flat = Vector3.new(v.X, 0, v.Z)
	if flat.Magnitude < 0.05 then
		flat = Vector3.new(fallback.X, 0, fallback.Z)
	end
	return if flat.Magnitude < 0.05 then Vector3.new(0, 0, -1) else flat.Unit
end

local function resolveHit(
	player: Player,
	kit: Heroes.Kit,
	enemy: EnemyService.Enemy,
	spec: HitSpec,
	sourceKey: string,
	t: number
)
	local applied: Elements.ApplyResult? = nil
	if spec.element and Elements.icdAllows(enemy.icd, sourceKey, t) then
		applied = Elements.apply(enemy.elements, spec.element, spec.units, t)
	end

	local stats = kit.stats
	local enemyStats = enemy.def.stats
	local brittle = Elements.hasStatus(enemy.elements, "Brittle", t)
	local hit = Damage.computeHit({
		attack = stats.attack,
		skillMultiplier = spec.multiplier,
		critRate = stats.critRate,
		critDamage = stats.critDamage,
		attackerLevel = stats.level,
		targetLevel = enemyStats.defenseLevel,
		resistance = enemyStats.resistance,
		defenseReduction = if brittle then CombatConfig.Combat.BrittleDefenseReduction else 0,
		hitMultiplier = if applied then applied.hitMultiplier else 1,
	}, function()
		return rng:NextNumber()
	end)

	local bonus = 0
	local reactionId: string? = nil
	if applied and applied.reaction then
		reactionId = applied.reaction.id
		if applied.transformScale > 0 then
			bonus = Damage.transformDamage(stats.level, applied.transformScale, enemyStats.resistance)
		end
		if applied.shieldElement then
			PartyService.addShield(player)
		end
		local spread = applied.spreadElement
		if spread then
			for _, other in EnemyService.query(enemy.root.Position, SWEEP_RADIUS) do
				if other ~= enemy then
					Elements.apply(other.elements, spread, 1, t)
					EnemyService.refreshAura(other)
				end
			end
		end
	end

	local position = enemy.root.Position
	EnemyService.applyHit(enemy, hit.amount + bonus, spec.poise)
	EnemyService.refreshAura(enemy)

	return {
		position = position,
		amount = hit.amount,
		bonus = bonus,
		crit = hit.crit,
		element = spec.element,
		reaction = reactionId,
	}
end

local function onAction(player: Player, action: unknown, aim: unknown)
	if action ~= "attack" and action ~= "skill" and action ~= "burst" then
		return
	end
	local t = now()
	if not RateLimit.allow(limiter, player, t) then
		return
	end
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not humanoid or not root or humanoid.Health <= 0 then
		return
	end
	local kit, ability = PartyService.active(player)
	if not kit or not ability then
		return
	end

	local forward = flatUnit(
		if isFiniteVector(aim) then aim :: Vector3 else root.CFrame.LookVector,
		root.CFrame.LookVector
	)
	local tolerance = CombatConfig.Combat.TimingToleranceSeconds
	-- Positions on the server trail what the player saw by a few frames, so reach gets a little slack.
	local reach = CombatConfig.Combat.ReachToleranceStuds
	local origin = root.Position

	local targets: { EnemyService.Enemy } = {}
	local spec: HitSpec
	local chainIndex: number? = nil
	local areaCenter: Vector3? = nil

	if action == "attack" then
		chainIndex = Ability.tryAttack(ability, kit, t, tolerance)
		if not chainIndex then
			return
		end
		local chainHit = kit.chain[chainIndex]
		targets = EnemyService.query(origin, chainHit.range + reach, forward, chainHit.arc)
		spec = {
			multiplier = chainHit.multiplier,
			element = if kit.chainIsElemental then kit.element else nil,
			units = chainHit.units or 1,
			poise = chainHit.poise,
			heavy = chainHit.heavy == true,
		}
	else
		local area = if action == "skill" then kit.skill else kit.burst
		local accepted = if action == "skill"
			then Ability.trySkill(ability, kit, t, tolerance)
			else Ability.tryBurst(ability, kit, t, tolerance)
		if not accepted then
			PartyService.pushState(player)
			return
		end
		areaCenter = origin + forward * area.forward
		targets = EnemyService.query(areaCenter :: Vector3, area.radius + reach)
		spec = {
			multiplier = area.multiplier,
			element = kit.element,
			units = area.units,
			poise = area.poise,
			heavy = true,
		}
	end

	local sourceKey = `{player.UserId}:{kit.id}:{action}`
	local hits = {}
	for _, enemy in targets do
		table.insert(hits, resolveHit(player, kit, enemy, spec, sourceKey, t))
	end

	if action == "skill" and #hits > 0 then
		PartyService.addEnergy(
			player,
			math.min(kit.skill.maxEnergyPerCast, kit.skill.energyPerTarget * #hits)
		)
	elseif action == "attack" and #hits > 0 then
		-- Normal attacks trickle a little energy so a burst is always reachable.
		PartyService.addEnergy(player, 1)
	end
	if action ~= "attack" or #hits > 0 then
		PartyService.pushState(player)
	end

	feedbackRemote:FireAllClients({
		kind = "action",
		attacker = player,
		heroId = kit.id,
		action = action,
		index = chainIndex,
		origin = origin,
		forward = forward,
		areaCenter = areaCenter,
		heavy = spec.heavy,
		hits = hits,
	})
end

function CombatService:Init()
	feedbackRemote = Net.event(Net.Names.CombatFeedback)
	Net.event(Net.Names.CombatAction).OnServerEvent:Connect(onAction)
end

function CombatService:Start()
	Players.PlayerRemoving:Connect(function(player)
		RateLimit.forget(limiter, player)
	end)
end

return CombatService
