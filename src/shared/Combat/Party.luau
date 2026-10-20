--!strict
--[[
	Party

	Up to four heroes, one on the field. HP and shields are kept per hero; swapping is instant and
	has a short cooldown. A hero at 0 HP is down and cannot be swapped in. Pure Luau; covered by
	tests/Party.spec.luau.
]]

export type Member = {
	heroId: string,
	hp: number,
	maxHp: number,
	shield: number,
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
		table.insert(members, { heroId = heroId, hp = maxHp, maxHp = maxHp, shield = 0 })
	end
	return { members = members, active = 1, lastSwapAt = -math.huge }
end

function Party.activeMember(state: State): Member
	return state.members[state.active]
end

function Party.trySwap(state: State, slot: number, now: number, cooldown: number): (boolean, SwapError?)
	local member = state.members[slot]
	if not member then
		return false, "invalid_slot"
	end
	if slot == state.active then
		return false, "already_active"
	end
	if member.hp <= 0 then
		return false, "down"
	end
	if now - state.lastSwapAt < cooldown then
		return false, "cooldown"
	end
	state.active = slot
	state.lastSwapAt = now
	return true, nil
end

-- Damages the active hero, shield first. Returns the HP damage taken and whether the hero went down.
function Party.damageActive(state: State, amount: number): (number, boolean)
	local member = Party.activeMember(state)
	local absorbed = math.min(member.shield, amount)
	member.shield -= absorbed
	local taken = math.min(member.hp, amount - absorbed)
	member.hp -= taken
	return taken, member.hp <= 0
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
	state.active = slot
	state.lastSwapAt = now
	return true
end

function Party.restoreAll(state: State)
	for _, member in state.members do
		member.hp = member.maxHp
		member.shield = 0
	end
end

return Party
