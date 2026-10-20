--!strict
--[[
	ClipLibrary

	Finds animation clips by name. Clips are ModuleScripts kept in ReplicatedStorage.PrivateClips
	(authored or captured motion that stays out of the public repository). A clip that is missing
	or fails validation is simply absent, and callers fall back to no animation.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Clip = require(ReplicatedStorage.Shared.Anim.Clip)

local ClipLibrary = {}

local cache: { [string]: Clip.Clip | false } = {}

function ClipLibrary.get(name: string): Clip.Clip?
	local cached = cache[name]
	if cached ~= nil then
		return cached or nil
	end
	local folder = ReplicatedStorage:FindFirstChild("PrivateClips")
	local module = folder and (folder:FindFirstChild(name) or folder:FindFirstChild("00_" .. name))
	if not module or not module:IsA("ModuleScript") then
		cache[name] = false
		return nil
	end
	local ok, clip = pcall(require, module)
	if ok and type(clip) == "table" then
		local problem = Clip.validate(clip :: any)
		if problem == nil then
			cache[name] = clip :: any
			return clip :: any
		end
		warn(`[ClipLibrary] {name} is not a valid clip: {problem}`)
	end
	cache[name] = false
	return nil
end

return ClipLibrary
