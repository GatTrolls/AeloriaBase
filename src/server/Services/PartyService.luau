--!strict
--[[
	PartyService

	Owns each player's party: who is on the field, HP and shields per hero, and every hero's
	cooldowns, Finale energy and infusions (Shared.Combat.Ability). The Humanoid mirrors the
	active hero's HP, and the active hero's weapon is attached to the character so everyone can
	see who is fighting.

	Swaps go through Shared.Combat.Party, so the cooldown, Relay and "can't swap to a downed hero"
	rules are the same ones the tests cover. CombatService decides when a swap may ignore the
	cooldown (Cover and Pile-On) and runs Relays, through `setSwapPolicy` and `onSwapped`. When the
	active hero goes down the next one takes the field; when the whole party is down the character
	respawns with everyone restored.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage.Shared
local Ability = require(Shared.Combat.Ability)
local CombatConfig = require(Shared.Config.CombatConfig)
local GameConfig = require(Shared.Config.GameConfig)
local Heroes = require(Shared.Config.Heroes)
local Net = require(Shared.Net)
local Party = require(Shared.Combat.Party)
local RateLimit = require(Shared.RateLimit)

local PlayerDataService = require(script.Parent.PlayerDataService)

export type Record = {
	party: Party.State,
	abilities: { [string]: Ability.State },
}

export type SwapKind = "swap" | "cover" | "pileon" | "forced"

export type SwapInfo = {
	fromHeroId: string,
	toHeroId: string,
	relay: boolean,
	kind: SwapKind,
}

-- Decides whether a swap may ignore the cooldown, and what kind of swap it is.
export type SwapPolicy = (player: Player, slot: number, now: number) -> SwapKind

local PartyService = {}

local records: { [Player]: Record } = {}
local swapLimiter = RateLimit.new(CombatConfig.RateLimits.PartySwap)
local stateRemote: RemoteEvent
local feedbackRemote: RemoteEvent
local swapPolicy: SwapPolicy = function(_player, _slot, _now)
	return "swap"
end
local swapListeners: { (Player, SwapInfo) -> () } = {}

local function now(): number
	return Workspace:GetServerTimeNow()
end

local function toColor(rgb: { number }): Color3
	return Color3.fromRGB(rgb[1], rgb[2], rgb[3])
end

local function weld(part: BasePart, to: BasePart, offset: CFrame)
	part.CFrame = to.CFrame * offset
	local joint = Instance.new("WeldConstraint")
	joint.Part0 = to
	joint.Part1 = part
	joint.Parent = part
end

local function weaponPart(
	model: Model,
	name: string,
	size: Vector3,
	color: Color3,
	material: Enum.Material?
): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Size = size
	p.Color = color
	p.Material = material or Enum.Material.SmoothPlastic
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.Massless = true
	p.Parent = model
	return p
end

-- Grey-box weapons built from parts, one shape per weapon type, tinted by element.
local function attachWeapon(character: Model, kit: Heroes.Kit)
	local old = character:FindFirstChild("HeroWeapon")
	if old then
		old:Destroy()
	end
	local hand = (character:FindFirstChild("RightHand") or character:FindFirstChild("Right Arm")) :: BasePart?
	if not hand then
		return
	end

	local model = Instance.new("Model")
	model.Name = "HeroWeapon"
	local tint = toColor(kit.color)
	local metal = Color3.fromRGB(70, 70, 80)
	local grip = CFrame.new(0, -hand.Size.Y / 2, 0)

	if kit.weapon == "focus" then
		local orb = weaponPart(model, "Orb", Vector3.new(1.1, 1.1, 1.1), tint, Enum.Material.Neon)
		orb.Shape = Enum.PartType.Ball
		weld(orb, hand, grip * CFrame.new(0.9, 0.6, -0.6))
	elseif kit.weapon == "bow" then
		local bow = weaponPart(model, "Bow", Vector3.new(0.2, 4.2, 0.35), tint, Enum.Material.Neon)
		weld(bow, hand, grip * CFrame.new(0, 0, -0.3))
	else
		local length = if kit.weapon == "lance" then 7 elseif kit.weapon == "greatsword" then 5 else 3.8
		local width = if kit.weapon == "greatsword" then 1 elseif kit.weapon == "lance" then 0.3 else 0.45
		local handle = weaponPart(model, "Handle", Vector3.new(0.3, 0.3, 1.1), metal)
		weld(handle, hand, grip * CFrame.new(0, -0.2, 0))
		local blade = weaponPart(model, "Blade", Vector3.new(0.15, width, length), tint, Enum.Material.Neon)
		weld(blade, handle, CFrame.new(0, 0, -(length / 2 + 0.5)))
	end
	model.Parent = character
end

local function applyToCharacter(player: Player, record: Record)
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not character or not humanoid or humanoid.Health <= 0 then
		return
	end
	local member = Party.activeMember(record.party)
	humanoid.MaxHealth = member.maxHp
	humanoid.Health = math.max(member.hp, 0.01)
	character:SetAttribute("HeroId", member.heroId)
	attachWeapon(character, Heroes[member.heroId])
end

local function snapshot(record: Record)
	local members = {}
	for slot, member in record.party.members do
		local ability = record.abilities[member.heroId]
		local kit = Heroes[member.heroId]
		members[slot] = {
			heroId = member.heroId,
			hp = member.hp,
			maxHp = member.maxHp,
			shield = member.shield,
			energy = ability.energy,
			energyCost = kit.finale.energyCost,
			techniqueReadyAt = ability.techniqueReadyAt,
			finaleReadyAt = ability.finaleReadyAt,
			benchedSince = member.benchedSince,
			infusedHits = ability.infusedHits,
		}
	end
	return {
		active = record.party.active,
		swapReadyAt = record.party.lastSwapAt + GameConfig.Party.SwapCooldownSeconds,
		members = members,
	}
end

function PartyService.pushState(player: Player)
	local record = records[player]
	if record then
		stateRemote:FireClient(player, snapshot(record))
	end
end

function PartyService.get(player: Player): Record?
	return records[player]
end

-- The active hero's kit, timing state and party member, or nil if the player has no party yet.
function PartyService.active(player: Player): (Heroes.Kit?, Ability.State?, Party.Member?)
	local record = records[player]
	if not record then
		return nil, nil, nil
	end
	local member = Party.activeMember(record.party)
	return Heroes[member.heroId], record.abilities[member.heroId], member
end

function PartyService.setSwapPolicy(policy: SwapPolicy)
	swapPolicy = policy
end

function PartyService.onSwapped(listener: (Player, SwapInfo) -> ())
	table.insert(swapListeners, listener)
end

-- Gives Finale energy to the active hero and a share to everyone on the bench.
function PartyService.addEnergy(player: Player, amount: number)
	local record = records[player]
	if not record or amount <= 0 then
		return
	end
	for slot, member in record.party.members do
		local share = if slot == record.party.active then 1 else CombatConfig.Combat.BenchEnergyShare
		Ability.addEnergy(record.abilities[member.heroId], Heroes[member.heroId], amount * share)
	end
end

-- Gives Finale energy to one hero only, wherever they are (Starburst feeds the main character).
function PartyService.addEnergyTo(player: Player, heroId: string, amount: number)
	local record = records[player]
	local ability = record and record.abilities[heroId]
	if ability then
		Ability.addEnergy(ability, Heroes[heroId], amount)
	end
end

local function syncHumanoid(player: Player, record: Record)
	local humanoid = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
	if humanoid and humanoid.Health > 0 then
		local member = Party.activeMember(record.party)
		humanoid.Health = math.max(member.hp, 0.01)
	end
end

-- Heals heroes: "active", "party" (everyone standing), or a hero by id. `amountFor` gets each
-- hero's member record and returns how much to heal. Returns the total HP restored.
function PartyService.heal(player: Player, target: string, amountFor: (Party.Member) -> number): number
	local record = records[player]
	if not record then
		return 0
	end
	local restored = 0
	for slot, member in record.party.members do
		local chosen = (target == "party")
			or (target == "active" and slot == record.party.active)
			or (target == member.heroId)
		if chosen then
			restored += Party.heal(member, amountFor(member))
		end
	end
	if restored > 0 then
		syncHumanoid(player, record)
		PartyService.pushState(player)
	end
	return restored
end

function PartyService.addShield(
	player: Player,
	target: string,
	amountFor: (Party.Member) -> number,
	element: string?
)
	local record = records[player]
	if not record then
		return
	end
	for slot, member in record.party.members do
		if target == "party" or (target == "active" and slot == record.party.active) then
			Party.addShield(member, amountFor(member), element)
		end
	end
	PartyService.pushState(player)
end

-- Damages the active hero. Handles a hero going down and a full party wipe. Returns HP lost.
function PartyService.damage(player: Player, amount: number, element: string?): number
	local record = records[player]
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not record or not humanoid or humanoid.Health <= 0 then
		return 0
	end
	local taken, down = Party.damageActive(record.party, amount, element)
	if down then
		local outgoing = Party.activeMember(record.party).heroId
		if Party.forceNext(record.party, now()) then
			applyToCharacter(player, record)
			local info: SwapInfo = {
				fromHeroId = outgoing,
				toHeroId = Party.activeMember(record.party).heroId,
				relay = false,
				kind = "forced",
			}
			feedbackRemote:FireAllClients({ kind = "swap", attacker = player, swap = "forced" })
			for _, listener in swapListeners do
				task.spawn(listener, player, info)
			end
		else
			humanoid.Health = 0
		end
	else
		syncHumanoid(player, record)
	end
	PartyService.pushState(player)
	return taken
end

local function onSwap(player: Player, slot: unknown)
	local record = records[player]
	if not record or type(slot) ~= "number" or slot ~= math.floor(slot) then
		return
	end
	local t = now()
	if not RateLimit.allow(swapLimiter, player, t) then
		return
	end
	local humanoid = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
	if not humanoid or humanoid.Health <= 0 then
		return
	end
	local outgoing = Party.activeMember(record.party).heroId
	local kind = swapPolicy(player, slot, t)
	local ok, _, relay =
		Party.trySwap(record.party, slot, t, GameConfig.Party.SwapCooldownSeconds, kind ~= "swap")
	if ok then
		Ability.cancelRecovery(record.abilities[outgoing])
		applyToCharacter(player, record)
		local info: SwapInfo = {
			fromHeroId = outgoing,
			toHeroId = Party.activeMember(record.party).heroId,
			-- A Cover always counters with the incoming hero's Relay.
			relay = relay or kind == "cover",
			kind = kind,
		}
		feedbackRemote:FireAllClients({ kind = "swap", attacker = player, swap = kind })
		for _, listener in swapListeners do
			task.spawn(listener, player, info)
		end
	end
	-- Always answer, so a refused swap corrects the client's prediction.
	PartyService.pushState(player)
end

local function onCharacterAdded(player: Player, character: Model)
	local record = records[player]
	if not record then
		return
	end
	-- HP only changes through combat, so remove the default regeneration script.
	local regen = character:WaitForChild("Health", 5)
	if regen then
		regen:Destroy()
	end
	if Party.activeMember(record.party).hp <= 0 then
		Party.restoreAll(record.party)
		record.party.active = 1
	end
	character:WaitForChild("Humanoid")
	applyToCharacter(player, record)
	PartyService.pushState(player)
end

local function owned(profile: { [string]: any }, heroId: string): boolean
	if table.find(GameConfig.Party.StarterParty, heroId) then
		return true
	end
	return profile.roster ~= nil and profile.roster[heroId] ~= nil
end

-- Rebuilds the live party around a new line-up. Heroes who stay keep their cooldowns and energy;
-- everyone comes back standing, so a line-up change is also a free heal and is refused mid-fight.
local function rebuild(player: Player, record: Record, heroIds: { string })
	local abilities = {}
	for _, heroId in heroIds do
		abilities[heroId] = record.abilities[heroId] or Ability.new()
	end
	record.party = Party.new(heroIds, function(heroId)
		return Heroes[heroId].stats.maxHp
	end)
	record.abilities = abilities
	applyToCharacter(player, record)
	PartyService.pushState(player)
end

-- A line-up the player may field: 1..MaxMembers distinct heroes they own. Returns the cleaned list
-- or an error code.
local function cleanLineup(profile: any, heroIds: unknown): ({ string }?, string?)
	if type(heroIds) ~= "table" then
		return nil, "bad_request"
	end
	local list = heroIds :: { any }
	if #list < 1 or #list > GameConfig.Party.MaxMembers then
		return nil, "bad_size"
	end
	local clean: { string } = {}
	local seen: { [string]: boolean } = {}
	for _, heroId in list do
		if type(heroId) ~= "string" or not Heroes[heroId] or seen[heroId] then
			return nil, "bad_hero"
		end
		if not owned(profile, heroId) then
			return nil, "not_owned"
		end
		seen[heroId] = true
		table.insert(clean, heroId)
	end
	return clean, nil
end

local function onPreset(player: Player, slot: unknown, heroIds: unknown): { [string]: any }
	local profile = PlayerDataService.get(player)
	if not profile then
		return { ok = false, error = "not_loaded" }
	end
	if type(slot) ~= "number" or slot % 1 ~= 0 or slot < 1 or slot > GameConfig.Party.PresetSlots then
		return { ok = false, error = "bad_request" }
	end
	local clean, problem = cleanLineup(profile, heroIds)
	if not clean then
		return { ok = false, error = problem }
	end
	if type(profile.presets) ~= "table" then
		profile.presets = {}
	end
	profile.presets[slot] = clean
	PlayerDataService.markChanged(player)
	return { ok = true }
end

local function onEdit(player: Player, heroIds: unknown): { [string]: any }
	local record = records[player]
	if not record then
		return { ok = false, error = "bad_request" }
	end
	local profile = PlayerDataService.get(player)
	if not profile then
		return { ok = false, error = "not_loaded" }
	end
	local clean, problem = cleanLineup(profile, heroIds)
	if not clean then
		return { ok = false, error = problem }
	end
	local humanoid = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
	if humanoid and humanoid.Health <= 0 then
		return { ok = false, error = "down" }
	end
	profile.party = clean
	PlayerDataService.markChanged(player)
	rebuild(player, record, clean)
	return { ok = true }
end

function PartyService:Init()
	stateRemote = Net.event(Net.Names.PartyState)
	feedbackRemote = Net.event(Net.Names.CombatFeedback)
	Net.event(Net.Names.PartySwap).OnServerEvent:Connect(onSwap)
	Net.func(Net.Names.PartyEdit).OnServerInvoke = onEdit
	Net.func(Net.Names.PartyPreset).OnServerInvoke = onPreset
end

function PartyService:Start()
	local function onPlayerAdded(player: Player)
		local heroIds = GameConfig.Party.StarterParty
		local abilities = {}
		for _, heroId in heroIds do
			abilities[heroId] = Ability.new()
		end
		records[player] = {
			party = Party.new(heroIds, function(heroId)
				return Heroes[heroId].stats.maxHp
			end),
			abilities = abilities,
		}
		player.CharacterAdded:Connect(function(character)
			onCharacterAdded(player, character)
		end)
		if player.Character then
			task.spawn(onCharacterAdded, player, player.Character)
		end
		-- The saved line-up replaces the free team once the profile is in.
		task.spawn(function()
			local profile = PlayerDataService.waitFor(player)
			local record = records[player]
			local saved = profile and profile.party
			if
				not record
				or type(saved) ~= "table"
				or #saved == 0
				or #saved > GameConfig.Party.MaxMembers
			then
				return
			end
			for _, heroId in saved do
				if type(heroId) ~= "string" or not Heroes[heroId] or not owned(profile :: any, heroId) then
					return
				end
			end
			rebuild(player, record, saved)
		end)
	end

	Players.PlayerAdded:Connect(onPlayerAdded)
	for _, player in Players:GetPlayers() do
		task.spawn(onPlayerAdded, player)
	end
	Players.PlayerRemoving:Connect(function(player)
		records[player] = nil
		RateLimit.forget(swapLimiter, player)
	end)
end

return PartyService
