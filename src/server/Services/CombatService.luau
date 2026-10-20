--!strict
--[[
	CombatService

	Confirms every attack, charged attack, plunge, Technique and Finale on the server, and runs
	Relays when a rested hero swaps in.

	  1. Type, rate and aliveness checks on the request.
	  2. Timing through Shared.Combat.Ability for the active hero (recovery, cooldown, energy).
	  3. Hitboxes at the server's copy of positions: an arc in front for the chain, a circle for
	     charged spins and plunges. The client only sends which way it is aiming.
	  4. Each enemy hit goes through Combat/HitResolver (elements, reactions, damage, Composure).
	     Techniques, Finales and Relays run their steps through Combat/AbilityRunner.
	  5. One feedback message to every client: the action for others to animate, and the
	     confirmed hits for damage numbers, reaction names and hit-stop.

	It also decides which swaps may ignore the swap cooldown: a Cover (a swap right after a Slip)
	and Pile-On (Relay swaps on a Rattled enemy, up to three in a row).
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage.Shared
local Ability = require(Shared.Combat.Ability)
local CombatConfig = require(Shared.Config.CombatConfig)
local Heroes = require(Shared.Config.Heroes)
local Net = require(Shared.Net)
local Party = require(Shared.Combat.Party)
local RateLimit = require(Shared.RateLimit)

local Combat = script.Parent.Parent.Combat
local AbilityRunner = require(Combat.AbilityRunner)
local ActionLog = require(Combat.ActionLog)
local EnemyService = require(script.Parent.EnemyService)
local HitResolver = require(Combat.HitResolver)
local MovementService = require(script.Parent.MovementService)
local PartyService = require(script.Parent.PartyService)

type Action = "attack" | "charged" | "plunge" | "technique" | "finale"

local CombatService = {}

local ACTIONS: { [string]: boolean } = {
	attack = true,
	charged = true,
	plunge = true,
	technique = true,
	finale = true,
}

local limiter = RateLimit.new(CombatConfig.RateLimits.CombatAction)
local feedbackRemote: RemoteEvent

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

-- The element a basic, charged or plunge attack carries: an infusion first, then the hero's own
-- element for Focus users, otherwise physical.
local function basicElement(kit: Heroes.Kit, ability: Ability.State): string?
	local infused = Ability.takeInfusion(ability)
	if infused then
		return infused
	end
	return if kit.chainIsElemental then kit.element else nil
end

-- A basic or charged attack, or a plunge. Returns the feedback payload, or nil if refused.
local function basicAction(
	player: Player,
	kit: Heroes.Kit,
	ability: Ability.State,
	action: Action,
	root: BasePart,
	forward: Vector3,
	t: number
): { [string]: any }?
	local tolerance = CombatConfig.Combat.TimingToleranceSeconds
	local reach = CombatConfig.Combat.ReachToleranceStuds
	local origin = root.Position
	local log = ActionLog.get(player)

	local hitDef: Heroes.Hit
	local chainIndex: number? = nil
	local targets: { EnemyService.Enemy }

	if action == "attack" then
		chainIndex = Ability.tryAttack(ability, kit, t, tolerance)
		if not chainIndex then
			return nil
		end
		hitDef = kit.chain[chainIndex :: number]
		targets = EnemyService.query(origin, hitDef.range + reach, forward, hitDef.arc)
	elseif action == "charged" then
		if not Ability.tryCharged(ability, kit, t, tolerance) then
			return nil
		end
		hitDef = kit.charged
		targets = EnemyService.query(origin, hitDef.range + reach, forward, hitDef.arc)
	else
		-- Plunge: only after a real fall.
		if MovementService.recentDrop(player, 1.5) < CombatConfig.Movement.PlungeMinHeight then
			return nil
		end
		if not Ability.tryPlunge(ability, t, tolerance) then
			return nil
		end
		local plunge = kit.plunge
		hitDef = {
			multiplier = plunge.multiplier,
			range = plunge.radius,
			arc = 360,
			recovery = 0.35,
			poise = plunge.poise,
			heavy = true,
		}
		targets = EnemyService.query(origin, plunge.radius + reach)
	end

	log.lastAttackAt = t
	local counter = t <= log.slipCounterUntil
	if counter then
		log.slipCounterUntil = -math.huge
	end

	local element = basicElement(kit, ability)
	local hits = {}
	for _, enemy in targets do
		table.insert(
			hits,
			HitResolver.resolve(player, kit, enemy, {
				multiplier = hitDef.multiplier,
				poise = hitDef.poise,
				heavy = hitDef.heavy == true,
				element = element,
				basic = true,
				composure = if counter then CombatConfig.Combat.Composure.SlipCounter else nil,
				damageScale = if counter then CombatConfig.Defense.SlipCounterMultiplier else nil,
			})
		)
	end
	if #hits > 0 then
		-- Landed hits trickle a little energy so a Finale is always reachable.
		PartyService.addEnergy(player, 1)
		PartyService.pushState(player)
	end

	return {
		kind = "action",
		attacker = player,
		heroId = kit.id,
		action = action,
		index = chainIndex,
		origin = origin,
		forward = forward,
		element = element,
		heavy = hitDef.heavy == true,
		counter = counter or nil,
		hits = hits,
	}
end

local function onAction(player: Player, action: unknown, aim: unknown)
	if type(action) ~= "string" or not ACTIONS[action] then
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

	if action == "technique" then
		if Ability.tryTechnique(ability, kit, t, tolerance) then
			AbilityRunner.run(player, kit, "technique", root.Position, forward)
		end
		PartyService.pushState(player)
		return
	end

	if action == "finale" then
		if Ability.tryFinale(ability, kit, t, tolerance) then
			EnemyService.halt(
				root.Position,
				CombatConfig.Combat.FinaleFreezeRadius,
				CombatConfig.Combat.FinaleFreezeSeconds
			)
			AbilityRunner.run(player, kit, "finale", root.Position, forward)
		end
		PartyService.pushState(player)
		return
	end

	local payload = basicAction(player, kit, ability, action :: Action, root, forward, t)
	if payload then
		feedbackRemote:FireAllClients(payload)
	end
end

-- Cover: a swap right after a Slip. Pile-On: a Relay swap while an enemy nearby is Rattled.
-- Both ignore the swap cooldown.
local function swapPolicy(player: Player, slot: number, t: number): PartyService.SwapKind
	if t <= ActionLog.get(player).coverUntil then
		return "cover"
	end
	local record = PartyService.get(player)
	local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if record and root and Party.relayReady(record.party, slot, t) then
		for _, enemy in EnemyService.rattledNear(root.Position, CombatConfig.Combat.PileOnRange) do
			if enemy.pileOns < CombatConfig.Combat.PileOnMax then
				return "pileon"
			end
		end
	end
	return "swap"
end

local function onSwapped(player: Player, info: PartyService.SwapInfo)
	local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not root then
		return
	end
	if info.kind == "cover" then
		ActionLog.get(player).coverUntil = -math.huge
	elseif info.kind == "pileon" then
		for _, enemy in EnemyService.rattledNear(root.Position, CombatConfig.Combat.PileOnRange) do
			if enemy.pileOns < CombatConfig.Combat.PileOnMax then
				enemy.pileOns += 1
				break
			end
		end
	end
	if info.relay then
		local kit = Heroes[info.toHeroId]
		local forward = flatUnit(root.CFrame.LookVector, Vector3.zAxis)
		AbilityRunner.run(player, kit, "relay", root.Position, forward, info.toHeroId)
	end
end

function CombatService:Init()
	feedbackRemote = Net.event(Net.Names.CombatFeedback)
	Net.event(Net.Names.CombatAction).OnServerEvent:Connect(onAction)
end

function CombatService:Start()
	PartyService.setSwapPolicy(swapPolicy)
	PartyService.onSwapped(onSwapped)
	Players.PlayerRemoving:Connect(function(player)
		RateLimit.forget(limiter, player)
	end)
end

return CombatService
