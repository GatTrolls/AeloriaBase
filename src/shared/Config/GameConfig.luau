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
		-- The party every player fights with in the combat slice, before rosters are wired in.
		StarterParty = {
			"hero_placeholder_a",
			"hero_placeholder_b",
			"hero_placeholder_c",
			"hero_placeholder_d",
		},
	},

	Gacha = {
		PullCost = 160, -- in wish currency
		MaxPullsPerRequest = 10,
	},

	-- Data every new player starts with.
	DefaultProfile = {
		currencies = {
			gold = 0,
			wishCurrency = 1600, -- earned in game only; see docs/systems/platform-rules.md
			premium = 0, -- bought with Robux
		},
		roster = {},
		inventory = {},
		pity = {},
		flags = {},
	},
}

return GameConfig
