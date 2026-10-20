--!strict
--[[
	Content

	Display names for heroes and enemies. This repository uses placeholder ids and names, so
	nothing unannounced is public. The real names live only in the game's place file, in a
	ModuleScript at ReplicatedStorage.PrivateContent that is not part of the repository:

	  return {
	      heroes = { hero_tide_healer = { displayName = "..." } },
	      enemies = { grunt_melee = { displayName = "..." } },
	  }

	When it is missing (a fresh checkout), the placeholders from Config are shown. The main
	character always shows the player's own display name.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Enemies = require(script.Parent.Config.Enemies)
local Heroes = require(script.Parent.Config.Heroes)
local Items = require(script.Parent.Config.Items)
local Strings = require(script.Parent.Strings)

type Entry = { displayName: string? }
type PrivateContent = {
	heroes: { [string]: Entry }?,
	enemies: { [string]: Entry }?,
	-- Real names for everything else the interface shows: currencies, banners, items, places.
	strings: { [string]: string }?,
	-- How each hero is drawn: { assetId, texture, map, meshName }. See Content.visual.
	visuals: { [string]: { [string]: any } }?,
	-- Any other private tables (quests, dialogue, costumes...) are read through Content.section.
	[string]: any,
}

local Content = {}

local loaded = false
local private: PrivateContent? = nil

local function privateContent(): PrivateContent?
	if not loaded then
		loaded = true
		local module = ReplicatedStorage:FindFirstChild("PrivateContent")
		if module and module:IsA("ModuleScript") then
			local ok, result = pcall(require, module)
			if ok and type(result) == "table" then
				private = result :: any
			else
				warn("[Content] PrivateContent failed to load:", result)
			end
		end
	end
	return private
end

function Content.heroName(heroId: string, player: Player?): string
	if heroId == "hero_main" and player then
		return player.DisplayName
	end
	local content = privateContent()
	local entry = content and content.heroes and content.heroes[heroId]
	if entry and entry.displayName then
		return entry.displayName
	end
	local kit = Heroes[heroId]
	return if kit then kit.displayName else heroId
end

-- A piece of interface text: the private content first, then the generic English in Strings.
function Content.text(key: string): string
	local content = privateContent()
	local override = content and content.strings and content.strings[key]
	if override then
		return override
	end
	return Strings[key] or key
end

-- Fills {name} placeholders in a text key.
function Content.format(key: string, values: { [string]: any }): string
	local text = Content.text(key)
	return (
		string.gsub(text, "{(%w+)}", function(name)
			local value = values[name]
			return if value ~= nil then tostring(value) else "{" .. name .. "}"
		end)
	)
end

-- A whole private table (for example "quests" or "dialogue"), or nil when the place has none.
function Content.section(name: string): any
	local content = privateContent()
	return content and content[name]
end

-- An item shown in the bag or a pull result: weapons, materials, trinkets and unannounced heroes.
function Content.itemName(itemId: string): string
	local content = privateContent()
	local items = content and content.items
	local entry = items and items[itemId]
	if entry and entry.displayName then
		return entry.displayName
	end
	local hero = Heroes[itemId]
	if hero then
		return Content.heroName(itemId, nil)
	end
	local item = Items.get(itemId)
	return Strings["item." .. itemId] or (item and item.name) or itemId
end

-- How a hero is drawn: a skinned model uploaded for the game (asset id, texture, bone map), kept in
-- the private content because it shows unannounced designs. nil means the default body.
function Content.visual(heroId: string): { [string]: any }?
	local content = privateContent()
	local visuals = content and content.visuals
	local entry = visuals and visuals[heroId]
	return if type(entry) == "table" then entry else nil
end

-- Every hero id that has a model, for the server to load.
function Content.visualIds(): { string }
	local content = privateContent()
	local out = {}
	if content and content.visuals then
		for heroId in content.visuals do
			table.insert(out, heroId)
		end
	end
	return out
end

-- An image for an item (a banner splash or card portrait) from the private content, or nil. The
-- repository ships none, so screens fall back to drawn medallions and icons.
function Content.art(itemId: string): string?
	local content = privateContent()
	local art = content and content.art
	local entry = art and art[itemId]
	return if type(entry) == "string" and entry ~= "" then entry else nil
end

function Content.enemyName(enemyId: string): string
	local content = privateContent()
	local entry = content and content.enemies and content.enemies[enemyId]
	if entry and entry.displayName then
		return entry.displayName
	end
	local def = Enemies[enemyId]
	return if def then def.displayName else enemyId
end

return Content
