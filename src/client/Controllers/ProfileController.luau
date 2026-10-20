--!strict
--[[
	ProfileController

	The client's copy of the player's profile: currencies, roster, party, quests and settings. The
	server sends a fresh snapshot on load and after every change; screens read from here and
	listen for changes instead of asking the server again.

	  Profile.get()            the latest snapshot, or nil before the first one arrives
	  Profile.waitReady()      yields until there is one
	  Profile.onChanged(fn)    fn(snapshot) now (if loaded) and after every change; returns a
	                           function that stops listening
	  Profile.currency(id)     how many of a currency the player has
	  Profile.dew()            Dew right now, including what has refilled since the snapshot

	The client never writes profile data. Anything that changes it is a request to a service.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Economy = require(ReplicatedStorage.Shared.Config.Economy)
local Net = require(ReplicatedStorage.Shared.Net)

type Snapshot = { [string]: any }

local ProfileController = {}

local snapshot: Snapshot? = nil
local listeners: { (Snapshot) -> () } = {}
local readySignal = Instance.new("BindableEvent")

local function publish(next: Snapshot)
	snapshot = next
	for _, listener in table.clone(listeners) do
		task.spawn(listener, next)
	end
	readySignal:Fire()
end

function ProfileController.get(): Snapshot?
	return snapshot
end

function ProfileController.waitReady(): Snapshot
	while snapshot == nil do
		readySignal.Event:Wait()
	end
	return snapshot :: Snapshot
end

function ProfileController.onChanged(listener: (Snapshot) -> ()): () -> ()
	table.insert(listeners, listener)
	if snapshot then
		task.spawn(listener, snapshot)
	end
	return function()
		local index = table.find(listeners, listener)
		if index then
			table.remove(listeners, index)
		end
	end
end

function ProfileController.currency(id: string): number
	local current = snapshot
	local currencies = current and current.currencies
	return if currencies and currencies[id] then currencies[id] else 0
end

-- Dew refills one point every Economy.Dew.RefillSeconds up to the cap, and spill-over from a
-- full bar fills the reserve. Returns (dew, reserve, secondsToNextPoint).
function ProfileController.dew(): (number, number, number)
	local current = snapshot
	local record = current and current.dew
	if not record then
		return Economy.Dew.Max, 0, 0
	end
	local now = Workspace:GetServerTimeNow()
	local elapsed = math.max(0, now - (record.updatedAt or now))
	local gained = elapsed / Economy.Dew.RefillSeconds
	local value = (record.value or 0) + gained
	local reserve = record.reserve or 0
	if value > Economy.Dew.Max then
		reserve = math.min(Economy.Dew.ReserveMax, reserve + (value - Economy.Dew.Max))
		value = Economy.Dew.Max
	end
	local toNext = if value >= Economy.Dew.Max then 0 else (1 - (value % 1)) * Economy.Dew.RefillSeconds
	return math.floor(value), math.floor(reserve), toNext
end

function ProfileController:Init()
	Net.event(Net.Names.ProfileChanged).OnClientEvent:Connect(publish)
end

function ProfileController:Start()
	local ok, first = pcall(function()
		return Net.func(Net.Names.GetProfile):InvokeServer()
	end)
	if ok and first and not snapshot then
		publish(first)
	end
end

return ProfileController
