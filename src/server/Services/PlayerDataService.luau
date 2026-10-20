--!strict
--[[
	PlayerDataService

	Loads, session-locks, upgrades and saves each player's profile with ProfileStore.

	  * Session locking: a profile is open on one server at a time, so a player who hops servers
	    quickly can never duplicate or roll back anything. If another server takes the session,
	    this server lets go and asks the player to rejoin.
	  * Autosave and a final save on leave and shutdown are handled by ProfileStore.
	  * Reconcile: fields added to GameConfig.DefaultProfile appear in old saves automatically.
	  * Migrations: Data/Migrations upgrades saves from older data versions, one step at a time.
	  * The player's UserId is attached to their profile so data requests can be honoured.

	Without API access (a fresh Studio place) or without the ProfileStore package installed, the
	service falls back to temporary profiles and says so in the output, so play-testing still works.

	Other services use `get` and `waitFor`; neither changed when the storage moved to ProfileStore.

	The player's own view of their profile (currencies, roster, quests, settings) is sent to their
	client as a snapshot on load and after every change. Services that change the profile call
	`markChanged(player)`, which batches changes made in the same moment into one message.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local GameConfig = require(ReplicatedStorage.Shared.Config.GameConfig)
local Migrations = require(script.Parent.Parent.Data.Migrations)
local Net = require(ReplicatedStorage.Shared.Net)

type Profile = {
	Data: { [string]: any },
	OnSessionEnd: { Connect: (self: any, () -> ()) -> any },
	Reconcile: (self: any) -> (),
	EndSession: (self: any) -> (),
	AddUserId: (self: any, number) -> (),
}

local PlayerDataService = {}

local store: any = nil
local profiles: { [Player]: Profile } = {}
local temporary: { [Player]: { [string]: any } } = {}
local loadedSignals: { [Player]: BindableEvent } = {}
local changedPending: { [Player]: boolean } = {}
local changedRemote: RemoteEvent

local function deepCopy<T>(value: T): T
	if type(value) ~= "table" then
		return value
	end
	local copy = {}
	for key, inner in value :: any do
		copy[key] = deepCopy(inner)
	end
	return copy :: any
end

local function keyFor(player: Player): string
	return `player_{player.UserId}`
end

-- What the client may see: everything except the long pull history, of which only the length is
-- sent (the client asks for pages of it when it opens the history tab).
local function buildSnapshot(data: { [string]: any }): { [string]: any }
	local snapshot: { [string]: any } = {}
	for key, value in data do
		if key ~= "pullHistory" then
			snapshot[key] = deepCopy(value)
		end
	end
	snapshot.pullHistoryCount = #(data.pullHistory or {})
	snapshot.serverTime = workspace:GetServerTimeNow()
	return snapshot
end

local function finishLoading(player: Player)
	local signal = loadedSignals[player]
	if signal then
		signal:Fire()
	end
	task.defer(function()
		PlayerDataService.markChanged(player)
	end)
end

local function loadProfile(player: Player)
	if not store then
		local data = deepCopy(GameConfig.DefaultProfile) :: { [string]: any }
		data.dataVersion = GameConfig.DataVersion
		temporary[player] = data
		finishLoading(player)
		return
	end

	local profile = store:StartSessionAsync(keyFor(player), {
		Cancel = function()
			return player.Parent ~= Players
		end,
	}) :: Profile?

	if not profile then
		-- Another server held the session and wouldn't let go, or the DataStore is down.
		player:Kick("We couldn't load your save. Please rejoin in a minute.")
		return
	end

	profile:AddUserId(player.UserId)
	profile:Reconcile()
	Migrations.run(profile.Data, GameConfig.DataVersion)

	profile.OnSessionEnd:Connect(function()
		profiles[player] = nil
		player:Kick("Your save was opened on another server. Please rejoin.")
	end)

	if player.Parent == Players then
		profiles[player] = profile
		finishLoading(player)
	else
		-- Left while loading.
		profile:EndSession()
	end
end

-- Returns the live profile data table, or nil if it has not loaded yet. Changes to it are saved.
function PlayerDataService.get(player: Player): { [string]: any }?
	local profile = profiles[player]
	if profile then
		return profile.Data
	end
	return temporary[player]
end

-- Yields until the player's profile has loaded. Returns nil if they leave first.
function PlayerDataService.waitFor(player: Player): { [string]: any }?
	local data = PlayerDataService.get(player)
	if data then
		return data
	end
	local signal = loadedSignals[player]
	if not signal then
		return nil
	end
	signal.Event:Wait()
	return PlayerDataService.get(player)
end

-- The snapshot the player's client sees, or nil before the profile has loaded.
function PlayerDataService.snapshot(player: Player): { [string]: any }?
	local data = PlayerDataService.get(player)
	return data and buildSnapshot(data)
end

-- Tells the player's client their profile changed. Many calls in one frame send one message.
function PlayerDataService.markChanged(player: Player)
	if changedPending[player] or not changedRemote then
		return
	end
	changedPending[player] = true
	task.defer(function()
		changedPending[player] = nil
		if player.Parent ~= Players then
			return
		end
		local snapshot = PlayerDataService.snapshot(player)
		if snapshot then
			changedRemote:FireClient(player, snapshot)
		end
	end)
end

function PlayerDataService:Init()
	changedRemote = Net.event(Net.Names.ProfileChanged)
	Net.func(Net.Names.GetProfile).OnServerInvoke = function(player: Player)
		return PlayerDataService.waitFor(player) and PlayerDataService.snapshot(player)
	end
	local packages = ServerScriptService:FindFirstChild("ServerPackages")
	local module = packages and packages:FindFirstChild("ProfileStore")
	if not module then
		warn("[PlayerData] ProfileStore is not installed (run `wally install`); using temporary profiles")
		return
	end
	local ok, result = pcall(function()
		local ProfileStore = (require :: any)(module)
		return ProfileStore.New(GameConfig.DataStoreName, GameConfig.DefaultProfile)
	end)
	if ok then
		store = result
	else
		warn("[PlayerData] ProfileStore failed to start, using temporary profiles:", result)
	end
end

function PlayerDataService:Start()
	local function onPlayerAdded(player: Player)
		loadedSignals[player] = Instance.new("BindableEvent")
		loadProfile(player)
	end

	Players.PlayerAdded:Connect(onPlayerAdded)
	for _, player in Players:GetPlayers() do
		task.spawn(onPlayerAdded, player)
	end

	Players.PlayerRemoving:Connect(function(player)
		changedPending[player] = nil
		local profile = profiles[player]
		profiles[player] = nil
		temporary[player] = nil
		if profile then
			profile:EndSession()
		end
		local signal = loadedSignals[player]
		loadedSignals[player] = nil
		if signal then
			signal:Fire()
			signal:Destroy()
		end
	end)
end

return PlayerDataService
