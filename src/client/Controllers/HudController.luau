--!strict
--[[
	HudController

	The combat HUD, built in code so it needs no assets:

	  * Party list (right, or top right on phones): each hero's slot, name, element and HP. Tap
	    or click to swap.
	  * HP and stamina bars (bottom centre). Stamina only shows while it is not full.
	  * Technique and Finale buttons (bottom right) with the cooldown and Finale energy. They work as
	    buttons on every platform, and show their key when playing on keyboard.
	  * Touch only: attack, dodge/sprint and lock-on buttons, placed around Roblox's jump button
	    by TouchLayout so they fit phones and tablets.
	  * Party portraits glow gold when that hero's Relay is ready.
	  * Dodges left, as pips under the HP bar.
	  * Above each enemy: health, its status icon, a Composure bar on elites (RATTLED when it
	    breaks) and the attack glint while it winds up: white ring, gold star (Lift it) or red
	    burst (dodge it).
	  * A short controls hint for keyboard or gamepad.

	The layout follows the last input the player used, so plugging in a controller or touching a
	laptop screen switches it on the fly.
]]

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local CombatConfig = require(ReplicatedStorage.Shared.Config.CombatConfig)
local Content = require(ReplicatedStorage.Shared.Content)
local ElementStyle = require(ReplicatedStorage.Shared.Config.ElementStyle)
local Heroes = require(ReplicatedStorage.Shared.Config.Heroes)

local CameraController = require(script.Parent.CameraController)
local CombatController = require(script.Parent.CombatController)
local MovementController = require(script.Parent.MovementController)
local PartyController = require(script.Parent.PartyController)
local TouchLayout = require(script.Parent.Parent.TouchLayout)

local player = Players.LocalPlayer

local HudController = {}

local INK = Color3.fromRGB(20, 22, 30)
local PAPER = Color3.fromRGB(245, 242, 235)
local HP_GREEN = Color3.fromRGB(110, 220, 120)
local SHIELD = Color3.fromRGB(230, 200, 120)
local STAMINA = Color3.fromRGB(255, 220, 110)
local RELAY_GOLD = Color3.fromRGB(255, 205, 80)
local GLINTS: { [string]: { symbol: string, color: Color3 } } = {
	normal = { symbol = "◯", color = Color3.fromRGB(255, 250, 240) },
	gold = { symbol = "★", color = Color3.fromRGB(255, 205, 80) },
	red = { symbol = "✸", color = Color3.fromRGB(255, 70, 55) },
}

type Row = { button: TextButton, name: TextLabel, fill: Frame, pip: Frame, stroke: UIStroke }

local gui: ScreenGui
local rows: { Row } = {}
local hpBack: Frame
local hpFill: Frame
local shieldFill: Frame
local hpText: TextLabel
local staminaBar: Frame
local staminaFill: Frame
local techniqueButton: TextButton
local techniqueCooldown: TextLabel
local finaleButton: TextButton
local finaleFill: Frame
local finaleStroke: UIStroke
local dodgePips: { Frame } = {}

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
	keyboard = "Click attack, hold to charge · E Technique · Q Finale · Shift or right click dodge, hold to sprint · Space jump/glide · 1-4 swap · T lock-on · Alt cursor",
	gamepad = "X attack, hold to charge · R1 Technique · Y Finale · B dodge, hold to sprint · A jump/glide · D-pad swap · R3 lock-on",
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

	local pips = make("Frame", {
		Name = "Dodges",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -20),
		Size = UDim2.fromOffset(60, 8),
		BackgroundTransparency = 1,
	}, gui)
	make("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal,
		HorizontalAlignment = Enum.HorizontalAlignment.Center,
		Padding = UDim.new(0, 6),
	}, pips)
	for index = 1, CombatConfig.Defense.DodgeCharges do
		local pip = make("Frame", {
			Name = "Dodge" .. index,
			Size = UDim2.fromOffset(8, 8),
			BackgroundColor3 = PAPER,
			BorderSizePixel = 0,
		}, pips)
		corner(pip)
		dodgePips[index] = pip
	end
end

-- A button that reports press and release, for actions that care about holding. The release
-- follows the touch that pressed it, so sliding a finger off the button still lets go, and a
-- second finger on the same button doesn't press it twice.
local function holdButton(name: string, label: string, color: Color3, onHeld: (boolean) -> ()): TextButton
	local button = roundButton(gui, name, 60, UDim2.new(), label, color)
	local pressedBy: InputObject? = nil
	local function release()
		if pressedBy then
			pressedBy = nil
			onHeld(false)
		end
	end
	button.InputBegan:Connect(function(input)
		local kind = input.UserInputType
		if
			pressedBy == nil
			and (kind == Enum.UserInputType.Touch or kind == Enum.UserInputType.MouseButton1)
		then
			pressedBy = input
			onHeld(true)
		end
	end)
	UserInputService.InputEnded:Connect(function(input)
		local pressed = pressedBy
		if
			pressed
			and (
				input == pressed
				or (
					pressed.UserInputType == Enum.UserInputType.MouseButton1
					and input.UserInputType == Enum.UserInputType.MouseButton1
				)
			)
		then
			release()
		end
	end)
	button:GetPropertyChangedSignal("Visible"):Connect(function()
		if not button.Visible then
			release()
		end
	end)
	return button
end

local function buildAbilityButtons()
	techniqueButton = roundButton(gui, "Technique", 64, UDim2.new(), "", Color3.new(1, 1, 1))
	techniqueCooldown = make("TextLabel", {
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		TextColor3 = PAPER,
		Font = Enum.Font.GothamBlack,
		TextSize = 22,
		Text = "",
	}, techniqueButton)
	techniqueButton.Activated:Connect(CombatController.technique)

	finaleButton = roundButton(gui, "Finale", 80, UDim2.new(), "", Color3.new(1, 1, 1))
	finaleStroke = finaleButton:FindFirstChildOfClass("UIStroke") :: UIStroke
	finaleButton.ClipsDescendants = true
	finaleFill = make("Frame", {
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.fromScale(0, 1),
		Size = UDim2.fromScale(1, 0),
		BackgroundTransparency = 0.55,
		BorderSizePixel = 0,
		ZIndex = 0,
	}, finaleButton)
	finaleButton.Activated:Connect(CombatController.finale)

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

local function place(object: GuiObject, spot: TouchLayout.Spot)
	object.Size = UDim2.fromOffset(spot.size, spot.size)
	object.Position = UDim2.new(1, spot.x, 1, spot.y)
end

-- Roblox's touch jump button as TouchLayout expects it: its centre measured from the HUD's
-- bottom-right corner, and its size. Until the touch controls exist, assume a phone.
local function jumpButtonSpot(): TouchLayout.Spot
	local playerGui = gui.Parent
	local touchGui = playerGui and playerGui:FindFirstChild("TouchGui")
	local jump = touchGui and touchGui:FindFirstChild("JumpButton", true)
	if jump and jump:IsA("GuiObject") and jump.AbsoluteSize.X > 0 then
		local centre = jump.AbsolutePosition + jump.AbsoluteSize / 2
		local bottomRight = gui.AbsolutePosition + gui.AbsoluteSize
		return { x = centre.X - bottomRight.X, y = centre.Y - bottomRight.Y, size = jump.AbsoluteSize.X }
	end
	return TouchLayout.PhoneJump
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

	-- Narrower bars on phones so they stay clear of the Technique button.
	local barWidth = if touch then 220 else 340
	hpBack.Size = UDim2.fromOffset(barWidth, 14)
	hpText.Size = UDim2.fromOffset(barWidth, 16)
	staminaBar.Size = UDim2.fromOffset(if touch then 140 else 200, 6)

	if touch then
		local spots = TouchLayout.around(jumpButtonSpot())
		local attack, dodge, lock = touchButtons[1], touchButtons[2], touchButtons[3]
		place(attack, spots.Attack)
		place(dodge, spots.Dodge)
		place(lock, spots.LockOn)
		place(techniqueButton, spots.Technique)
		place(finaleButton, spots.Finale)
		attack.TextSize = math.floor(spots.Attack.size * 0.23)
		dodge.TextSize = math.floor(spots.Dodge.size * 0.24)
		lock.TextSize = math.floor(spots.LockOn.size * 0.28)
	else
		place(techniqueButton, { x = -150, y = -60, size = 64 })
		place(finaleButton, { x = -66, y = -76, size = 80 })
	end
	for _, button in touchButtons do
		button.Visible = touch
	end

	techniqueButton.Text = if inputMode == "keyboard" then "E" else ""
	finaleButton.Text = if inputMode == "keyboard" then "Q" else ""
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
			row.name.Text = Content.heroName(member.heroId, player)
			row.pip.BackgroundColor3 = rgb(ElementStyle.Elements[kit.element] or ElementStyle.Physical)
			row.fill.Size = UDim2.fromScale(math.clamp(member.hp / member.maxHp, 0, 1), 1)
			row.button.BackgroundTransparency = if active then 0.1 else 0.45
			local relay = PartyController.relayReady(slot)
			row.stroke.Color = if relay then RELAY_GOLD else PAPER
			row.stroke.Thickness = if active then 2 elseif relay then 1.5 + math.sin(now * 5) * 0.5 else 0
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

	local techniqueLeft = state.techniqueReadyAt - now
	techniqueCooldown.Text = if techniqueLeft > 0 then string.format("%.1f", techniqueLeft) else ""
	techniqueButton.BackgroundTransparency = if techniqueLeft > 0 then 0.55 else 0.15
	techniqueButton.TextTransparency = if techniqueLeft > 0 then 1 else 0
	local techniqueStroke = techniqueButton:FindFirstChildOfClass("UIStroke")
	if techniqueStroke then
		techniqueStroke.Color = color
	end

	local fraction = math.clamp(state.energy / kit.finale.energyCost, 0, 1)
	finaleFill.Size = UDim2.fromScale(1, fraction)
	finaleFill.BackgroundColor3 = color
	local ready = fraction >= 1 and now >= state.finaleReadyAt
	finaleStroke.Color = if ready then color else Color3.fromRGB(120, 120, 130)
	finaleStroke.Thickness = if ready then 3.5 + math.sin(now * 6) else 2

	local charges = MovementController.getDodgeCharges()
	for index, pip in dodgePips do
		pip.BackgroundTransparency = if index <= charges then 0.1 else 0.75
	end

	local stamina, max = MovementController.getStamina()
	staminaBar.Visible = stamina < max - 0.5
	staminaFill.Size = UDim2.fromScale(math.clamp(stamina / max, 0, 1), 1)
	staminaFill.BackgroundColor3 = if stamina < 40 then Color3.fromRGB(255, 120, 90) else STAMINA
end

-- Health, status, Composure and the attack glint above each enemy, driven by the attributes
-- EnemyService publishes.
local function attachEnemyBar(model: Instance)
	local root = model:FindFirstChild("HumanoidRootPart") or model:WaitForChild("HumanoidRootPart", 5)
	if not root or not model:IsA("Model") or not root:IsA("BasePart") then
		return
	end
	local elite = model:GetAttribute("MaxComposure") ~= nil
	local billboard = make("BillboardGui", {
		Name = "EnemyBar",
		Adornee = root,
		Size = UDim2.fromOffset(if elite then 160 else 110, if elite then 68 else 52),
		StudsOffset = Vector3.new(0, root.Size.Y * 2.1 + 1.4, 0),
		MaxDistance = 90,
		AlwaysOnTop = true,
	}, root)
	local glint = make("TextLabel", {
		Size = UDim2.new(1, 0, 0, 24),
		BackgroundTransparency = 1,
		Font = Enum.Font.GothamBlack,
		TextScaled = true,
		TextStrokeTransparency = 0.3,
		Text = "",
		Visible = false,
	}, billboard)
	local name = make("TextLabel", {
		Size = UDim2.new(1, 0, 0, 12),
		Position = UDim2.fromOffset(0, 26),
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
		UDim2.fromOffset(0, 40),
		Vector2.zero,
		Color3.fromRGB(235, 80, 70)
	)
	local status = make("TextLabel", {
		Size = UDim2.fromOffset(16, 16),
		Position = UDim2.new(1, 3, 0, 36),
		BackgroundTransparency = 1,
		TextScaled = true,
		Text = "",
	}, billboard)
	local composureFill: Frame? = nil
	local rattled: TextLabel? = nil
	if elite then
		local _, composure =
			bar(billboard, UDim2.new(1, 0, 0, 5), UDim2.fromOffset(0, 50), Vector2.zero, RELAY_GOLD)
		composureFill = composure
		rattled = make("TextLabel", {
			Size = UDim2.new(1, 0, 0, 10),
			Position = UDim2.fromOffset(0, 57),
			BackgroundTransparency = 1,
			TextColor3 = RELAY_GOLD,
			TextStrokeTransparency = 0.3,
			Font = Enum.Font.GothamBlack,
			TextSize = 10,
			Text = "RATTLED",
			Visible = false,
		}, billboard)
	end

	local function update()
		local health = model:GetAttribute("Health") :: number? or 0
		local maxHealth = model:GetAttribute("MaxHealth") :: number? or 1
		fill.Size = UDim2.fromScale(math.clamp(health / maxHealth, 0, 1), 1)
		local element = model:GetAttribute("Status")
		local icon = type(element) == "string" and ElementStyle.Icons[element]
		status.Text = if icon then icon else ""
		local values = type(element) == "string" and ElementStyle.Elements[element]
		if values then
			status.TextColor3 = rgb(values)
		end
		local frozen = model:GetAttribute("Frozen") == true
		local locked = model:GetAttribute("Locked") == true
		name.TextColor3 = if locked or frozen then Color3.fromRGB(170, 240, 255) else PAPER
		local telegraph = model:GetAttribute("Telegraph")
		local style = type(telegraph) == "string" and GLINTS[telegraph]
		glint.Visible = style ~= nil and style ~= false
		if style then
			glint.Text = style.symbol
			glint.TextColor3 = style.color
		end
		if composureFill and rattled then
			local composure = model:GetAttribute("Composure") :: number? or 0
			local max = model:GetAttribute("MaxComposure") :: number? or 1
			composureFill.Size = UDim2.fromScale(math.clamp(composure / max, 0, 1), 1)
			rattled.Visible = model:GetAttribute("Rattled") == true
		end
	end
	for _, attribute in { "Health", "Status", "Frozen", "Locked", "Telegraph", "Composure", "Rattled" } do
		model:GetAttributeChangedSignal(attribute):Connect(update)
	end
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

	-- Re-place the touch buttons when Roblox's jump button appears or moves, or the screen changes
	-- size (turning a tablet, for example).
	local function watchJumpButton(instance: Instance)
		if instance.Name == "JumpButton" and instance:IsA("GuiObject") then
			instance:GetPropertyChangedSignal("AbsolutePosition"):Connect(applyLayout)
			instance:GetPropertyChangedSignal("AbsoluteSize"):Connect(applyLayout)
			applyLayout()
		end
	end
	local playerGui = gui.Parent :: Instance
	playerGui.DescendantAdded:Connect(watchJumpButton)
	for _, descendant in playerGui:GetDescendants() do
		watchJumpButton(descendant)
	end
	gui:GetPropertyChangedSignal("AbsoluteSize"):Connect(applyLayout)

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
