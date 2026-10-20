--!strict
-- Game-wide constants. Anything a designer might tune belongs here or in a sibling Config
-- module, never inline in a service.

local GameConfig = {
	-- Bump when the saved data shape changes, and add a migration in PlayerDataService.
	DataVersion = 1,
	DataStoreName = "PlayerData_v1",
	AutosaveSeconds = 120,

	Party = {
		MaxMembers = 4,
		SwapCooldownSeconds = 1,
	},

	Gacha = {
		PullCost = 160, -- in wish currency
		MaxPullsPerRequest = 10,
	},

	-- Data every new player starts with.
	DefaultProfile = {
		currencies = {
			gold = 0,
			wishCurrency = 1600, -- earned in game only; see docs/operations/compliance.md
			premium = 0, -- bought with Robux
		},
		roster = {},
		inventory = {},
		pity = {},
		flags = {},
	},
}

return GameConfig
