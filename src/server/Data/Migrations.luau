--!strict
--[[
	Migrations

	Upgrades old saves to the current data shape, one version at a time. Pure Luau with no Roblox
	APIs; covered by tests/Migrations.spec.luau.

	When the saved data shape changes:
	  1. Bump GameConfig.DataVersion.
	  2. Add a step here keyed by the version it upgrades FROM, which edits the data in place.
	New fields with defaults don't need a step: PlayerDataService fills them in from
	GameConfig.DefaultProfile. Steps are for renames, moves and changed meanings.
]]

export type Step = (data: { [string]: any }) -> ()

local Migrations = {}

-- [from version] = step that turns a version `from` save into version `from + 1`.
Migrations.steps = {
	-- 1 -> 2: the economy got its real currencies, and pulls moved out of a flat inventory into the
	-- roster, weapons and pull history. Starter-build placeholder pulls are dropped.
	[1] = function(data)
		local old = if type(data.currencies) == "table" then data.currencies else {}
		data.currencies = {
			glint = old.gold or 0,
			starglass = old.wishCurrency or 0,
			pureStarglass = old.premium or 0,
			goldStar = 0,
			silverStar = 0,
			moonflakes = 0,
			guildSeals = 0,
		}
		data.inventory = nil
		data.pity = {}
	end,
} :: { [number]: Step }

-- Runs every step from the save's version up to `target`. Saves with no version are treated as
-- version 1. Returns the version the data ended at; a save newer than `target` is left alone.
function Migrations.run(data: { [string]: any }, target: number, steps: { [number]: Step }?): number
	local list = steps or Migrations.steps
	local version = if type(data.dataVersion) == "number" then data.dataVersion else 1
	while version < target do
		local step = list[version]
		if step then
			step(data)
		end
		version += 1
		data.dataVersion = version
	end
	return version
end

return Migrations
