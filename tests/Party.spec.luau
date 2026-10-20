--!strict
local CombatConfig = require("../src/shared/Config/CombatConfig")
local Party = require("../src/shared/Combat/Party")
local TestKit = require("./TestKit")

local RELAY = CombatConfig.Combat.RelayBenchSeconds

local function newParty()
	return Party.new({ "a", "b", "c", "d" }, function()
		return 1000
	end)
end

return {
	["swapping changes the active hero"] = function()
		local party = newParty()
		TestKit.truthy(Party.trySwap(party, 3, 10, 1))
		TestKit.equal(Party.activeMember(party).heroId, "c")
	end,

	["swaps inside the cooldown are refused unless forced"] = function()
		local party = newParty()
		Party.trySwap(party, 2, 10, 1)
		local ok, reason = Party.trySwap(party, 3, 10.5, 1)
		TestKit.equal(ok, false)
		TestKit.equal(reason, "cooldown")
		TestKit.truthy(Party.trySwap(party, 3, 10.5, 1, true), "Cover and Pile-On ignore the cooldown")
	end,

	["bad and redundant swaps are refused"] = function()
		local party = newParty()
		TestKit.equal(select(2, Party.trySwap(party, 9, 10, 1)), "invalid_slot")
		TestKit.equal(select(2, Party.trySwap(party, 1, 10, 1)), "already_active")
	end,

	["a hero rested on the bench fires their relay"] = function()
		local party = newParty()
		local _, _, relay = Party.trySwap(party, 2, 10, 1)
		TestKit.truthy(relay, "benched from the start")
		local _, _, backTooSoon = Party.trySwap(party, 1, 12, 1)
		TestKit.equal(backTooSoon, false, "hero 1 only rested 2 seconds")
		local _, _, rested = Party.trySwap(party, 2, 12 + RELAY, 1)
		TestKit.truthy(rested)
	end,

	["hp is kept per hero"] = function()
		local party = newParty()
		Party.damageActive(party, 300)
		Party.trySwap(party, 2, 10, 1)
		TestKit.equal(Party.activeMember(party).hp, 1000)
		TestKit.equal(party.members[1].hp, 700)
	end,

	["shields absorb damage first"] = function()
		local party = newParty()
		Party.addShield(Party.activeMember(party), 200)
		local taken = Party.damageActive(party, 250)
		TestKit.equal(taken, 50)
		TestKit.equal(Party.activeMember(party).shield, 0)
	end,

	["a geode shield absorbs more of its own element"] = function()
		local party = newParty()
		Party.addShield(Party.activeMember(party), 100, "Flame")
		local taken = Party.damageActive(party, 150, "Flame")
		TestKit.equal(taken, 0, "100 shield x 1.5 covers 150 Flame damage")
	end,

	["healing never passes max hp or raises the downed"] = function()
		local party = newParty()
		local member = Party.activeMember(party)
		member.hp = 900
		TestKit.equal(Party.heal(member, 500), 100)
		member.hp = 0
		TestKit.equal(Party.heal(member, 500), 0)
	end,

	["a downed hero cannot be swapped in and the next one takes the field"] = function()
		local party = newParty()
		local _, down = Party.damageActive(party, 5000)
		TestKit.truthy(down)
		TestKit.truthy(Party.forceNext(party, 10))
		TestKit.equal(party.active, 2)
		TestKit.equal(select(2, Party.trySwap(party, 1, 20, 1)), "down")
	end,

	["the party wipes when nobody is standing"] = function()
		local party = newParty()
		for _, member in party.members do
			member.hp = 0
		end
		TestKit.equal(Party.forceNext(party, 0), false)
		Party.restoreAll(party)
		TestKit.equal(party.members[4].hp, 1000)
	end,
}
