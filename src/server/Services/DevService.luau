--!strict
--[[
	DevService

	Studio-only test commands for designers, exposed as a BindableFunction at
	ServerStorage.DevCommands so they can be run from the command bar during a playtest:

	  local dev = game.ServerStorage.DevCommands
	  dev:Invoke("spawn", 5)          -- spawn five more grunts around the arena centre
	  dev:Invoke("spawn", 1, "elite_brute") -- or any enemy id from Config/Enemies
	  dev:Invoke("party")             -- print every player's party HP, energy and active hero
	  dev:Invoke("restore")           -- refill every party
	  dev:Invoke("energy")            -- fill every hero's Finale energy
	  dev:Invoke("hurt", 500)         -- damage each active hero (tests downed heroes and wipes)
	  dev:Invoke("enemies")           -- list enemies with HP, status, effects, Composure and state

	Nothing here exists in a live server.
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ServerStorage = game:GetService("ServerStorage")
local Workspace = game:GetService("Workspace")

local Elements = require(game:GetService("ReplicatedStorage").Shared.Elements)
local EnemyService = require(script.Parent.EnemyService)
local PartyService = require(script.Parent.PartyService)

local DevService = {}

local commands: { [string]: (...any) -> any } = {}

function commands.spawn(count: number?, enemyId: string?)
	local total = math.clamp(count or 1, 1, 30)
	for index = 1, total do
		local angle = index / total * math.pi * 2
		local position = Vector3.new(math.cos(angle) * 15, 0.6, 10 + math.sin(angle) * 15)
		EnemyService.spawn(enemyId or "grunt_melee", CFrame.new(position))
	end
	return `spawned {total}`
end

function commands.party()
	local lines = {}
	for _, player in Players:GetPlayers() do
		local record = PartyService.get(player)
		if record then
			for slot, member in record.party.members do
				local ability = record.abilities[member.heroId]
				table.insert(
					lines,
					string.format(
						"%s%d %s hp=%d/%d shield=%d energy=%d infused=%d",
						if slot == record.party.active then "*" else " ",
						slot,
						member.heroId,
						member.hp,
						member.maxHp,
						member.shield,
						ability.energy,
						ability.infusedHits
					)
				)
			end
		end
	end
	return table.concat(lines, "\n")
end

function commands.restore()
	for _, player in Players:GetPlayers() do
		local record = PartyService.get(player)
		if record then
			for _, member in record.party.members do
				member.hp = member.maxHp
			end
			PartyService.damage(player, 0)
		end
	end
	return "restored"
end

-- Fills every hero's Finale energy.
function commands.energy()
	for _, player in Players:GetPlayers() do
		PartyService.addEnergy(player, math.huge)
		PartyService.pushState(player)
	end
	return "energy full"
end

-- Damages each player's active hero, to test downed heroes and party wipes.
function commands.hurt(amount: number?)
	for _, player in Players:GetPlayers() do
		PartyService.damage(player, amount or 500)
	end
	return "hurt"
end

function commands.enemies()
	local now = Workspace:GetServerTimeNow()
	local lines = {}
	for index, enemy in EnemyService.getAll() do
		local effects = {}
		for id, endsAt in enemy.elements.effects do
			if endsAt > now then
				table.insert(effects, id)
			end
		end
		table.insert(
			lines,
			string.format(
				"%d %s hp=%d status=%s effects=%s composure=%d state=%s",
				index,
				enemy.def.id,
				enemy.hp,
				Elements.statusOf(enemy.elements, now) or "",
				table.concat(effects, ","),
				enemy.brain.composure,
				enemy.brain.state
			)
		)
	end
	return table.concat(lines, "\n")
end

function DevService:Init()
	if not RunService:IsStudio() then
		return
	end
	local remote = Instance.new("BindableFunction")
	remote.Name = "DevCommands"
	remote.OnInvoke = function(name: string, ...)
		local command = commands[name]
		if not command then
			return `unknown command {name}`
		end
		return command(...)
	end
	remote.Parent = ServerStorage
end

return DevService
