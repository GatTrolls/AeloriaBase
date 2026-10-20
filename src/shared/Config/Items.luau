--!strict
--[[
	Items

	Everything a Starfall pull (or a chest, shop or reward) can hand out: characters and weapons,
	each with a rarity. The repository's ids and names are generic placeholders; the real ones live
	in the game's private content (see Shared.Content). Services only care about the ids, the kind
	and the rarity, so swapping names never touches code.

	Characters that already have a kit use that kit's id (Config/Heroes); the others are roster
	slots waiting for their kits.
]]

local Heroes = require("./Heroes")

export type Kind = "character" | "weapon"

export type Item = {
	id: string,
	kind: Kind,
	rarity: number,
	-- Weapon type for weapons ("sword", "greatsword", "lance", "bow", "focus"); a character's own type.
	weapon: string?,
	-- Shown when the private content has no name for it.
	name: string,
}

local Items = {}

Items.WeaponTypes = table.freeze({ "sword", "greatsword", "lance", "bow", "focus" })

local byId: { [string]: Item } = {}
Items.byId = byId

local function add(id: string, kind: Kind, rarity: number, weapon: string?, name: string): string
	assert(byId[id] == nil, `Items: {id} defined twice`)
	byId[id] = table.freeze({ id = id, kind = kind, rarity = rarity, weapon = weapon, name = name })
	return id
end

local function characters(rarity: number, list: { { string } }): { string }
	local ids = {}
	for _, entry in list do
		table.insert(ids, add(entry[1], "character", rarity, entry[3], entry[2]))
	end
	return ids
end

-- Weapons come in sets with one entry per type, so every character has something to wield.
local TYPE_NAMES = {
	sword = "Blade",
	greatsword = "Greatblade",
	lance = "Spear",
	bow = "Bow",
	focus = "Lens",
}

local function weaponSet(prefix: string, rarity: number, adjectives: { string }): { string }
	local ids = {}
	for index, weaponType in Items.WeaponTypes do
		local adjective = adjectives[index] or adjectives[1]
		table.insert(
			ids,
			add(`{prefix}_{weaponType}`, "weapon", rarity, weaponType, `{adjective} {TYPE_NAMES[weaponType]}`)
		)
	end
	return ids
end

-- Characters ---------------------------------------------------------------------------------------

-- Standard 5-star characters: always on the Everlit Starfall.
Items.StandardFive = table.freeze(characters(5, {
	{ "char_ever_1", "Lantern Warden", "sword" },
	{ "char_ever_2", "Harbour Seer", "focus" },
	{ "char_ever_3", "Bastion Veteran", "greatsword" },
}))

-- Limited 5-star characters: one per Featured Starfall.
Items.LimitedFive = table.freeze(characters(5, {
	{ "char_ltd_1", "Tidecaller", "lance" },
	{ "char_ltd_2", "Cinder Tamer", "focus" },
}))

-- Launch 4-star characters. The three story heroes already have kits.
for _, id in { "hero_tide_healer", "hero_frost_debuffer", "hero_flame_hammer" } do
	local kit = Heroes[id]
	add(id, "character", 4, kit.weapon, kit.displayName)
end
local fourCharacters = { "hero_tide_healer", "hero_frost_debuffer", "hero_flame_hammer" }
for _, id in
	characters(4, {
		{ "char_4_a", "Moss Archer", "bow" },
		{ "char_4_b", "Dune Scout", "lance" },
		{ "char_4_c", "Gale Scribe", "focus" },
		{ "char_4_d", "Ridge Guard", "sword" },
		{ "char_4_e", "Ember Cook", "greatsword" },
	})
do
	table.insert(fourCharacters, id)
end
Items.FourCharacters = table.freeze(fourCharacters)

-- The main character is not on any banner but belongs in the roster.
add("hero_main", "character", 5, "sword", "Wanderer")

-- Weapons -------------------------------------------------------------------------------------------

Items.StandardFiveWeapons =
	table.freeze(weaponSet("wpn5_std", 5, { "Halcyon", "Halcyon", "Halcyon", "Halcyon", "Halcyon" }))
Items.LimitedFiveWeapons = table.freeze({
	add("wpn5_ltd_1", "weapon", 5, "lance", "Tidebreaker Spear"),
	add("wpn5_ltd_2", "weapon", 5, "focus", "Emberheart Lens"),
})
Items.FourWeapons =
	table.freeze(weaponSet("wpn4_a", 4, { "Wayfarer's", "Ironbark", "Stormline", "Hollowreed", "Glasswing" }))
Items.FourWeaponsRateUp = table.freeze({
	Items.FourWeapons[1],
	Items.FourWeapons[2],
	Items.FourWeapons[3],
	Items.FourWeapons[4],
	Items.FourWeapons[5],
})
local threeA = weaponSet("wpn3_a", 3, { "Worn", "Plain", "Cracked", "Frayed", "Dull" })
local threeB = weaponSet("wpn3_b", 3, { "Rusty", "Faded", "Chipped", "Knotted", "Clouded" })
table.move(threeB, 1, #threeB, #threeA + 1, threeA)
Items.ThreeWeapons = table.freeze(threeA)

-- The free Caravan series: one 4-star weapon per type, crafted rather than pulled.
Items.CaravanWeapons = table.freeze(weaponSet("wpn4_caravan", 4, { "Caravan" }))

function Items.get(id: string): Item?
	return byId[id]
end

function Items.isCharacter(id: string): boolean
	local item = byId[id]
	return item ~= nil and item.kind == "character"
end

function Items.rarityOf(id: string): number
	local item = byId[id]
	return if item then item.rarity else 3
end

return Items
