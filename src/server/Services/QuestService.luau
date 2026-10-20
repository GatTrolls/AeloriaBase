--!strict
--[[
	QuestService

	The quest log on the server. The profile's `quests` table is the truth; clients report what
	they did through QuestEvent (talk, reach, interact) and ask to track a quest, and the server
	validates the shape, advances the log with Shared.Config.Quests and pays rewards when a quest
	completes. Combat reports kills through QuestService.report so a client can never claim one.

	  QuestEvent (client -> server): (kind, target) or ("track", questId)
	  QuestState (server -> client): { quests = profile.quests, finished = { questId }, started = { questId } }
	  QuestService.report(player, kind, target, amount?)  for server-side events (kills)
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Net = require(ReplicatedStorage.Shared.Net)
local Quests = require(ReplicatedStorage.Shared.Config.Quests)
local RateLimit = require(ReplicatedStorage.Shared.RateLimit)

local PlayerDataService = require(script.Parent.PlayerDataService)

local QuestService = {}

local limiter = RateLimit.new(4, 8)
local stateRemote: RemoteEvent
-- Events a client may report itself; kills and anything combat-related must come from the server.
local CLIENT_KINDS = { talk = true, reach = true, interact = true }

local function pay(profile: { [string]: any }, questId: string)
	local quest = Quests.get(questId)
	if not quest then
		return
	end
	local currencies = profile.currencies
	for currency, amount in quest.reward do
		if currency ~= "exp" and type(amount) == "number" and currencies[currency] ~= nil then
			currencies[currency] += amount
		end
	end
end

local function push(player: Player, profile: { [string]: any }, started: { string }, finished: { string })
	stateRemote:FireClient(player, { quests = profile.quests, started = started, finished = finished })
	PlayerDataService.markChanged(player)
end

function QuestService.report(player: Player, kind: string, target: string, amount: number?)
	local profile = PlayerDataService.get(player)
	if not profile then
		return
	end
	local state = Quests.normalize(profile.quests)
	profile.quests = state
	local before = {}
	for id in state.active do
		before[id] = true
	end
	local result = Quests.report(state, kind, target, amount)
	if #result.advanced == 0 then
		return
	end
	for _, id in result.completed do
		pay(profile, id)
	end
	local started = {}
	for id in state.active do
		if not before[id] then
			table.insert(started, id)
		end
	end
	push(player, profile, started, result.completed)
end

local function onEvent(player: Player, kind: unknown, target: unknown)
	if
		not RateLimit.allow(limiter, player, os.clock())
		or type(kind) ~= "string"
		or type(target) ~= "string"
	then
		return
	end
	if kind == "track" then
		local profile = PlayerDataService.get(player)
		if profile and Quests.track(Quests.normalize(profile.quests), target) then
			push(player, profile, {}, {})
		end
		return
	end
	if CLIENT_KINDS[kind] then
		QuestService.report(player, kind, target, 1)
	end
end

function QuestService:Init()
	stateRemote = Net.event(Net.Names.QuestState)
	Net.event(Net.Names.QuestEvent).OnServerEvent:Connect(onEvent)
end

function QuestService:Start()
	local function onPlayerAdded(player: Player)
		local profile = PlayerDataService.waitFor(player)
		if not profile then
			return
		end
		local state = Quests.normalize(profile.quests)
		profile.quests = state
		if #Quests.unlock(state) > 0 then
			PlayerDataService.markChanged(player)
		end
	end
	for _, player in Players:GetPlayers() do
		task.spawn(onPlayerAdded, player)
	end
	Players.PlayerAdded:Connect(onPlayerAdded)
end

return QuestService
