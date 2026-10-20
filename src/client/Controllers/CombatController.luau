--!strict
--[[
	CombatController

	Attack, charged attack, plunge, Technique and Finale input, plus every piece of combat
	feedback.

	Inputs follow the combat plan:
	  Attack: left click, X on a gamepad, or the attack button. Press to attack; hold to charge.
	          Attacking while gliding or falling plunges.
	  Technique: E, R1, or the Technique button.
	  Finale: Q, Y, or the Finale button.

	The client plays its own swing the moment the local copy of Shared.Combat.Ability accepts
	the input, then asks CombatService. Damage numbers, reactions and hit-stop wait for the
	server's confirmed hits, so what players see is always what actually happened.
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
local Registry = require(script.Parent.Parent.Rig.Registry)

local player = Players.LocalPlayer

type Action = "attack" | "charged" | "plunge" | "technique" | "finale"

local CombatController = {}

local actionRemote: RemoteEvent
local attackHeld = false
local attackHeldSince = 0
local chargedDone = false

local GOLD = Color3.fromRGB(255, 205, 80)
local TELEGRAPH_COLORS: { [string]: Color3 } = {
	normal = Color3.fromRGB(255, 245, 230),
	gold = GOLD,
	red = Color3.fromRGB(255, 70, 55),
}

local function characterParts(character: Model?): (Humanoid?, BasePart?)
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	return humanoid, root
end

-- The swing every player sees for a basic or charged attack, or a plunge's landing.
local function playSwing(
	character: Model,
	kit: Heroes.Kit,
	action: string,
	index: number?,
	origin: Vector3,
	forward: Vector3,
	element: string?
)
	local color = if element then Effects.elementColor(element) else Color3.fromRGB(245, 245, 255)
	if action == "plunge" then
		Effects.shockwave(origin, kit.plunge.radius, color)
		Effects.area(origin, kit.plunge.radius, color, false)
		return
	end
	local hit: Heroes.Hit? = if action == "charged"
		then kit.charged
		elseif index then kit.chain[index]
		else nil
	if not hit then
		return
	end
	local rig = Registry.get(character)
	if rig then
		rig.play(action, { weapon = kit.weapon, index = index, heavy = hit.heavy })
	else
		Effects.swingArm(character, hit.heavy)
	end
	if kit.weapon == "focus" or kit.weapon == "bow" then
		Effects.bolt(origin, forward, hit.range, Effects.elementColor(kit.element))
	elseif hit.arc >= 360 then
		Effects.area(origin, hit.range, color, false)
	else
		Effects.slash(origin, forward, hit.range, hit.arc, color, hit.heavy)
	end
end

-- A Technique or Finale: the rig's cast animation, or the plain arm swing without one.
local function playCast(character: Model, name: string, kit: Heroes.Kit)
	local rig = Registry.get(character)
	if rig then
		rig.play(name, { weapon = kit.weapon })
	else
		Effects.swingArm(character, true)
	end
end

-- Tries one action locally; if the local timing allows it, sends it and plays it at once.
local function perform(action: Action): boolean
	local character = player.Character
	local humanoid, root = characterParts(character)
	if not character or not humanoid or not root or humanoid.Health <= 0 then
		return false
	end
	if
		action ~= "plunge" and (MovementController.getMode() ~= "ground" or MovementController.isDodging())
	then
		return false
	end
	local kit, state = PartyController.active()
	if not kit or not state then
		return false
	end

	local now = PartyController.now()
	local index: number? = nil
	if action == "attack" then
		index = Ability.tryAttack(state, kit, now, 0)
		if not index then
			return false
		end
	elseif action == "charged" then
		if not Ability.tryCharged(state, kit, now, 0) then
			return false
		end
	elseif action == "plunge" then
		if not Ability.tryPlunge(state, now, 0) then
			return false
		end
	elseif action == "technique" then
		if not Ability.tryTechnique(state, kit, now, 0) then
			return false
		end
	elseif not Ability.tryFinale(state, kit, now, 0) then
		return false
	end

	local forward = CameraController.getAimDirection()
	if action ~= "plunge" then
		root.CFrame = CFrame.lookAt(root.Position, root.Position + forward)
	end
	-- Send first: a problem in a cosmetic effect must never cost the player their input.
	actionRemote:FireServer(action, forward)

	if action == "attack" or action == "charged" or action == "plunge" then
		local element = if kit.chainIsElemental then kit.element else nil
		playSwing(character, kit, action, index, root.Position, forward, element)
	elseif action == "technique" then
		playCast(character, "technique", kit)
		local first = kit.technique.steps[1]
		if first and first.kind == "dash" then
			MovementController.dash(forward, first.length or 10, first.seconds or 0.25)
		end
	else
		playCast(character, "finale", kit)
		Effects.flash(character, Effects.elementColor(kit.element), 0.6)
		CameraController.shake(0.9)
	end
	return true
end

local function startPlunge()
	MovementController.plunge(function()
		perform("plunge")
	end)
end

function CombatController.technique()
	perform("technique")
end

function CombatController.finale()
	perform("finale")
end

function CombatController.setAttackHeld(held: boolean)
	if held and not attackHeld then
		attackHeld = true
		attackHeldSince = os.clock()
		chargedDone = false
		if MovementController.canPlunge() then
			chargedDone = true
			startPlunge()
		else
			perform("attack")
		end
	elseif not held then
		attackHeld = false
	end
end

local function showHits(hits: { any }, heavy: boolean?)
	for _, hit in hits do
		Effects.spark(hit.position, Effects.elementColor(hit.element), heavy)
		Effects.damageNumber(hit.position, hit.amount, hit.element, hit.crit)
		if hit.bonus and hit.bonus > 0 then
			Effects.damageNumber(hit.position + Vector3.new(0, 1, 0), hit.bonus, hit.element, false)
		end
		if hit.reaction then
			Effects.reaction(hit.position, hit.reaction)
		end
		if hit.shatter then
			Effects.popup(hit.position + Vector3.new(0, 2, 0), "SHATTER!", Color3.fromRGB(190, 240, 255), 1.2)
		end
	end
end

local function hitStopFor(mine: boolean, hits: { any }, heavy: boolean?)
	if mine and #hits > 0 and player.Character then
		local seconds = if heavy
			then CombatConfig.Combat.HeavyHitStopSeconds
			else CombatConfig.Combat.HitStopSeconds
		Effects.hitStop(player.Character, seconds)
		CameraController.shake(if heavy then 0.45 else 0.18)
	end
end

local function onStep(message: { [string]: any }, mine: boolean)
	local color = Effects.elementColor(message.element)
	local kind = message.step
	local hits = message.hits or {}

	if kind == "hit" then
		if not message.tick then
			if message.shape == "arc" then
				Effects.slash(
					message.origin,
					message.forward,
					message.radius,
					message.arc or 120,
					color,
					true
				)
			else
				Effects.area(message.center, message.radius, color, message.part == "finale")
			end
		end
	elseif kind == "line" or kind == "dash" then
		Effects.streak(message.from, message.to, color, 1.4)
	elseif kind == "pull" then
		Effects.implode(message.center, message.radius, color)
	elseif kind == "rain" then
		Effects.fallingStar(message.center, message.radius, color)
	elseif kind == "zone" then
		if message.seconds then
			Effects.zone(message.center, message.radius, message.seconds, color)
		end
		if message.healed then
			Effects.healNumber(message.position, message.healed)
		end
	elseif kind == "heal" then
		if message.healed and message.healed > 0 then
			Effects.healNumber(message.position, message.healed)
		end
		local character = message.attacker and message.attacker.Character
		if character then
			Effects.flash(character, Color3.fromRGB(120, 235, 140), 0.4)
		end
	elseif kind == "effect" then
		for _, position in message.positions or {} do
			Effects.popup(position + Vector3.new(0, 2, 0), string.upper(message.effect), color, 0.9)
		end
		if message.effect ~= "Marked" then
			Effects.area(message.center, message.radius, color, false)
		end
	elseif kind == "infuse" then
		local character = message.attacker and message.attacker.Character
		if character then
			Effects.flash(character, color, 1)
		end
	end

	showHits(hits, message.heavy)
	hitStopFor(mine, hits, message.heavy)
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
				playSwing,
				character,
				kit,
				message.action,
				message.index,
				message.origin,
				message.forward,
				message.element
			)
		end
		if message.counter and message.hits and #message.hits > 0 then
			Effects.popup(message.hits[1].position + Vector3.new(0, 2.5, 0), "COUNTER!", GOLD, 1.2)
		end
		showHits(message.hits, message.heavy)
		hitStopFor(mine, message.hits, message.heavy)
	elseif kind == "ability" then
		local character = attacker and attacker.Character
		local kit = Heroes[message.heroId]
		if not mine and character and kit then
			playCast(character, if message.part == "finale" then "finale" else "technique", kit)
			Effects.flash(
				character,
				Effects.elementColor(kit.element),
				if message.part == "finale" then 0.6 else 0.3
			)
		end
		if message.part == "relay" and kit then
			Effects.popup(
				message.origin + Vector3.new(0, 3, 0),
				"RELAY",
				Effects.elementColor(kit.element),
				1
			)
		end
	elseif kind == "step" then
		onStep(message, mine)
	elseif kind == "explosion" or kind == "sweep" then
		local color = Effects.elementColor(message.element)
		Effects.area(message.position, message.radius or 6, color, kind == "explosion")
		showHits(message.hits or {})
	elseif kind == "chain" then
		local color = Effects.elementColor(message.element)
		for _, hit in message.hits or {} do
			Effects.lightning(message.position, hit.position, color)
		end
		showHits(message.hits or {})
	elseif kind == "dot" then
		Effects.damageNumber(message.position, message.amount, message.element, false)
	elseif kind == "geode" then
		Effects.popup(
			message.position + Vector3.new(0, 2, 0),
			"SHIELD",
			Effects.elementColor(message.element),
			1
		)
	elseif kind == "enemyStrike" then
		Effects.shockwave(message.position, message.radius, TELEGRAPH_COLORS[message.telegraph])
		for _, victim in message.victims :: { any } do
			local character = victim.player.Character
			local _, root = characterParts(character)
			if root then
				if victim.evaded then
					Effects.popup(root.Position, "EVADE", Color3.fromRGB(220, 240, 255), 1)
				elseif victim.amount and victim.amount > 0 then
					local victimRig = Registry.get(character)
					if victimRig then
						victimRig.play("hurt", { heavy = message.telegraph == "red" })
					end
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
	elseif kind == "slip" then
		Effects.popup(message.position + Vector3.new(0, 2, 0), "SLIP!", Color3.fromRGB(190, 225, 255), 1.4)
		if mine then
			Effects.timeSlow(CombatConfig.Defense.SlipSlowSeconds)
		end
	elseif kind == "lift" then
		Effects.popup(message.position + Vector3.new(0, 4, 0), "LIFT!", GOLD, 1.6)
		Effects.spark(message.position, GOLD, true)
		if mine and player.Character then
			Effects.hitStop(player.Character, 0.15)
			CameraController.shake(0.6)
		end
	elseif kind == "rattled" then
		Effects.popup(message.position + Vector3.new(0, 5, 0), "RATTLED!", GOLD, 1.5)
	elseif kind == "swap" then
		local character = attacker and attacker.Character
		-- The server sets HeroId before announcing the swap, and both arrive in order.
		local heroId = character and character:GetAttribute("HeroId")
		local kit = type(heroId) == "string" and Heroes[heroId] or nil
		if character and kit then
			Effects.flash(character, Effects.elementColor(kit.element), 0.35)
			local _, root = characterParts(character)
			if root and message.swap == "cover" then
				Effects.popup(root.Position + Vector3.new(0, 3, 0), "COVER!", GOLD, 1.3)
			elseif root and message.swap == "pileon" then
				Effects.popup(root.Position + Vector3.new(0, 3, 0), "PILE-ON!", GOLD, 1.3)
			end
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

	ContextActionService:BindAction("FarbornTechnique", function(_, state)
		if state == Enum.UserInputState.Begin then
			CombatController.technique()
		end
		return Enum.ContextActionResult.Sink
	end, false, Enum.KeyCode.E, Enum.KeyCode.ButtonR1)

	ContextActionService:BindAction("FarbornFinale", function(_, state)
		if state == Enum.UserInputState.Begin then
			CombatController.finale()
		end
		return Enum.ContextActionResult.Sink
	end, false, Enum.KeyCode.Q, Enum.KeyCode.ButtonY)

	-- Holding attack charges: once the hold is long enough, the charged attack plays as soon as
	-- the current swing's recovery allows.
	RunService.Heartbeat:Connect(function()
		if not attackHeld or chargedDone then
			return
		end
		local kit = PartyController.active()
		if kit and os.clock() - attackHeldSince >= kit.charged.holdSeconds then
			if perform("charged") then
				chargedDone = true
			end
		end
	end)
end

return CombatController
