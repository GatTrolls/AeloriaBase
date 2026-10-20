--!strict
--[[
	StarfallController

	The client's way to ask the server about Starfall: wishes, Star Pick, token exchange, the
	Armoury target and wish history. Every call returns the server's answer table (`ok`, plus
	`results` or `error`); a lost connection comes back as `{ ok = false, error = "network" }`, so
	screens only ever deal with one shape.

	The client never decides a result. It asks, shows what the server says, and redraws from the
	profile snapshot.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Net = require(ReplicatedStorage.Shared.Net)

type Answer = { [string]: any }

local StarfallController = {}

local function invoke(name: string, ...: any): Answer
	local args = table.pack(...)
	local ok, answer = pcall(function()
		return Net.func(name):InvokeServer(table.unpack(args, 1, args.n))
	end)
	if not ok or type(answer) ~= "table" then
		return { ok = false, error = "network" }
	end
	return answer
end

function StarfallController.pull(bannerId: string, count: number): Answer
	return invoke(Net.Names.RequestPull, bannerId, count)
end

function StarfallController.starPick(bannerId: string, itemId: string): Answer
	return invoke(Net.Names.StarPick, bannerId, itemId)
end

function StarfallController.exchange(currencyId: string, count: number, usePure: boolean?): Answer
	return invoke(Net.Names.ExchangeStars, currencyId, count, usePure == true)
end

function StarfallController.setTarget(itemId: string): Answer
	return invoke(Net.Names.SetArmouryTarget, itemId)
end

function StarfallController.history(offset: number, limit: number): Answer
	return invoke(Net.Names.GetPullHistory, offset, limit)
end

return StarfallController
