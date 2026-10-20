--!strict
--[[
	Rewards

	What happens to a player's profile when an item reaches them: a new character joins the roster,
	a duplicate raises Awakening, a weapon gains Polish, and every pull pays back Moonflakes. Pure
	functions over the profile table, so the rules are tested (tests/Rewards.spec.luau) and the
	server services only decide who gets what.

	The numbers come from the design plan and live in Config/Economy.
]]

local Economy = require("./Config/Economy")
local Items = require("./Config/Items")

export type Grant = {
	itemId: string,
	kind: Items.Kind,
	rarity: number,
	isNew: boolean,
	-- Moonflakes paid for this result.
	moonflakes: number,
	-- A duplicate character's Awakening, or a duplicate weapon's Polish, after this result.
	awakening: number?,
	polish: number?,
	-- True when the duplicate had nothing left to raise, so it paid the larger Moonflake amount.
	maxed: boolean,
}

local Rewards = {}

function Rewards.newRosterEntry(): { [string]: any }
	return { level = 1, exp = 0, ascension = 0, awakening = 0, friendship = 0, talents = {} }
end

function Rewards.newWeaponEntry(): { [string]: any }
	return { count = 0, polish = 1, level = 1, exp = 0 }
end

-- Gives the player an item and reports what it did. Does not touch currencies other than
-- Moonflakes, so callers charge the pull themselves.
function Rewards.grantItem(profile: { [string]: any }, itemId: string): Grant
	local item = Items.get(itemId)
	assert(item, `Rewards: unknown item {itemId}`)
	local payouts = Economy.Moonflakes
	local grant: Grant = {
		itemId = itemId,
		kind = item.kind,
		rarity = item.rarity,
		isNew = false,
		moonflakes = 0,
		maxed = false,
	}

	if item.kind == "character" then
		local roster = profile.roster
		local entry = roster[itemId]
		if not entry then
			roster[itemId] = Rewards.newRosterEntry()
			grant.isNew = true
			grant.awakening = 0
			grant.moonflakes = if item.rarity >= 5 then payouts.any5 else payouts.new4
		else
			local awakening = entry.awakening or 0
			if awakening < Economy.MaxAwakening then
				entry.awakening = awakening + 1
				grant.awakening = awakening + 1
				grant.moonflakes = if item.rarity >= 5 then payouts.any5 else payouts.duplicate4
			else
				grant.awakening = awakening
				grant.maxed = true
				grant.moonflakes = if item.rarity >= 5
					then payouts.duplicate5Maxed
					else payouts.duplicate4Maxed
			end
		end
	else
		local weapons = profile.weapons
		local entry = weapons[itemId]
		if not entry then
			entry = Rewards.newWeaponEntry()
			weapons[itemId] = entry
			grant.isNew = true
		end
		entry.count = (entry.count or 0) + 1
		grant.polish = entry.polish or 1
		if item.rarity <= 3 then
			-- Three-star weapons are upgrade material: they stack and always pay one Moonflake.
			grant.moonflakes = payouts.weapon3
		elseif grant.isNew then
			grant.moonflakes = if item.rarity >= 5 then payouts.any5 else payouts.new4
		elseif (entry.polish or 1) < Economy.MaxPolish then
			entry.polish = (entry.polish or 1) + 1
			grant.polish = entry.polish
			grant.moonflakes = if item.rarity >= 5 then payouts.any5 else payouts.duplicate4
		else
			grant.maxed = true
			grant.moonflakes = if item.rarity >= 5 then payouts.duplicate5Maxed else payouts.duplicate4Maxed
		end
	end

	profile.currencies.moonflakes += grant.moonflakes
	return grant
end

-- Keeps pull history to the platform's six months and a size cap, newest last.
function Rewards.trimHistory(history: { { [string]: any } }, now: number, maxDays: number, maxEntries: number)
	local cutoff = now - maxDays * 86400
	local keepFrom = 1
	for index, entry in history do
		if (entry.at or 0) >= cutoff then
			keepFrom = index
			break
		end
		keepFrom = index + 1
	end
	if keepFrom > 1 then
		table.move(history, keepFrom, #history, 1)
		for index = #history - keepFrom + 2, #history do
			history[index] = nil
		end
	end
	local excess = #history - maxEntries
	if excess > 0 then
		table.move(history, excess + 1, #history, 1)
		for index = #history - excess + 1, #history do
			history[index] = nil
		end
	end
end

-- Whether a player can afford `cost` of a currency.
function Rewards.canAfford(profile: { [string]: any }, currency: string, cost: number): boolean
	return (profile.currencies[currency] or 0) >= cost
end

return Rewards
