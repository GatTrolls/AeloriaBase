--!strict
--[[
	SettingsService

	Player preferences (Assist mode, text size, reduced motion, colour-blind mode, volumes, HUD
	auto-hide). They live in the profile so they follow the player, and the client changes them by
	asking here; every value is checked against a small schema so a bad request can't store
	nonsense. Assist mode also feeds the combat timing windows through ActionLog.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Net = require(ReplicatedStorage.Shared.Net)

local ActionLog = require(script.Parent.Parent.Combat.ActionLog)
local PlayerDataService = require(script.Parent.PlayerDataService)

type Rule =
	{ kind: "boolean" }
	| { kind: "number", min: number, max: number }
	| { kind: "enum", values: { string } }

local RULES: { [string]: Rule } = {
	assist = { kind = "boolean" },
	textScale = { kind = "number", min = 0.8, max = 1.4 },
	reducedMotion = { kind = "boolean" },
	colorblind = { kind = "enum", values = { "off", "deuteranopia", "protanopia", "tritanopia" } },
	musicVolume = { kind = "number", min = 0, max = 1 },
	sfxVolume = { kind = "number", min = 0, max = 1 },
	hudAutoHide = { kind = "boolean" },
}

local SettingsService = {}

local function valid(rule: Rule, value: unknown): (boolean, any)
	if rule.kind == "boolean" then
		return type(value) == "boolean", value
	elseif rule.kind == "number" then
		if type(value) ~= "number" or value ~= value then
			return false, nil
		end
		return true, math.clamp(value, rule.min, rule.max)
	end
	return type(value) == "string" and table.find(rule.values, value) ~= nil, value
end

-- Applies the settings that change gameplay, so the server never trusts the client for them.
local function applyToGameplay(player: Player, settings: { [string]: any })
	ActionLog.get(player).assist = settings.assist == true
end

local function handleSet(player: Player, key: unknown, value: unknown)
	if type(key) ~= "string" then
		return { ok = false, error = "bad_request" }
	end
	local rule = RULES[key]
	if not rule then
		return { ok = false, error = "unknown_setting" }
	end
	local ok, clean = valid(rule, value)
	if not ok then
		return { ok = false, error = "bad_value" }
	end
	local profile = PlayerDataService.get(player)
	if not profile then
		return { ok = false, error = "not_loaded" }
	end
	profile.settings[key] = clean
	applyToGameplay(player, profile.settings)
	PlayerDataService.markChanged(player)
	return { ok = true, value = clean }
end

function SettingsService:Init()
	Net.func(Net.Names.SetSetting).OnServerInvoke = handleSet
end

function SettingsService:Start()
	game:GetService("Players").PlayerAdded:Connect(function(player)
		task.spawn(function()
			local profile = PlayerDataService.waitFor(player)
			if profile then
				applyToGameplay(player, profile.settings)
			end
		end)
	end)
	for _, player in game:GetService("Players"):GetPlayers() do
		task.spawn(function()
			local profile = PlayerDataService.waitFor(player)
			if profile then
				applyToGameplay(player, profile.settings)
			end
		end)
	end
end

return SettingsService
