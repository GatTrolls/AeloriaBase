--!strict
--[[
	PartyController

	The client's view of the party: the latest snapshot from PartyService, plus a local copy of
	each hero's Shared.Combat.Ability state so attacks can be timed and the HUD can count down
	without waiting for the server. Server snapshots always overwrite cooldowns and energy.

	Swap with 1-4, the D-pad (up, right, down, left) or by tapping a hero in the party list.
]]

local ContextActionService = game:GetService("ContextActionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Ability = require(ReplicatedStorage.Shared.Combat.Ability)
local GameConfig = require(ReplicatedStorage.Shared.Config.GameConfig)
local Heroes = require(ReplicatedStorage.Shared.Config.Heroes)
local Net = require(ReplicatedStorage.Shared.Net)

export type MemberSnapshot = {
	heroId: string,
	hp: number,
	maxHp: number,
	shield: number,
	energy: number,
	energyCost: number,
	skillReadyAt: number,
	burstReadyAt: number,
}

export type Snapshot = {
	active: number,
	swapReadyAt: number,
	members: { MemberSnapshot },
}

local PartyController = {}

local swapRemote: RemoteEvent
local snapshot: Snapshot? = nil
local abilities: { [string]: Ability.State } = {}
local listeners: { () -> () } = {}

local SWAP_KEYS = {
	[Enum.KeyCode.One] = 1,
	[Enum.KeyCode.Two] = 2,
	[Enum.KeyCode.Three] = 3,
	[Enum.KeyCode.Four] = 4,
	[Enum.KeyCode.DPadUp] = 1,
	[Enum.KeyCode.DPadRight] = 2,
	[Enum.KeyCode.DPadDown] = 3,
	[Enum.KeyCode.DPadLeft] = 4,
}

local function notify()
	for _, listener in listeners do
		task.spawn(listener)
	end
end

function PartyController.onChanged(listener: () -> ())
	table.insert(listeners, listener)
end

function PartyController.getSnapshot(): Snapshot?
	return snapshot
end

function PartyController.now(): number
	return Workspace:GetServerTimeNow()
end

-- The active hero's kit and local timing state.
function PartyController.active(): (Heroes.Kit?, Ability.State?)
	if not snapshot then
		return nil, nil
	end
	local member = snapshot.members[snapshot.active]
	if not member then
		return nil, nil
	end
	local state = abilities[member.heroId]
	if not state then
		state = Ability.new()
		abilities[member.heroId] = state
	end
	return Heroes[member.heroId], state
end

function PartyController.requestSwap(slot: number)
	local current = snapshot
	if not current then
		return
	end
	local member = current.members[slot]
	if
		not member
		or slot == current.active
		or member.hp <= 0
		or PartyController.now() < current.swapReadyAt
	then
		return
	end
	-- Predict the swap so the HUD answers instantly; the server's snapshot confirms or corrects it.
	local outgoing = current.members[current.active]
	if outgoing and abilities[outgoing.heroId] then
		Ability.cancelRecovery(abilities[outgoing.heroId])
	end
	current.active = slot
	current.swapReadyAt = PartyController.now() + GameConfig.Party.SwapCooldownSeconds
	swapRemote:FireServer(slot)
	notify()
end

local function onState(next: Snapshot)
	snapshot = next
	for _, member in next.members do
		local state = abilities[member.heroId] or Ability.new()
		state.energy = member.energy
		state.skillReadyAt = member.skillReadyAt
		state.burstReadyAt = member.burstReadyAt
		abilities[member.heroId] = state
	end
	notify()
end

function PartyController:Init()
	swapRemote = Net.event(Net.Names.PartySwap)
end

function PartyController:Start()
	Net.event(Net.Names.PartyState).OnClientEvent:Connect(onState)

	local keys = {}
	for key in SWAP_KEYS do
		table.insert(keys, key)
	end
	ContextActionService:BindAction("FarbornSwap", function(_, state, input)
		if state == Enum.UserInputState.Begin then
			local slot = SWAP_KEYS[input.KeyCode]
			if slot then
				PartyController.requestSwap(slot)
			end
		end
		return Enum.ContextActionResult.Sink
	end, false, table.unpack(keys))
end

return PartyController
