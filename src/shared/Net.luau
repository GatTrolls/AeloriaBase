--!strict
--[[
	Net

	One place to create and look up remotes, so names are never typed twice.
	The server creates each remote; clients wait for it.

	Rule: the client asks, the server decides. Never trust a value a client sends
	(damage, currency, rolls, positions) without checking it on the server.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local FOLDER_NAME = "Remotes"

local Net = {}

Net.Names = table.freeze({
	RequestPull = "RequestPull", -- RemoteFunction: (bannerId, count) -> results | error
	GetBannerOdds = "GetBannerOdds", -- RemoteFunction: (bannerId) -> odds table
	ProfileChanged = "ProfileChanged", -- RemoteEvent: server -> client snapshot
})

local function getFolder(): Folder
	local folder = ReplicatedStorage:FindFirstChild(FOLDER_NAME)
	if folder then
		return folder :: Folder
	end
	if RunService:IsServer() then
		local created = Instance.new("Folder")
		created.Name = FOLDER_NAME
		created.Parent = ReplicatedStorage
		return created
	end
	return ReplicatedStorage:WaitForChild(FOLDER_NAME) :: Folder
end

local function get(name: string, className: "RemoteEvent" | "RemoteFunction"): Instance
	local folder = getFolder()
	local existing = folder:FindFirstChild(name)
	if existing then
		return existing
	end
	if RunService:IsServer() then
		local remote = Instance.new(className)
		remote.Name = name
		remote.Parent = folder
		return remote
	end
	return folder:WaitForChild(name)
end

function Net.event(name: string): RemoteEvent
	return get(name, "RemoteEvent") :: RemoteEvent
end

function Net.func(name: string): RemoteFunction
	return get(name, "RemoteFunction") :: RemoteFunction
end

return Net
