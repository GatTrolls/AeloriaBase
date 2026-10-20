--!strict
--[[
	Party

	Up to four heroes, one on the field. HP and shields are kept per hero; swapping is instant
	and has a short cooldown. A hero at 0 HP is down and cannot be swapped in. A hero that has
	rested on the bench long enough fires their Relay when swapped in. Pure Luau; covered by
	tests/Party.spec.luau.
]]

local CombatConfig = require("../Config/CombatConfig")

export type Member = {
	heroId: string,
	hp: number,
	maxHp: number,
	shield: number,
	-- A Geode shield absorbs more of its own element.
	shieldElement: string?,
	-- When this hero last left the field.
	benchedSince: number,
}

export type State = {
	members: { Member },
	active: number,
	lastSwapAt: number,
}

export type SwapError = "invalid_slot" | "already_active" | "cooldown" | "down"

local Party = {}

function Party.new(heroIds: { string }, maxHpFor: (heroId: string) -> number): State
	local members = {}
	for _, heroId in heroIds do
		local maxHp = maxHpFor(heroId)
		table.insert(members, {
			heroId = heroId,
			hp = maxHp,
			maxHp = maxHp,
			shield = 0,
			shieldElement = nil,
			benchedSince = -math.huge,
		})
	end
	return { members = members, active = 1, lastSwapAt = -math.huge }
end

function Party.activeMember(state: State): Member
	return state.members[state.active]
end

-- Whether swapping this hero in now would fire their Relay.
function Party.relayReady(state: State, slot: number, now: number): boolean
	local member = state.members[slot]
	return member ~= nil
		and slot ~= state.active
		and member.hp > 0
		and now - member.benchedSince >= CombatConfig.Combat.RelayBenchSeconds
end

local function moveTo(state: State, slot: number, now: number)
	Party.activeMember(state).benchedSince = now
	state.active = slot
	state.lastSwapAt = now
end

-- Swaps the active hero. `ignoreCooldown` is for Cover and Pile-On swaps. Returns whether the
-- swap happened, why not, and whether the incoming hero's Relay fires.
function Party.trySwap(
	state: State,
	slot: number,
	now: number,
	cooldown: number,
	ignoreCooldown: boolean?
): (boolean, SwapError?, boolean)
	local member = state.members[slot]
	if not member then
		return false, "invalid_slot", false
	end
	if slot == state.active then
		return false, "already_active", false
	end
	if member.hp <= 0 then
		return false, "down", false
	end
	if not ignoreCooldown and now - state.lastSwapAt < cooldown then
		return false, "cooldown", false
	end
	local relay = Party.relayReady(state, slot, now)
	moveTo(state, slot, now)
	return true, nil, relay
end

-- Damages the active hero, shield first. Returns the HP damage taken and whether the hero went down.
function Party.damageActive(state: State, amount: number, element: string?): (number, boolean)
	local member = Party.activeMember(state)
	local strength = if element and member.shieldElement == element
		then 1 + CombatConfig.Combat.GeodeOwnElementBonus
		else 1
	local absorbed = math.min(member.shield * strength, amount)
	member.shield -= absorbed / strength
	if member.shield <= 0.001 then
		member.shield = 0
		member.shieldElement = nil
	end
	local taken = math.min(member.hp, amount - absorbed)
	member.hp -= taken
	return taken, member.hp <= 0
end

-- Heals a standing hero, up to their max HP. Returns the HP restored.
function Party.heal(member: Member, amount: number): number
	if member.hp <= 0 then
		return 0
	end
	local restored = math.min(member.maxHp - member.hp, amount)
	member.hp += restored
	return restored
end

function Party.addShield(member: Member, amount: number, element: string?)
	if amount > member.shield then
		member.shield = amount
		member.shieldElement = element
	end
end

-- The next hero still standing after the active one, or nil if the whole party is down.
function Party.nextStanding(state: State): number?
	local count = #state.members
	for offset = 1, count - 1 do
		local slot = (state.active + offset - 1) % count + 1
		if state.members[slot].hp > 0 then
			return slot
		end
	end
	return nil
end

-- Moves the field to the next standing hero, ignoring the swap cooldown. Used when a hero goes down.
function Party.forceNext(state: State, now: number): boolean
	local slot = Party.nextStanding(state)
	if not slot then
		return false
	end
	moveTo(state, slot, now)
	return true
end

function Party.restoreAll(state: State)
	for _, member in state.members do
		member.hp = member.maxHp
		member.shield = 0
		member.shieldElement = nil
	end
end

return Party
