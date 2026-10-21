--!strict
--[[
	HitResolver

	Turns one confirmed hit on one enemy into its outcome. Used by every action: basic attacks,
	charged attacks, plunges, and every step of a Technique, Finale or Relay.

	  1. The element lands through Shared.Elements (basic attacks once every 2.5 s per enemy).
	  2. Reactions do their work: Scald and Thaw multiply the hit, Flashpoint explodes, Conduct
	     chains between Wet enemies, Lock freezes, Brittle weakens, Sweep spreads, Geode leaves a
	     crystal shield, Starburst blasts and feeds the main character's Finale.
	  3. Shared.Damage turns stats into a number, with Brittle, Sweep, Marked and Rattled applied.
	  4. Heavy hits shatter Lock. Heavy hits, reactions, Relays and Slip counters fill Composure.
	  5. Burning is (re)lit when Flame is left on the enemy.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage.Shared
local CombatConfig = require(Shared.Config.CombatConfig)
local Damage = require(Shared.Damage)
local ElementConfig = require(Shared.Config.ElementConfig)
local ElementStyle = require(Shared.Config.ElementStyle)
local Elements = require(Shared.Elements)
local Heroes = require(Shared.Config.Heroes)
local Net = require(Shared.Net)

local Services = script.Parent.Parent.Services
local EnemyService = require(Services.EnemyService)
local PartyService = require(Services.PartyService)

export type HitSpec = {
	multiplier: number,
	poise: number,
	heavy: boolean,
	-- The element the hit carries; nil is physical.
	element: string?,
	-- Basic attacks apply their element at most once every 2.5 s per enemy.
	basic: boolean,
	-- Extra Composure on top of heavy hits and reactions (Relays, Slip counters).
	composure: number?,
	-- Extra damage scale (Slip counters).
	damageScale: number?,
}

export type HitFeedback = {
	position: Vector3,
	amount: number,
	bonus: number,
	crit: boolean,
	element: string?,
	reaction: string?,
	shatter: boolean?,
}

type Crystal = {
	part: BasePart,
	element: string,
	endsAt: number,
}

local HitResolver = {}

local Composure = CombatConfig.Combat.Composure
local rng = Random.new()
local feedbackRemote: RemoteEvent? = nil
local crystals: { Crystal } = {}
local crystalLoop: RBXScriptConnection? = nil

local function now(): number
	return Workspace:GetServerTimeNow()
end

local function feedback(message: { [string]: any })
	if not feedbackRemote then
		feedbackRemote = Net.event(Net.Names.CombatFeedback)
	end
	(feedbackRemote :: RemoteEvent):FireAllClients(message)
end

local function resistanceOf(enemy: EnemyService.Enemy, element: string?, t: number): number
	local stats = enemy.def.stats
	local base = stats.resistance
	if element and stats.elementResistance and stats.elementResistance[element] then
		base = stats.elementResistance[element]
	end
	if element then
		base -= Elements.resistanceCut(enemy.elements, element, t)
	end
	return base
end

local function damageTaken(enemy: EnemyService.Enemy): number
	return if EnemyService.isRattled(enemy) then CombatConfig.Combat.RattledDamageTaken else 0
end

local function reactionHit(
	kit: Heroes.Kit,
	enemy: EnemyService.Enemy,
	scale: number,
	element: string?,
	t: number
): number
	return Damage.reactionDamage(kit.stats.level, scale, resistanceOf(enemy, element, t), damageTaken(enemy))
end

local function rgb(values: { number }): Color3
	return Color3.fromRGB(values[1], values[2], values[3])
end

local function stepCrystals()
	local t = now()
	for index = #crystals, 1, -1 do
		local crystal = crystals[index]
		local taken = false
		if t < crystal.endsAt then
			for _, player in Players:GetPlayers() do
				local root = player.Character
					and player.Character:FindFirstChild("HumanoidRootPart") :: BasePart?
				if
					root
					and (root.Position - crystal.part.Position).Magnitude
						<= CombatConfig.Combat.GeodePickupRadius
				then
					PartyService.addShield(player, "active", function(member)
						return member.maxHp * CombatConfig.Combat.GeodeShieldShare
					end, crystal.element)
					feedback({
						kind = "geode",
						attacker = player,
						position = root.Position,
						element = crystal.element,
					})
					taken = true
					break
				end
			end
		end
		if taken or t >= crystal.endsAt then
			crystal.part:Destroy()
			table.remove(crystals, index)
		end
	end
	if #crystals == 0 and crystalLoop then
		crystalLoop:Disconnect()
		crystalLoop = nil
	end
end

local function spawnCrystal(position: Vector3, element: string, seconds: number)
	local part = Instance.new("Part")
	part.Name = "GeodeCrystal"
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.Material = Enum.Material.Glass
	part.Color = rgb(ElementStyle.Elements[element] or ElementStyle.Physical)
	part.Size = Vector3.new(1.4, 2.2, 1.4)
	part.CFrame = CFrame.new(position.X, position.Y - 1.4, position.Z) * CFrame.Angles(0, 0, math.rad(45))
	part.Parent = Workspace:FindFirstChild("Enemies") or Workspace
	TweenService
		:Create(part, TweenInfo.new(1, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true), {
			CFrame = part.CFrame * CFrame.new(0, 0.6, 0) * CFrame.Angles(0, math.rad(90), 0),
		})
		:Play()
	table.insert(crystals, { part = part, element = element, endsAt = now() + seconds })
	if not crystalLoop then
		crystalLoop = RunService.Heartbeat:Connect(stepCrystals)
	end
end

-- Flashpoint: an explosion around the target that knocks small enemies back.
local function explode(kit: Heroes.Kit, center: Vector3, reaction: ElementConfig.ReactionDef, t: number)
	local hits = {}
	for _, enemy in EnemyService.query(center, reaction.radius or 6) do
		local amount = reactionHit(kit, enemy, reaction.scale or 1, "Flame", t)
		local away = enemy.root.Position - center
		local direction = if away.Magnitude > 0.1 then (away * Vector3.new(1, 0, 1)).Unit else Vector3.zero
		table.insert(hits, { position = enemy.root.Position, amount = amount, element = "Flame" })
		EnemyService.addComposure(enemy, Composure.Reaction * 0.5)
		EnemyService.applyDamage(enemy, amount, 15)
		EnemyService.push(enemy, direction * 30 + Vector3.new(0, 18, 0))
	end
	feedback({
		kind = "explosion",
		position = center,
		radius = reaction.radius,
		element = "Flame",
		hits = hits,
	})
end

-- Conduct: lightning jumps between Wet enemies near the target once a second.
local function conduct(kit: Heroes.Kit, target: EnemyService.Enemy, reaction: ElementConfig.ReactionDef)
	local ticks = reaction.ticks or 4
	for tick = 1, ticks do
		task.delay(tick * ((reaction.seconds or ticks) / ticks), function()
			local t = now()
			if not target.alive then
				return
			end
			local center = target.root.Position
			local hits = {}
			for _, enemy in EnemyService.query(center, reaction.radius or 8) do
				if enemy == target or Elements.statusOf(enemy.elements, t) == "Tide" then
					local amount = reactionHit(kit, enemy, reaction.scale or 0.3, "Volt", t)
					table.insert(hits, { position = enemy.root.Position, amount = amount, element = "Volt" })
					EnemyService.applyDamage(enemy, amount, 0)
				end
			end
			feedback({ kind = "chain", position = center, element = "Volt", hits = hits })
		end)
	end
end

-- Sweep: spreads the swept status to nearby enemies, pulls small ones in and cuts their
-- resistance to it.
local function sweep(
	kit: Heroes.Kit,
	target: EnemyService.Enemy,
	swept: string,
	reaction: ElementConfig.ReactionDef,
	t: number
)
	local center = target.root.Position
	local hits = {}
	for _, enemy in EnemyService.query(center, reaction.radius or 8) do
		if enemy ~= target then
			Elements.setStatus(enemy.elements, swept, t)
			enemy.elements.resistanceCuts[swept] = t + (reaction.seconds or 8)
			local inward = center - enemy.root.Position
			if inward.Magnitude > 2 then
				EnemyService.push(enemy, (inward * Vector3.new(1, 0, 1)).Unit * 22 + Vector3.new(0, 6, 0))
			end
		end
		local amount = reactionHit(kit, enemy, reaction.scale or 0.5, swept, t)
		table.insert(hits, { position = enemy.root.Position, amount = amount, element = swept })
		EnemyService.applyDamage(enemy, amount, 0)
		EnemyService.refreshStatus(enemy)
	end
	feedback({ kind = "sweep", position = center, radius = reaction.radius, element = swept, hits = hits })
end

function HitResolver.resolve(
	player: Player,
	kit: Heroes.Kit,
	enemy: EnemyService.Enemy,
	spec: HitSpec
): HitFeedback
	local t = now()
	local position = enemy.root.Position
	local applied: Elements.ApplyResult? = nil
	if spec.element then
		applied = Elements.apply(enemy.elements, spec.element, t, {
			basic = spec.basic,
			sourceKey = `{player.UserId}:{kit.id}`,
		})
	end

	local reaction = applied and applied.reaction
	local elite = enemy.def.tier == "elite"
	local bonus = 0
	local composure = (if spec.heavy then Composure.HeavyHit else 0) + (spec.composure or 0)

	if reaction and applied then
		composure += Composure.Reaction
		local consumed = applied.consumed :: string
		if reaction.kind == "explode" then
			explode(kit, position, reaction, t)
		elseif reaction.kind == "chain" then
			conduct(kit, enemy, reaction)
		elseif reaction.kind == "lock" and elite then
			-- Elites and bosses can't be frozen; they take Composure damage instead.
			Elements.clearEffect(enemy.elements, "Locked")
			composure += Composure.Lock
		elseif reaction.kind == "spread" then
			sweep(kit, enemy, consumed, reaction, t)
		elseif reaction.kind == "geode" then
			spawnCrystal(position, consumed, reaction.seconds or 10)
		elseif reaction.kind == "starburst" then
			bonus += reactionHit(kit, enemy, reaction.scale or 2, "Astral", t)
			bonus += reactionHit(kit, enemy, (reaction.scale or 2) * 0.5, consumed, t)
			PartyService.addEnergyTo(player, kit.id, reaction.energy or 0)
		end
	end

	local stats = kit.stats
	local marked = Elements.hasEffect(enemy.elements, "Marked", t)
	local hit = Damage.computeHit({
		attack = stats.attack,
		multiplier = spec.multiplier * (spec.damageScale or 1),
		critRate = stats.critRate,
		critDamage = stats.critDamage + (if marked then CombatConfig.Combat.MarkedCritDamageBonus else 0),
		attackerLevel = stats.level,
		defense = enemy.def.stats.defense,
		defenseCut = if Elements.hasEffect(enemy.elements, "Brittle", t)
			then ElementConfig.Reactions["Frost+Volt"].defenseCut
			else 0,
		resistance = resistanceOf(enemy, spec.element, t),
		reactionMultiplier = if applied then applied.hitMultiplier else 1,
		damageTaken = damageTaken(enemy),
	}, function()
		return rng:NextNumber()
	end)

	local shattered = false
	if spec.heavy and Elements.shatter(enemy.elements, t) then
		shattered = true
		local lock = ElementConfig.Reactions["Frost+Tide"]
		bonus += reactionHit(kit, enemy, lock.shatterScale or 1.5, "Frost", t)
	end

	if composure > 0 then
		EnemyService.addComposure(enemy, composure)
	end
	enemy.lastHitBy = player
	EnemyService.applyDamage(enemy, hit.amount + bonus, spec.poise)

	if enemy.alive and applied and applied.statusAfter == "Flame" then
		EnemyService.setBurning(enemy, reactionHit(kit, enemy, ElementConfig.BurningScale, "Flame", t))
	end
	EnemyService.refreshStatus(enemy)

	return {
		position = position,
		amount = hit.amount,
		bonus = bonus,
		crit = hit.crit,
		element = spec.element,
		reaction = reaction and reaction.id,
		shatter = shattered or nil,
	}
end

return HitResolver
