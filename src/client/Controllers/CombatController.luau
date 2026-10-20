--!strict
--[[
	CombatController

	Attack, skill and burst input, plus every piece of combat feedback.

	Inputs: left mouse / X on a gamepad / the attack button to attack (hold to keep the chain
	going), E / Y / skill button for the elemental skill, Q / R1 / burst button for the burst.

	The client plays its own swing the moment the input is accepted by the local copy of
	Shared.Combat.Ability, then asks CombatService. Damage numbers, reactions and hit-stop wait
	for the server's confirmed hits, so what players see is always what actually happened.
]]

local ContextActionService = game:GetService("ContextActionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Ability = require(ReplicatedStorage.Shared.Combat.Ability)
local CombatConfig = require(ReplicatedStorage.Shared.Config.CombatConfig)
local Heroes = require(ReplicatedStorage.Shared.Config.Heroes)
local Net = require(ReplicatedStorage.Shared.Net)

local CameraController = require(script.Parent.CameraController)
local Effects = require(script.Parent.Parent.Effects)
local MovementController = require(script.Parent.MovementController)
local PartyController = require(script.Parent.PartyController)

local player = Players.LocalPlayer

local CombatController = {}

local actionRemote: RemoteEvent
local attackHeld = false

local function characterParts(character: Model?): (Humanoid?, BasePart?)
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	return humanoid, root
end

local function playAction(
	character: Model,
	kit: Heroes.Kit,
	action: string,
	index: number?,
	origin: Vector3,
	forward: Vector3,
	areaCenter: Vector3?
)
	local color = Effects.elementColor(kit.element)
	if action == "attack" and index then
		local hit = kit.chain[index]
		local swingColor = if kit.chainIsElemental then color else Color3.fromRGB(245, 245, 255)
		Effects.swingArm(character, hit.heavy)
		if kit.weapon == "catalyst" then
			Effects.bolt(origin, forward, hit.range, color)
		else
			Effects.slash(origin, forward, hit.range, hit.arc, swingColor, hit.heavy)
		end
	elseif action == "skill" then
		Effects.swingArm(character, true)
		Effects.area(areaCenter or origin, kit.skill.radius, color, false)
	elseif action == "burst" then
		Effects.swingArm(character, true)
		Effects.area(areaCenter or origin, kit.burst.radius, color, true)
	end
end

-- Tries one action locally; if the local timing allows it, plays it and sends it to the server.
local function perform(action: "attack" | "skill" | "burst")
	local character = player.Character
	local humanoid, root = characterParts(character)
	if not character or not humanoid or not root or humanoid.Health <= 0 then
		return
	end
	if MovementController.getMode() ~= "ground" or MovementController.isDodging() then
		return
	end
	local kit, state = PartyController.active()
	if not kit or not state then
		return
	end

	local now = PartyController.now()
	local index: number? = nil
	if action == "attack" then
		index = Ability.tryAttack(state, kit, now, 0)
		if not index then
			return
		end
	elseif action == "skill" then
		if not Ability.trySkill(state, kit, now, 0) then
			return
		end
	elseif not Ability.tryBurst(state, kit, now, 0) then
		return
	end

	local forward = CameraController.getAimDirection()
	root.CFrame = CFrame.lookAt(root.Position, root.Position + forward)
	local area = if action == "skill" then kit.skill elseif action == "burst" then kit.burst else nil
	local areaCenter = if area then root.Position + forward * area.forward else nil
	-- Send first: a problem in a cosmetic effect must never cost the player their input.
	actionRemote:FireServer(action, forward)
	playAction(character, kit, action, index, root.Position, forward, areaCenter)
	if action == "burst" then
		CameraController.shake(0.8)
	end
end

function CombatController.attack()
	perform("attack")
end

function CombatController.skill()
	perform("skill")
end

function CombatController.burst()
	perform("burst")
end

function CombatController.setAttackHeld(held: boolean)
	attackHeld = held
	if held then
		perform("attack")
	end
end

local function onFeedback(message: { [string]: any })
	local kind = message.kind
	local attacker = message.attacker :: Player?
	local mine = attacker == player

	if kind == "action" then
		local kit = Heroes[message.heroId]
		local character = attacker and attacker.Character
		if not mine and kit and character then
			-- Spawned so a cosmetic error can never stop the damage numbers below.
			task.spawn(
				playAction,
				character,
				kit,
				message.action,
				message.index,
				message.origin,
				message.forward,
				message.areaCenter
			)
		end
		local hits = message.hits :: { any }
		for _, hit in hits do
			Effects.spark(hit.position, Effects.elementColor(hit.element), message.heavy)
			Effects.damageNumber(hit.position, hit.amount, hit.element, hit.crit)
			if hit.bonus > 0 then
				Effects.damageNumber(hit.position + Vector3.new(0, 1, 0), hit.bonus, hit.element, false)
			end
			if hit.reaction then
				Effects.reaction(hit.position, hit.reaction)
			end
		end
		if mine and #hits > 0 and player.Character then
			local heavy = message.heavy == true
			Effects.hitStop(
				player.Character,
				if heavy then CombatConfig.Combat.HeavyHitStopSeconds else CombatConfig.Combat.HitStopSeconds
			)
			CameraController.shake(if heavy then 0.45 else 0.18)
		end
	elseif kind == "enemyStrike" then
		Effects.shockwave(message.position, message.radius)
		for _, victim in message.victims :: { any } do
			local character = victim.player.Character
			local _, root = characterParts(character)
			if root then
				if victim.evaded then
					Effects.popup(root.Position, "Evade", Color3.fromRGB(220, 240, 255), 1)
				elseif victim.amount and victim.amount > 0 then
					Effects.popup(
						root.Position,
						tostring(math.floor(victim.amount)),
						Color3.fromRGB(255, 80, 70),
						1
					)
					if victim.player == player then
						CameraController.shake(0.5)
						Effects.flash(character :: Model, Color3.fromRGB(255, 60, 60), 0.25)
					end
				end
			end
		end
	elseif kind == "stagger" then
		Effects.popup(message.position, "Break!", Color3.fromRGB(255, 220, 120), 1.2)
	elseif kind == "swap" then
		local character = attacker and attacker.Character
		-- The server sets HeroId before announcing the swap, and both arrive in order.
		local heroId = character and character:GetAttribute("HeroId")
		local kit = type(heroId) == "string" and Heroes[heroId] or nil
		if character and kit then
			Effects.flash(character, Effects.elementColor(kit.element), 0.35)
		end
	end
end

function CombatController:Init()
	actionRemote = Net.event(Net.Names.CombatAction)
end

function CombatController:Start()
	Net.event(Net.Names.CombatFeedback).OnClientEvent:Connect(onFeedback)

	ContextActionService:BindAction("FarbornAttack", function(_, state)
		if state == Enum.UserInputState.Begin then
			CombatController.setAttackHeld(true)
		elseif state == Enum.UserInputState.End or state == Enum.UserInputState.Cancel then
			CombatController.setAttackHeld(false)
		end
		return Enum.ContextActionResult.Pass
	end, false, Enum.UserInputType.MouseButton1, Enum.KeyCode.ButtonX)

	ContextActionService:BindAction("FarbornSkill", function(_, state)
		if state == Enum.UserInputState.Begin then
			CombatController.skill()
		end
		return Enum.ContextActionResult.Sink
	end, false, Enum.KeyCode.E, Enum.KeyCode.ButtonY)

	ContextActionService:BindAction("FarbornBurst", function(_, state)
		if state == Enum.UserInputState.Begin then
			CombatController.burst()
		end
		return Enum.ContextActionResult.Sink
	end, false, Enum.KeyCode.Q, Enum.KeyCode.ButtonR1)

	-- Holding attack keeps the chain going as soon as each recovery ends.
	RunService.Heartbeat:Connect(function()
		if attackHeld then
			perform("attack")
		end
	end)
end

return CombatController
