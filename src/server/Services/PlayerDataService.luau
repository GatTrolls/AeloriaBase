--!strict
--[[
	PlayerDataService

	Loads, caches and saves each player's profile.

	This is a starter implementation: retries, autosave and a final save on shutdown.
	It does NOT session-lock, so a player who rejoins quickly on another server can in
	rare cases overwrite newer data. Replace the storage layer with ProfileStore before
	the closed alpha (tracked in ROADMAP.md, milestone M2). The public API below should
	stay the same when that happens.
]]

local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local GameConfig = require(game:GetService("ReplicatedStorage").Shared.Config.GameConfig)

local MAX_ATTEMPTS = 5

local PlayerDataService = {}

local store: DataStore? = nil
local profiles: { [Player]: { [string]: any } } = {}
local loadedSignals: { [Player]: BindableEvent } = {}

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

-- Fill in any keys added to DefaultProfile since this player last saved.
local function reconcile(target: { [string]: any }, template: { [string]: any })
	for key, value in template do
		if target[key] == nil then
			target[key] = deepCopy(value)
		elseif type(value) == "table" and type(target[key]) == "table" then
			reconcile(target[key], value)
		end
	end
end

local function withRetries<T>(label: string, callback: () -> T): (boolean, T?)
	for attempt = 1, MAX_ATTEMPTS do
		local ok, result = pcall(callback)
		if ok then
			return true, result
		end
		warn(`[PlayerData] {label} failed (attempt {attempt}): {result}`)
		task.wait(2 ^ attempt)
	end
	return false, nil
end

local function keyFor(player: Player): string
	return `player_{player.UserId}`
end

local function load(player: Player)
	local data: { [string]: any }? = nil
	if store then
		local ok, result = withRetries(`load {player.UserId}`, function()
			return (store :: DataStore):GetAsync(keyFor(player))
		end)
		if not ok then
			player:Kick("We couldn't load your save. Please rejoin in a minute.")
			return
		end
		data = result
	end

	local profile = data or deepCopy(GameConfig.DefaultProfile)
	reconcile(profile, GameConfig.DefaultProfile)
	profile.dataVersion = GameConfig.DataVersion

	if player.Parent then
		profiles[player] = profile
		local signal = loadedSignals[player]
		if signal then
			signal:Fire()
		end
	end
end

local function save(player: Player)
	local profile = profiles[player]
	if not profile or not store then
		return
	end
	withRetries(`save {player.UserId}`, function()
		(store :: DataStore):UpdateAsync(keyFor(player), function()
			return profile
		end)
	end)
end

-- Returns the live profile table, or nil if it has not loaded yet.
function PlayerDataService.get(player: Player): { [string]: any }?
	return profiles[player]
end

-- Yields until the player's profile has loaded. Returns nil if they leave first.
function PlayerDataService.waitFor(player: Player): { [string]: any }?
	if profiles[player] then
		return profiles[player]
	end
	local signal = loadedSignals[player]
	if not signal then
		return nil
	end
	signal.Event:Wait()
	return profiles[player]
end

function PlayerDataService:Init()
	-- DataStores only work in Studio when "Enable Studio Access to API Services" is on.
	local ok, result = pcall(DataStoreService.GetDataStore, DataStoreService, GameConfig.DataStoreName)
	if ok then
		store = result
	else
		warn("[PlayerData] DataStores unavailable, using temporary profiles:", result)
	end
end

function PlayerDataService:Start()
	local function onPlayerAdded(player: Player)
		loadedSignals[player] = Instance.new("BindableEvent")
		load(player)
	end

	Players.PlayerAdded:Connect(onPlayerAdded)
	for _, player in Players:GetPlayers() do
		task.spawn(onPlayerAdded, player)
	end

	Players.PlayerRemoving:Connect(function(player)
		save(player)
		profiles[player] = nil
		local signal = loadedSignals[player]
		loadedSignals[player] = nil
		if signal then
			signal:Fire()
			signal:Destroy()
		end
	end)

	task.spawn(function()
		while true do
			task.wait(GameConfig.AutosaveSeconds)
			for player in profiles do
				task.spawn(save, player)
			end
		end
	end)

	game:BindToClose(function()
		if RunService:IsStudio() and not store then
			return
		end
		local pending = 0
		for player in profiles do
			pending += 1
			task.spawn(function()
				save(player)
				pending -= 1
			end)
		end
		while pending > 0 do
			task.wait()
		end
	end)
end

return PlayerDataService
