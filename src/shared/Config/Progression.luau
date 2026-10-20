--!strict
--[[
	Progression

	How a hero grows: levels up to a cap set by their ascension, six ascensions that raise the cap,
	three talents from 1 to 10, Awakenings from duplicates and Friendship from time in the party.
	The costs are Glint for now; the material costs from the design plan slot in here later
	without touching the screens or the service, which only ask "can this happen" and "do it".

	Pure Luau: the same functions run on the server (ProgressionService) and in the Party page,
	so what the screen says a step costs is what the server charges.
]]

local Heroes = require("./Heroes")

export type Talent = "basic" | "technique" | "finale"

export type Entry = {
	level: number,
	exp: number,
	ascension: number,
	awakening: number,
	friendship: number,
	talents: { [string]: number },
}

export type Stats = {
	hp: number,
	atk: number,
	def: number,
	critRate: number,
	critDamage: number,
	energy: number,
	synergy: number,
}

local Progression = {}

Progression.MaxLevel = 90
Progression.MaxAscension = 6
Progression.MaxTalent = 10
Progression.MaxFriendship = 10
Progression.Talents = table.freeze({ "basic", "technique", "finale" }) :: { Talent }

-- Level caps by ascension step (0 to 6).
local CAPS = table.freeze({ 20, 40, 50, 60, 70, 80, 90 })

function Progression.cap(ascension: number): number
	return CAPS[math.clamp(math.floor(ascension), 0, Progression.MaxAscension) + 1]
end

-- Glint to go from `level` to the next.
function Progression.levelCost(level: number): number
	return 60 + level * 14 + math.floor(level * level * 0.6)
end

-- Glint for the ascension that follows `ascension`.
function Progression.ascendCost(ascension: number): number
	return 1500 * (ascension + 1)
end

-- Glint to raise a talent from `level` to the next.
function Progression.talentCost(level: number): number
	return 400 + level * 220
end

function Progression.newEntry(): Entry
	return {
		level = 1,
		exp = 0,
		ascension = 0,
		awakening = 0,
		friendship = 0,
		talents = { basic = 1, technique = 1, finale = 1 },
	}
end

-- The roster entry for a hero, made if missing (every owned hero starts at level 1).
function Progression.ensureEntry(profile: { [string]: any }, heroId: string): Entry
	local roster = profile.roster
	if not roster then
		roster = {}
		profile.roster = roster
	end
	local entry = roster[heroId]
	if not entry then
		entry = Progression.newEntry()
		roster[heroId] = entry
	end
	if not entry.talents then
		entry.talents = { basic = 1, technique = 1, finale = 1 }
	end
	return entry
end

function Progression.talentLevel(entry: Entry?, talent: string): number
	local talents = entry and entry.talents
	local level = talents and talents[talent]
	return if type(level) == "number" then level else 1
end

-- Kits list their stats at level 20 with no ascension; everything else scales from there.
function Progression.statMultiplier(level: number, ascension: number): number
	return ((level + 10) / 30) * (1 + 0.08 * ascension)
end

function Progression.stats(kit: Heroes.Kit, entry: Entry?): Stats
	local level = if entry then entry.level else 1
	local ascension = if entry then entry.ascension else 0
	local m = Progression.statMultiplier(level, ascension)
	local base = kit.stats
	return {
		hp = math.floor(base.maxHp * m),
		atk = math.floor(base.attack * m),
		def = math.floor(base.defense * m),
		critRate = base.critRate,
		critDamage = base.critDamage,
		energy = 1 + 0.02 * ascension,
		synergy = 0.05 * ascension,
	}
end

local function glint(profile: { [string]: any }): number
	local currencies = profile.currencies
	return if currencies and type(currencies.glint) == "number" then currencies.glint else 0
end

local function spend(profile: { [string]: any }, amount: number)
	profile.currencies.glint -= amount
end

-- Why a level-up can't happen, or nil when it can.
function Progression.levelBlock(profile: { [string]: any }, heroId: string): string?
	local entry = profile.roster and profile.roster[heroId]
	if not entry then
		return "not_owned"
	end
	if entry.level >= Progression.cap(entry.ascension) then
		return if entry.ascension >= Progression.MaxAscension then "max_level" else "needs_ascension"
	end
	if glint(profile) < Progression.levelCost(entry.level) then
		return "not_enough_glint"
	end
	return nil
end

function Progression.levelUp(profile: { [string]: any }, heroId: string): (boolean, string?)
	local block = Progression.levelBlock(profile, heroId)
	if block then
		return false, block
	end
	local entry = profile.roster[heroId]
	spend(profile, Progression.levelCost(entry.level))
	entry.level += 1
	return true, nil
end

function Progression.ascendBlock(profile: { [string]: any }, heroId: string): string?
	local entry = profile.roster and profile.roster[heroId]
	if not entry then
		return "not_owned"
	end
	if entry.ascension >= Progression.MaxAscension then
		return "max_ascension"
	end
	if entry.level < Progression.cap(entry.ascension) then
		return "needs_level"
	end
	if glint(profile) < Progression.ascendCost(entry.ascension) then
		return "not_enough_glint"
	end
	return nil
end

function Progression.ascend(profile: { [string]: any }, heroId: string): (boolean, string?)
	local block = Progression.ascendBlock(profile, heroId)
	if block then
		return false, block
	end
	local entry = profile.roster[heroId]
	spend(profile, Progression.ascendCost(entry.ascension))
	entry.ascension += 1
	return true, nil
end

function Progression.talentBlock(profile: { [string]: any }, heroId: string, talent: string): string?
	if not table.find(Progression.Talents, talent) then
		return "bad_talent"
	end
	local entry = profile.roster and profile.roster[heroId]
	if not entry then
		return "not_owned"
	end
	local level = Progression.talentLevel(entry, talent)
	if level >= Progression.MaxTalent then
		return "max_talent"
	end
	if glint(profile) < Progression.talentCost(level) then
		return "not_enough_glint"
	end
	return nil
end

function Progression.raiseTalent(
	profile: { [string]: any },
	heroId: string,
	talent: string
): (boolean, string?)
	local block = Progression.talentBlock(profile, heroId, talent)
	if block then
		return false, block
	end
	local entry = profile.roster[heroId]
	if not entry.talents then
		entry.talents = { basic = 1, technique = 1, finale = 1 }
	end
	local level = Progression.talentLevel(entry, talent)
	spend(profile, Progression.talentCost(level))
	entry.talents[talent] = level + 1
	return true, nil
end

return Progression
