--!strict
--[[
	ProgressionService

	Hero growth, server side: every owned hero has a roster entry (the free heroes get theirs the
	first time a player joins), and the Party page asks here to level up, ascend or raise a talent.
	The rules and costs live in Shared.Config.Progression, so the client can show the same numbers
	it is about to be charged; the profile only changes here.

	  Progression remote: (action, heroId, talent?) -> { ok, error? }
	    action: "levelUp" | "ascend" | "talent"
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GameConfig = require(ReplicatedStorage.Shared.Config.GameConfig)
local Heroes = require(ReplicatedStorage.Shared.Config.Heroes)
local Net = require(ReplicatedStorage.Shared.Net)
local Progression = require(ReplicatedStorage.Shared.Config.Progression)
local RateLimit = require(ReplicatedStorage.Shared.RateLimit)

local PlayerDataService = require(script.Parent.PlayerDataService)

local ProgressionService = {}

local limiter = RateLimit.new(8, 12)

local function owns(profile: { [string]: any }, heroId: string): boolean
	if table.find(GameConfig.Party.StarterParty, heroId) then
		return true
	end
	return profile.roster ~= nil and profile.roster[heroId] ~= nil
end

-- The free heroes join the roster on the first visit, so the Party page has something to show.
local function fillStarters(profile: { [string]: any })
	local changed = false
	for _, heroId in GameConfig.Party.StarterParty do
		if not (profile.roster and profile.roster[heroId]) then
			Progression.ensureEntry(profile, heroId)
			changed = true
		end
	end
	return changed
end

local function handle(player: Player, action: unknown, heroId: unknown, talent: unknown): { [string]: any }
	if not RateLimit.allow(limiter, player, os.clock()) then
		return { ok = false, error = "too_fast" }
	end
	if type(action) ~= "string" or type(heroId) ~= "string" or not Heroes[heroId] then
		return { ok = false, error = "bad_request" }
	end
	local profile = PlayerDataService.get(player)
	if not profile then
		return { ok = false, error = "not_loaded" }
	end
	if not owns(profile, heroId) then
		return { ok = false, error = "not_owned" }
	end
	Progression.ensureEntry(profile, heroId)
	local ok, why
	if action == "levelUp" then
		ok, why = Progression.levelUp(profile, heroId)
	elseif action == "ascend" then
		ok, why = Progression.ascend(profile, heroId)
	elseif action == "talent" then
		if type(talent) ~= "string" then
			return { ok = false, error = "bad_request" }
		end
		ok, why = Progression.raiseTalent(profile, heroId, talent)
	else
		return { ok = false, error = "bad_request" }
	end
	if ok then
		PlayerDataService.markChanged(player)
	end
	return { ok = ok, error = why }
end

function ProgressionService:Init()
	Net.func(Net.Names.Progression).OnServerInvoke = handle
end

function ProgressionService:Start()
	local function onPlayerAdded(player: Player)
		local profile = PlayerDataService.waitFor(player)
		if profile and fillStarters(profile) then
			PlayerDataService.markChanged(player)
		end
	end
	for _, player in Players:GetPlayers() do
		task.spawn(onPlayerAdded, player)
	end
	Players.PlayerAdded:Connect(onPlayerAdded)
end

return ProgressionService
