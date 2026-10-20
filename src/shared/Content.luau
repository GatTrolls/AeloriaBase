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

type Entry = { displayName: string? }
type PrivateContent = {
	heroes: { [string]: Entry }?,
	enemies: { [string]: Entry }?,
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
