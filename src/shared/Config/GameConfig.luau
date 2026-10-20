--!strict
-- Game-wide constants. Anything a designer might tune belongs here or in a sibling Config
-- module, never inline in a service.

local GameConfig = {
	-- Bump when the saved data shape changes, and add a step in Data/Migrations.
	DataVersion = 2,
	-- ProfileStore's DataStore, which also handles autosaving. Saves made before session locking
	-- used "PlayerData_v1".
	DataStoreName = "Profiles_v1",

	Party = {
		MaxMembers = 4,
		SwapCooldownSeconds = 1,
		-- The party every player fights with in the combat slice, before rosters are wired in.
		-- The free team every player ends up with: the main character plus the three story heroes.
		StarterParty = {
			"hero_main",
			"hero_tide_healer",
			"hero_frost_debuffer",
			"hero_flame_hammer",
		},
	},

	Gacha = {
		MaxPullsPerRequest = 10,
		-- Pull history is kept for about six months, as the platform rules ask.
		HistoryDays = 183,
		HistoryMaxEntries = 600,
	},

	Travel = {
		-- After using a travel pad, a player can't use another for this long, so arriving on a
		-- pad doesn't bounce them straight back.
		PadCooldownSeconds = 2,
	},

	-- Data every new player starts with. See Config/Economy for what each currency is for.
	DefaultProfile = {
		currencies = {
			glint = 2000,
			starglass = 1600, -- earned in game only; see docs/systems/platform-rules.md
			pureStarglass = 0, -- bought with Robux
			goldStar = 0,
			silverStar = 0,
			moonflakes = 0,
			guildSeals = 0,
		},
		dew = { value = 200, reserve = 0, updatedAt = 0 },
		guild = { rank = 1, exp = 0 },
		-- heroId -> { level, exp, ascension, awakening, friendship, talents }, filled in by
		-- ProgressionService the first time a player joins.
		roster = {},
		party = {},
		weapons = {},
		trinkets = {},
		materials = {},
		pity = {},
		-- Newest last: { at, banner, itemId, rarity }.
		pullHistory = {},
		quests = { active = {}, completed = {}, tracked = "" },
		settings = {
			assist = false,
			textScale = 1,
			reducedMotion = false,
			colorblind = "off",
			musicVolume = 0.7,
			sfxVolume = 0.8,
			hudAutoHide = true,
		},
		flags = {},
	},
}

return GameConfig
