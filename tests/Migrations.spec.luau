--!strict
local Migrations = require("../src/server/Data/Migrations")
local TestKit = require("./TestKit")

local steps = {
	[1] = function(data)
		-- version 1 -> 2: "coins" was renamed to "gold"
		data.gold = data.coins
		data.coins = nil
	end,
	[2] = function(data)
		-- version 2 -> 3: gold moved into a currencies table
		data.currencies = { gold = data.gold }
		data.gold = nil
	end,
}

return {
	["old saves run every step in order"] = function()
		local data: { [string]: any } = { dataVersion = 1, coins = 50 }
		TestKit.equal(Migrations.run(data, 3, steps), 3)
		TestKit.equal(data.currencies.gold, 50)
		TestKit.equal(data.coins, nil)
		TestKit.equal(data.dataVersion, 3)
	end,

	["saves with no version are treated as version 1"] = function()
		local data: { [string]: any } = { coins = 7 }
		Migrations.run(data, 2, steps)
		TestKit.equal(data.gold, 7)
	end,

	["current saves are untouched"] = function()
		local data: { [string]: any } = { dataVersion = 3, currencies = { gold = 1 } }
		TestKit.equal(Migrations.run(data, 3, steps), 3)
		TestKit.equal(data.currencies.gold, 1)
	end,

	["saves from a newer build are left alone"] = function()
		local data: { [string]: any } = { dataVersion = 9 }
		TestKit.equal(Migrations.run(data, 3, steps), 9)
	end,

	["versions with no step just move forward"] = function()
		local data: { [string]: any } = { dataVersion = 1 }
		TestKit.equal(Migrations.run(data, 4, {}), 4)
	end,
}
