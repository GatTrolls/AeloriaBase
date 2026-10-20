--!strict
--[[
	MovementService

	The server side of sprint, dodge, climb, glide and plunges. The client moves its own
	character for responsiveness, but everything that matters is decided here:

	  * Grip (stamina) lives on the server (Shared.Combat.Stamina), worked out from timestamps.
	  * Sprint speed is only ever set by the server.
	  * Dodges follow Shared.Combat.Defense: three in a row, then a short cooldown. Each accepted
	    dodge is logged, and enemy strikes judge evasion, Slips and Covers from that log.
	  * When Grip runs out the server ends the activity and tells the client.
	  * Recent heights are kept so a plunge can be checked against a real fall.

	It also samples each character's speed and logs anyone who keeps moving faster than any
	legitimate movement allows, for review rather than automatic punishment.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage.Shared
local CombatConfig = require(Shared.Config.CombatConfig)
local Defense = require(Shared.Combat.Defense)
local Net = require(Shared.Net)
local RateLimit = require(Shared.RateLimit)
local Stamina = require(Shared.Combat.Stamina)

local ActionLog = require(script.Parent.Parent.Combat.ActionLog)

type PlayerState = {
	stamina: Stamina.State,
	dodge: Defense.DodgeState,
	lastSentValue: number,
	lastSample: Vector3?,
	strikes: number,
	-- Root heights sampled ten times a second, newest last.
	heights: { { at: number, y: number } },
}

local MovementService = {}

local Movement = CombatConfig.Movement
local StaminaConfig = CombatConfig.Stamina
local HEIGHT_HISTORY_SECONDS = 2

local states: { [Player]: PlayerState } = {}
local limiter = RateLimit.new(CombatConfig.RateLimits.MoveIntent)
local stateRemote: RemoteEvent

local function now(): number
	return Workspace:GetServerTimeNow()
end

local function rootOf(player: Player): BasePart?
	local character = player.Character
	return character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
end

local function humanoidOf(player: Player): Humanoid?
	local character = player.Character
	return character and character:FindFirstChildOfClass("Humanoid")
end

local function send(player: Player, state: PlayerState, extra: { [string]: any }?)
	local message = extra or {}
	message.stamina = state.stamina.value
	message.max = StaminaConfig.Max
	message.activity = state.stamina.activity
	state.lastSentValue = state.stamina.value
	-- Other players' clients animate this player's body from it (climbing, gliding).
	local character = player.Character
	if character then
		character:SetAttribute("Activity", state.stamina.activity)
	end
	stateRemote:FireClient(player, message)
end

local function setSprintSpeed(player: Player, sprinting: boolean)
	local humanoid = humanoidOf(player)
	if humanoid then
		humanoid.WalkSpeed = if sprinting then Movement.SprintSpeed else Movement.WalkSpeed
	end
end

-- How far the player has fallen within the last `seconds`: the highest recent root height
-- minus the current one.
function MovementService.recentDrop(player: Player, seconds: number): number
	local state = states[player]
	local root = rootOf(player)
	if not state or not root then
		return 0
	end
	local since = now() - seconds
	local peak = root.Position.Y
	for _, sample in state.heights do
		if sample.at >= since then
			peak = math.max(peak, sample.y)
		end
	end
	return peak - root.Position.Y
end

local function onIntent(player: Player, intent: unknown, on: unknown)
	local state = states[player]
	if not state or type(intent) ~= "string" then
		return
	end
	local t = now()
	if not RateLimit.allow(limiter, player, t) then
		return
	end
	local humanoid = humanoidOf(player)
	if not humanoid or humanoid.Health <= 0 then
		return
	end

	if intent == "dodge" then
		if Defense.tryDodge(state.dodge, t) then
			ActionLog.get(player).lastDodgeAt = t
			send(player, state, { dodge = true, charges = Defense.chargesLeft(state.dodge, t) })
		else
			send(player, state, { denied = "dodge", charges = Defense.chargesLeft(state.dodge, t) })
		end
		return
	end

	if intent == "leap" then
		local ok = state.stamina.activity == "climb"
			and Stamina.spend(state.stamina, StaminaConfig.ClimbLeapCost, t)
		send(player, state, if ok then nil else { denied = "leap" })
		return
	end

	if not Stamina.isActivity(intent) or type(on) ~= "boolean" then
		return
	end

	if on then
		local ok = Stamina.setActivity(state.stamina, intent :: Stamina.Activity, t)
		setSprintSpeed(player, ok and intent == "sprint")
		send(player, state, if ok then nil else { denied = intent })
	elseif state.stamina.activity == intent then
		Stamina.setActivity(state.stamina, "none", t)
		setSprintSpeed(player, false)
		send(player, state)
	end
end

local function tick()
	local t = now()
	for player, state in states do
		if Stamina.update(state.stamina, t) then
			setSprintSpeed(player, false)
			send(player, state, { exhausted = true })
		else
			local value = state.stamina.value
			local reachedFull = value >= StaminaConfig.Max and state.lastSentValue < StaminaConfig.Max
			if reachedFull or math.abs(value - state.lastSentValue) >= 2 then
				send(player, state)
			end
		end

		local root = rootOf(player)
		if root then
			table.insert(state.heights, { at = t, y = root.Position.Y })
			while state.heights[1] and t - state.heights[1].at > HEIGHT_HISTORY_SECONDS do
				table.remove(state.heights, 1)
			end
		end
	end
end

-- Logs characters that keep moving faster than anything in the game allows.
local function sampleSpeeds(interval: number)
	for player, state in states do
		local root = rootOf(player)
		if root then
			local position = root.Position * Vector3.new(1, 0, 1)
			local last = state.lastSample
			state.lastSample = position
			if last and (position - last).Magnitude / interval > Movement.SuspiciousSpeed then
				state.strikes += 1
				if state.strikes >= 3 then
					warn(`[Movement] {player.UserId} moved faster than allowed for {state.strikes} samples`)
				end
			else
				state.strikes = 0
			end
		end
	end
end

function MovementService:Init()
	stateRemote = Net.event(Net.Names.MoveState)
	Net.event(Net.Names.MoveIntent).OnServerEvent:Connect(onIntent)
end

function MovementService:Start()
	local function onPlayerAdded(player: Player)
		local state: PlayerState = {
			stamina = Stamina.new(now()),
			dodge = Defense.newDodge(),
			lastSentValue = StaminaConfig.Max,
			lastSample = nil,
			strikes = 0,
			heights = {},
		}
		states[player] = state
		player.CharacterAdded:Connect(function(character)
			local humanoid = character:WaitForChild("Humanoid") :: Humanoid
			humanoid.WalkSpeed = Movement.WalkSpeed
			Stamina.setActivity(state.stamina, "none", now())
			state.lastSample = nil
			table.clear(state.heights)
			send(player, state)
		end)
	end
	Players.PlayerAdded:Connect(onPlayerAdded)
	for _, player in Players:GetPlayers() do
		onPlayerAdded(player)
	end
	Players.PlayerRemoving:Connect(function(player)
		states[player] = nil
		RateLimit.forget(limiter, player)
		ActionLog.forget(player)
	end)

	local tickAccumulator, sampleAccumulator = 0, 0
	RunService.Heartbeat:Connect(function(dt)
		tickAccumulator += dt
		sampleAccumulator += dt
		if tickAccumulator >= 0.1 then
			tickAccumulator = 0
			tick()
		end
		if sampleAccumulator >= 1 then
			sampleSpeeds(sampleAccumulator)
			sampleAccumulator = 0
		end
	end)
end

return MovementService
