--!strict
--[[
	HudController

	The combat HUD, built in code so it needs no assets:

	  * Party list (right, or top right on phones): each hero's slot, name, element and HP. Tap
	    or click to swap.
	  * HP and stamina bars (bottom centre). Stamina only shows while it is not full.
	  * Skill and burst buttons (bottom right) with cooldowns and burst energy. They work as
	    buttons on every platform, and show their key when playing on keyboard.
	  * Touch only: attack, dodge/sprint and lock-on buttons around the jump button.
	  * Enemy health bars with their current element aura, above each enemy.
	  * A short controls hint for keyboard or gamepad.

	The layout follows the last input the player used, so plugging in a controller or touching a
	laptop screen switches it on the fly.
]]

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local ElementStyle = require(ReplicatedStorage.Shared.Config.ElementStyle)
local Heroes = require(ReplicatedStorage.Shared.Config.Heroes)

local CameraController = require(script.Parent.CameraController)
local CombatController = require(script.Parent.CombatController)
local MovementController = require(script.Parent.MovementController)
local PartyController = require(script.Parent.PartyController)

local player = Players.LocalPlayer

local HudController = {}

local INK = Color3.fromRGB(20, 22, 30)
local PAPER = Color3.fromRGB(245, 242, 235)
local HP_GREEN = Color3.fromRGB(110, 220, 120)
local SHIELD = Color3.fromRGB(230, 200, 120)
local STAMINA = Color3.fromRGB(255, 220, 110)

type Row = { button: TextButton, name: TextLabel, fill: Frame, pip: Frame, stroke: UIStroke }

local gui: ScreenGui
local rows: { Row } = {}
local hpBack: Frame
local hpFill: Frame
local shieldFill: Frame
local hpText: TextLabel
local staminaBar: Frame
local staminaFill: Frame
local skillButton: TextButton
local skillCooldown: TextLabel
local burstButton: TextButton
local burstFill: Frame
local burstStroke: UIStroke

local function rgb(values: { number }): Color3
	return Color3.fromRGB(values[1], values[2], values[3])
end

local function make(className: string, props: { [string]: any }, parent: Instance?): any
	local instance = Instance.new(className)
	for key, value in props do
		(instance :: any)[key] = value
	end
	instance.Parent = parent
	return instance
end

local function corner(parent: Instance, radius: number?)
	make("UICorner", { CornerRadius = if radius then UDim.new(0, radius) else UDim.new(1, 0) }, parent)
end

local function bar(
	parent: Instance,
	size: UDim2,
	position: UDim2,
	anchor: Vector2,
	color: Color3
): (Frame, Frame)
	local back = make("Frame", {
		Size = size,
		Position = position,
		AnchorPoint = anchor,
		BackgroundColor3 = INK,
		BackgroundTransparency = 0.35,
		BorderSizePixel = 0,
	}, parent)
	corner(back, 4)
	local fill =
		make("Frame", { Size = UDim2.fromScale(1, 1), BackgroundColor3 = color, BorderSizePixel = 0 }, back)
	corner(fill, 4)
	return back, fill
end

local function roundButton(
	parent: Instance,
	name: string,
	size: number,
	position: UDim2,
	label: string,
	color: Color3
): TextButton
	local button = make("TextButton", {
		Name = name,
		Size = UDim2.fromOffset(size, size),
		Position = position,
		AnchorPoint = Vector2.new(0.5, 0.5),
		BackgroundColor3 = INK,
		BackgroundTransparency = 0.25,
		Text = label,
		TextColor3 = PAPER,
		Font = Enum.Font.GothamBold,
		TextSize = math.floor(size * 0.28),
		AutoButtonColor = true,
	}, parent)
	corner(button)
	make(
		"UIStroke",
		{ Color = color, Thickness = 2.5, ApplyStrokeMode = Enum.ApplyStrokeMode.Border },
		button
	)
	return button
end

type InputMode = "keyboard" | "gamepad" | "touch"

local partyList: Frame
local partyLayout: UIListLayout
local touchButtons: { GuiObject } = {}
local hint: TextLabel
local inputMode: InputMode = "keyboard"

local HINTS: { [InputMode]: string } = {
	keyboard = "Click attack · E skill · Q burst · Shift dodge, hold to sprint · Space jump/glide · 1-4 swap · T lock-on · Alt cursor",
	gamepad = "X attack · Y skill · R1 burst · B dodge, hold to sprint · A jump/glide · D-pad swap · R3 lock-on",
	touch = "",
}

local function buildPartyList()
	partyList = make("Frame", { Name = "Party", BackgroundTransparency = 1 }, gui)
	partyLayout = make("UIListLayout", { SortOrder = Enum.SortOrder.LayoutOrder }, partyList)

	for slot = 1, 4 do
		local button = make("TextButton", {
			Name = `Slot{slot}`,
			LayoutOrder = slot,
			BackgroundColor3 = INK,
			BackgroundTransparency = 0.4,
			Text = "",
			AutoButtonColor = true,
		}, partyList)
		corner(button, 10)
		local stroke = make(
			"UIStroke",
			{ Color = PAPER, Thickness = 0, ApplyStrokeMode = Enum.ApplyStrokeMode.Border },
			button
		)
		make("TextLabel", {
			Size = UDim2.new(0, 22, 1, 0),
			Position = UDim2.fromOffset(6, 0),
			BackgroundTransparency = 1,
			Text = tostring(slot),
			TextColor3 = PAPER,
			Font = Enum.Font.GothamBold,
			TextScaled = true,
		}, button)
		local pip = make("Frame", {
			AnchorPoint = Vector2.new(0, 0.5),
			Size = UDim2.fromOffset(10, 10),
			Position = UDim2.new(0, 32, 0.3, 0),
			BorderSizePixel = 0,
		}, button)
		corner(pip)
		local name = make("TextLabel", {
			Size = UDim2.new(1, -54, 0.45, 0),
			Position = UDim2.new(0, 48, 0.08, 0),
			BackgroundTransparency = 1,
			Text = "",
			TextColor3 = PAPER,
			TextXAlignment = Enum.TextXAlignment.Left,
			Font = Enum.Font.GothamMedium,
			TextScaled = true,
		}, button)
		local _, fill =
			bar(button, UDim2.new(1, -42, 0, 6), UDim2.new(0, 32, 0.68, 0), Vector2.zero, HP_GREEN)
		button.Activated:Connect(function()
			PartyController.requestSwap(slot)
		end)
		rows[slot] = { button = button, name = name, fill = fill, pip = pip, stroke = stroke }
	end
end

local function buildBars()
	hpBack, hpFill =
		bar(gui, UDim2.fromOffset(340, 14), UDim2.new(0.5, 0, 1, -34), Vector2.new(0.5, 1), HP_GREEN)
	shieldFill = make("Frame", {
		Size = UDim2.fromScale(0, 1),
		BackgroundColor3 = SHIELD,
		BackgroundTransparency = 0.2,
		BorderSizePixel = 0,
	}, hpBack)
	corner(shieldFill, 4)
	hpText = make("TextLabel", {
		Size = UDim2.fromOffset(340, 16),
		Position = UDim2.new(0.5, 0, 1, -50),
		AnchorPoint = Vector2.new(0.5, 1),
		BackgroundTransparency = 1,
		TextColor3 = PAPER,
		TextStrokeTransparency = 0.5,
		Font = Enum.Font.GothamMedium,
		TextSize = 14,
		Text = "",
	}, gui)
	staminaBar, staminaFill =
		bar(gui, UDim2.fromOffset(200, 6), UDim2.new(0.5, 0, 1, -72), Vector2.new(0.5, 1), STAMINA)
end

-- A button that reports press and release, for actions that care about holding.
local function holdButton(name: string, label: string, color: Color3, onHeld: (boolean) -> ()): TextButton
	local button = roundButton(gui, name, 60, UDim2.new(), label, color)
	button.MouseButton1Down:Connect(function()
		onHeld(true)
	end)
	button.MouseButton1Up:Connect(function()
		onHeld(false)
	end)
	button.MouseLeave:Connect(function()
		onHeld(false)
	end)
	return button
end

local function buildAbilityButtons()
	skillButton = roundButton(gui, "Skill", 64, UDim2.new(), "", Color3.new(1, 1, 1))
	skillCooldown = make("TextLabel", {
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		TextColor3 = PAPER,
		Font = Enum.Font.GothamBlack,
		TextSize = 22,
		Text = "",
	}, skillButton)
	skillButton.Activated:Connect(CombatController.skill)

	burstButton = roundButton(gui, "Burst", 80, UDim2.new(), "", Color3.new(1, 1, 1))
	burstStroke = burstButton:FindFirstChildOfClass("UIStroke") :: UIStroke
	burstButton.ClipsDescendants = true
	burstFill = make("Frame", {
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.fromScale(0, 1),
		Size = UDim2.fromScale(1, 0),
		BackgroundTransparency = 0.55,
		BorderSizePixel = 0,
		ZIndex = 0,
	}, burstButton)
	burstButton.Activated:Connect(CombatController.burst)

	local attack = holdButton("Attack", "Attack", PAPER, CombatController.setAttackHeld)
	local dodge = holdButton("Dodge", "Dodge", STAMINA, MovementController.setDodgeHeld)
	local lock = roundButton(gui, "LockOn", 44, UDim2.new(), "Lock", PAPER)
	lock.Activated:Connect(CameraController.toggleLockOn)
	touchButtons = { attack, dodge, lock }

	hint = make("TextLabel", {
		Name = "ControlsHint",
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.new(0, 14, 1, -12),
		Size = UDim2.fromOffset(620, 18),
		BackgroundTransparency = 1,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextColor3 = PAPER,
		TextTransparency = 0.25,
		TextStrokeTransparency = 0.6,
		Font = Enum.Font.Gotham,
		TextSize = 13,
		Text = "",
	}, gui)
end

local function place(object: GuiObject, size: number, x: number, y: number)
	object.Size = UDim2.fromOffset(size, size)
	object.Position = UDim2.new(1, x, 1, y)
end

-- Lays the HUD out for the current input. Phones put the party list in the top-right corner and
-- keep every button clear of Roblox's thumbstick (bottom left) and jump button (bottom right).
local function applyLayout()
	local touch = inputMode == "touch"
	local rowHeight = if touch then 28 else 44
	local rowGap = if touch then 3 else 6
	partyLayout.Padding = UDim.new(0, rowGap)
	for _, row in rows do
		row.button.Size = UDim2.new(1, 0, 0, rowHeight)
	end
	partyList.Size = UDim2.fromOffset(if touch then 150 else 200, 4 * rowHeight + 3 * rowGap)
	partyList.AnchorPoint = if touch then Vector2.new(1, 0) else Vector2.new(1, 0.5)
	partyList.Position = if touch then UDim2.new(1, -10, 0, 4) else UDim2.new(1, -14, 0.42, 0)

	-- Narrower bars on phones so they stay clear of the skill button.
	local barWidth = if touch then 220 else 340
	hpBack.Size = UDim2.fromOffset(barWidth, 14)
	hpText.Size = UDim2.fromOffset(barWidth, 16)
	staminaBar.Size = UDim2.fromOffset(if touch then 140 else 200, 6)

	if touch then
		local attack, dodge, lock = touchButtons[1], touchButtons[2], touchButtons[3]
		place(attack, 80, -150, -75)
		place(skillButton, 56, -235, -55)
		place(burstButton, 64, -215, -135)
		place(dodge, 52, -60, -140)
		place(lock, 40, -290, -130)
		attack.TextSize = 18
		dodge.TextSize = 12
		lock.TextSize = 11
	else
		place(skillButton, 64, -150, -60)
		place(burstButton, 80, -66, -76)
	end
	for _, button in touchButtons do
		button.Visible = touch
	end

	skillButton.Text = if inputMode == "keyboard" then "E" else ""
	burstButton.Text = if inputMode == "keyboard" then "Q" else ""
	hint.Text = HINTS[inputMode]
	hint.Visible = not touch
end

local function modeFor(inputType: Enum.UserInputType): InputMode?
	if inputType == Enum.UserInputType.Touch then
		return "touch"
	elseif inputType == Enum.UserInputType.Keyboard or string.find(inputType.Name, "Mouse") then
		return "keyboard"
	elseif string.find(inputType.Name, "Gamepad") then
		return "gamepad"
	end
	return nil
end

local function initialMode(): InputMode
	local last = modeFor(UserInputService:GetLastInputType())
	if last then
		return last
	end
	if UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled then
		return "touch"
	end
	if UserInputService.GamepadEnabled and not UserInputService.KeyboardEnabled then
		return "gamepad"
	end
	return "keyboard"
end

local function refreshParty()
	local snapshot = PartyController.getSnapshot()
	if not snapshot then
		return
	end
	local now = PartyController.now()
	for slot, row in rows do
		local member = snapshot.members[slot]
		row.button.Visible = member ~= nil
		if member then
			local kit = Heroes[member.heroId]
			local active = slot == snapshot.active
			row.name.Text = kit.displayName
			row.pip.BackgroundColor3 = rgb(ElementStyle.Elements[kit.element] or ElementStyle.Physical)
			row.fill.Size = UDim2.fromScale(math.clamp(member.hp / member.maxHp, 0, 1), 1)
			row.button.BackgroundTransparency = if active then 0.1 else 0.45
			row.stroke.Thickness = if active then 2 else 0
			row.name.TextTransparency = if member.hp <= 0
				then 0.6
				elseif now < snapshot.swapReadyAt and not active then 0.35
				else 0
		end
	end

	local member = snapshot.members[snapshot.active]
	if member then
		hpFill.Size = UDim2.fromScale(math.clamp(member.hp / member.maxHp, 0, 1), 1)
		shieldFill.Size = UDim2.fromScale(math.clamp(member.shield / member.maxHp, 0, 1), 1)
		hpText.Text = `{math.ceil(member.hp)} / {member.maxHp}`
	end
end

local function refreshAbilities()
	local kit, state = PartyController.active()
	if not kit or not state then
		return
	end
	local now = PartyController.now()
	local color = rgb(ElementStyle.Elements[kit.element] or ElementStyle.Physical)

	local skillLeft = state.skillReadyAt - now
	skillCooldown.Text = if skillLeft > 0 then string.format("%.1f", skillLeft) else ""
	skillButton.BackgroundTransparency = if skillLeft > 0 then 0.55 else 0.15
	skillButton.TextTransparency = if skillLeft > 0 then 1 else 0
	local skillStroke = skillButton:FindFirstChildOfClass("UIStroke")
	if skillStroke then
		skillStroke.Color = color
	end

	local fraction = math.clamp(state.energy / kit.burst.energyCost, 0, 1)
	burstFill.Size = UDim2.fromScale(1, fraction)
	burstFill.BackgroundColor3 = color
	local ready = fraction >= 1 and now >= state.burstReadyAt
	burstStroke.Color = if ready then color else Color3.fromRGB(120, 120, 130)
	burstStroke.Thickness = if ready then 3.5 + math.sin(now * 6) else 2

	local stamina, max = MovementController.getStamina()
	staminaBar.Visible = stamina < max - 0.5
	staminaFill.Size = UDim2.fromScale(math.clamp(stamina / max, 0, 1), 1)
	staminaFill.BackgroundColor3 = if stamina < 40 then Color3.fromRGB(255, 120, 90) else STAMINA
end

-- Health bar and aura pip above each enemy, driven by the attributes EnemyService publishes.
local function attachEnemyBar(model: Instance)
	local root = model:FindFirstChild("HumanoidRootPart") or model:WaitForChild("HumanoidRootPart", 5)
	if not root or not model:IsA("Model") then
		return
	end
	local billboard = make("BillboardGui", {
		Name = "EnemyBar",
		Adornee = root,
		Size = UDim2.fromOffset(110, 26),
		StudsOffset = Vector3.new(0, 5.4, 0),
		MaxDistance = 90,
		AlwaysOnTop = true,
	}, root)
	local name = make("TextLabel", {
		Size = UDim2.new(1, 0, 0, 12),
		BackgroundTransparency = 1,
		TextColor3 = PAPER,
		TextStrokeTransparency = 0.4,
		Font = Enum.Font.GothamMedium,
		TextSize = 11,
		Text = tostring(model:GetAttribute("DisplayName") or ""),
	}, billboard)
	local _, fill = bar(
		billboard,
		UDim2.new(1, 0, 0, 7),
		UDim2.fromOffset(0, 15),
		Vector2.zero,
		Color3.fromRGB(235, 80, 70)
	)
	local aura = make("Frame", {
		Size = UDim2.fromOffset(10, 10),
		Position = UDim2.new(1, 4, 0, 13),
		BorderSizePixel = 0,
		Visible = false,
	}, billboard)
	corner(aura)

	local function update()
		local health = model:GetAttribute("Health") :: number? or 0
		local maxHealth = model:GetAttribute("MaxHealth") :: number? or 1
		fill.Size = UDim2.fromScale(math.clamp(health / maxHealth, 0, 1), 1)
		local element = model:GetAttribute("Aura")
		local values = type(element) == "string" and ElementStyle.Elements[element]
		aura.Visible = values ~= nil and values ~= false
		if values then
			aura.BackgroundColor3 = rgb(values)
		end
		local frozen = model:GetAttribute("Frozen") == true
		name.TextColor3 = if frozen then Color3.fromRGB(170, 240, 255) else PAPER
	end
	model:GetAttributeChangedSignal("Health"):Connect(update)
	model:GetAttributeChangedSignal("Aura"):Connect(update)
	model:GetAttributeChangedSignal("Frozen"):Connect(update)
	update()
end

function HudController:Start()
	gui = make(
		"ScreenGui",
		{ Name = "FarbornHud", ResetOnSpawn = false, IgnoreGuiInset = false },
		player:WaitForChild("PlayerGui")
	)

	buildPartyList()
	buildBars()
	buildAbilityButtons()
	inputMode = initialMode()
	applyLayout()

	UserInputService.LastInputTypeChanged:Connect(function(inputType)
		local mode = modeFor(inputType)
		if mode and mode ~= inputMode then
			inputMode = mode
			applyLayout()
		end
	end)

	PartyController.onChanged(refreshParty)
	RunService.RenderStepped:Connect(function()
		refreshParty()
		refreshAbilities()
	end)

	CollectionService:GetInstanceAddedSignal("Enemy"):Connect(attachEnemyBar)
	for _, model in CollectionService:GetTagged("Enemy") do
		task.spawn(attachEnemyBar, model)
	end
end

return HudController
