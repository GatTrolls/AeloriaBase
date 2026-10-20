--!strict
--[[
	UIController

	Owns the interface's ScreenGui and everything that sits above the world: full-screen menus
	(the Notebook and its pages), toasts and modal questions.

	  UI.register(id, build)   build(ctx) returns { root, open(params), close() }
	  UI.open(id, params)      shows a screen and hands the game's input over to it
	  UI.close()               closes the open screen
	  UI.toggle(id, params)
	  UI.isOpen(id?)
	  UI.toast({ text, icon, color, seconds })
	  UI.modal({ title, body, confirm, cancel, onConfirm, onCancel })

	While a screen is open the cursor is free, the character stops listening to movement and
	combat input, and the combat HUD hides. Everything is laid out for a 600 px tall canvas and
	scaled to the real screen, with the player's text-size setting folded in.
]]

local ContextActionService = game:GetService("ContextActionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Content = require(ReplicatedStorage.Shared.Content)

local CameraController = require(script.Parent.CameraController)
local MovementController = require(script.Parent.MovementController)
local ProfileController = require(script.Parent.ProfileController)
local StarfallController = require(script.Parent.StarfallController)

local Kit = require(script.Parent.Parent.UI.Kit)
local Theme = require(script.Parent.Parent.UI.Theme)

export type Instance_ = {
	root: GuiObject,
	open: ((params: any?) -> ())?,
	close: (() -> ())?,
}

export type Context = {
	-- The safe, scaled area screens lay themselves out in.
	canvas: Frame,
	scale: () -> number,
	profile: typeof(ProfileController),
	starfall: typeof(StarfallController),
	ui: any,
}

local UIController = {
	-- Set by the Notebook so the shortcut keys know which tab is showing.
	currentTab = "",
	notebookButton = nil :: GuiObject?,
}

local player = Players.LocalPlayer

local gui: ScreenGui
local canvas: Frame
local screensLayer: Frame
local toastLayer: Frame
local modalLayer: Frame
local uiScale: UIScale

local builders: { [string]: (Context) -> Instance_ } = {}
local instances: { [string]: Instance_ } = {}
local openId: string? = nil
local listeners: { (string?) -> () } = {}
local toasts: { Frame } = {}
local context: Context

local BLOCKED_KEYS = {
	Enum.KeyCode.Space,
	Enum.KeyCode.E,
	Enum.KeyCode.Q,
	Enum.KeyCode.T,
	Enum.KeyCode.One,
	Enum.KeyCode.Two,
	Enum.KeyCode.Three,
	Enum.KeyCode.Four,
	Enum.KeyCode.LeftShift,
	Enum.KeyCode.ButtonA,
	Enum.KeyCode.ButtonX,
	Enum.KeyCode.ButtonY,
	Enum.KeyCode.ButtonR1,
	Enum.KeyCode.ButtonR3,
	Enum.UserInputType.MouseButton2,
	Enum.UserInputType.MouseButton3,
}

local function currentScale(): number
	local height = gui.AbsoluteSize.Y
	local base = height / Theme.BaseHeight
	local profile = ProfileController.get()
	local settings = profile and profile.settings
	local textScale = if settings and type(settings.textScale) == "number" then settings.textScale else 1
	return math.clamp(base, Theme.MinScale, Theme.MaxScale) * math.clamp(textScale, 0.8, 1.4)
end

local function relayout()
	local scale = currentScale()
	uiScale.Scale = scale
	local size = gui.AbsoluteSize
	canvas.Size = UDim2.fromOffset(size.X / scale, size.Y / scale)
end

function UIController.scale(): number
	return uiScale.Scale
end

function UIController.layer(name: string): Frame
	if name == "toasts" then
		return toastLayer
	elseif name == "modals" then
		return modalLayer
	end
	return screensLayer
end

function UIController.register(id: string, build: (Context) -> Instance_)
	builders[id] = build
end

function UIController.isOpen(id: string?): boolean
	if id then
		return openId == id
	end
	return openId ~= nil
end

function UIController.onOpenChanged(listener: (string?) -> ()): () -> ()
	table.insert(listeners, listener)
	return function()
		local index = table.find(listeners, listener)
		if index then
			table.remove(listeners, index)
		end
	end
end

local function setGameplayInput(enabled: boolean)
	CameraController.setUiOpen(not enabled)
	MovementController.setControlsEnabled(enabled)
	if enabled then
		ContextActionService:UnbindAction("FarbornUIBlock")
	else
		ContextActionService:BindActionAtPriority("FarbornUIBlock", function()
			return Enum.ContextActionResult.Sink
		end, false, Enum.ContextActionPriority.High.Value + 200, unpack(BLOCKED_KEYS :: { any }))
	end
	local hud = player:FindFirstChild("PlayerGui") and player.PlayerGui:FindFirstChild("FarbornHud")
	if hud and hud:IsA("ScreenGui") then
		hud.Enabled = enabled
	end
end

local function instanceFor(id: string): Instance_?
	local existing = instances[id]
	if existing then
		return existing
	end
	local build = builders[id]
	if not build then
		return nil
	end
	local made = build(context)
	made.root.Visible = false
	made.root.Parent = screensLayer
	instances[id] = made
	return made
end

function UIController.close()
	local id = openId
	if not id then
		return
	end
	openId = nil
	local made = instances[id]
	if made then
		if made.close then
			made.close()
		end
		made.root.Visible = false
	end
	setGameplayInput(true)
	for _, listener in table.clone(listeners) do
		task.spawn(listener, nil)
	end
end

function UIController.open(id: string, params: any?)
	if openId == id then
		local same = instances[id]
		if same and same.open then
			same.open(params)
		end
		return
	end
	if openId then
		local previous = instances[openId]
		if previous then
			if previous.close then
				previous.close()
			end
			previous.root.Visible = false
		end
	end
	local made = instanceFor(id)
	if not made then
		warn("[UI] unknown screen", id)
		return
	end
	local wasClosed = openId == nil
	openId = id
	made.root.Visible = true
	if made.open then
		made.open(params)
	end
	if wasClosed then
		setGameplayInput(false)
	end
	for _, listener in table.clone(listeners) do
		task.spawn(listener, id)
	end
end

function UIController.toggle(id: string, params: any?)
	if openId == id then
		UIController.close()
	else
		UIController.open(id, params)
	end
end

-- Pop-up message near the top of the screen. options: text, icon, color, seconds, style.
function UIController.toast(options: { text: string, icon: string?, color: Color3?, seconds: number? })
	local seconds = options.seconds or 2.6
	local card = Kit.panel({
		style = "ink",
		size = UDim2.fromOffset(300, 44),
		radius = 22,
		parent = toastLayer,
		name = "Toast",
	})
	local row = Kit.frame({ parent = card, size = UDim2.fromScale(1, 1) })
	Kit.padding(row, 12, 0)
	Kit.list(
		row,
		Enum.FillDirection.Horizontal,
		8,
		Enum.HorizontalAlignment.Left,
		Enum.VerticalAlignment.Center
	)
	if options.icon then
		Kit.icon({
			parent = row,
			name = options.icon,
			size = UDim2.fromOffset(26, 26),
			color = options.color,
			order = 1,
		})
	end
	Kit.text({
		parent = row,
		text = options.text,
		font = "bold",
		textSize = Theme.TextSize.small,
		color = Theme.Color.textLight,
		size = UDim2.new(1, -36, 1, 0),
		order = 2,
		wrap = true,
	})
	card.Position = UDim2.new(0.5, 0, 0, -60)
	card.AnchorPoint = Vector2.new(0.5, 0)
	table.insert(toasts, 1, card)
	-- Stack: newest on top, older ones slide down.
	for index, toast in toasts do
		Kit.tween(toast, Theme.Tween.pop, { Position = UDim2.new(0.5, 0, 0, 12 + (index - 1) * 52) })
	end
	if #toasts > 3 then
		local oldest = table.remove(toasts) :: Frame
		oldest:Destroy()
	end
	task.delay(seconds, function()
		local index = table.find(toasts, card)
		if index then
			table.remove(toasts, index)
		end
		if card.Parent then
			Kit.tween(card, Theme.Tween.normal, { Position = UDim2.new(0.5, 0, 0, -70) })
			task.delay(0.25, function()
				card:Destroy()
			end)
		end
		for i, toast in toasts do
			Kit.tween(toast, Theme.Tween.normal, { Position = UDim2.new(0.5, 0, 0, 12 + (i - 1) * 52) })
		end
	end)
end

-- A question over everything. options: title, body, confirm, cancel, onConfirm, onCancel.
function UIController.modal(options: {
	title: string,
	body: string,
	confirm: string?,
	cancel: string?,
	onConfirm: (() -> ())?,
	onCancel: (() -> ())?,
})
	local dim = Kit.frame({
		parent = modalLayer,
		size = UDim2.fromScale(1, 1),
		color = Theme.Color.black,
		transparency = 0.45,
		name = "Modal",
	})
	dim.Active = true
	local card = Kit.panel({
		style = "paper",
		parent = dim,
		size = UDim2.fromOffset(420, 220),
		position = UDim2.fromScale(0.5, 0.5),
		anchor = Vector2.new(0.5, 0.5),
	})
	Kit.padding(card, 22, 18)
	Kit.text({
		parent = card,
		text = options.title,
		font = "title",
		textSize = Theme.TextSize.heading,
		color = Theme.Color.textDark,
		size = UDim2.new(1, 0, 0, 36),
	})
	Kit.text({
		parent = card,
		text = options.body,
		font = "body",
		textSize = Theme.TextSize.body,
		color = Theme.Color.textDark,
		size = UDim2.new(1, 0, 1, -110),
		position = UDim2.fromOffset(0, 44),
		wrap = true,
		valign = Enum.TextYAlignment.Top,
	})
	local function finish(callback: (() -> ())?)
		dim:Destroy()
		if callback then
			callback()
		end
	end
	local buttons =
		Kit.frame({ parent = card, size = UDim2.new(1, 0, 0, 44), position = UDim2.new(0, 0, 1, -44) })
	Kit.list(
		buttons,
		Enum.FillDirection.Horizontal,
		12,
		Enum.HorizontalAlignment.Right,
		Enum.VerticalAlignment.Center
	)
	if options.cancel then
		Kit.button({
			parent = buttons,
			text = options.cancel,
			style = "paper",
			size = UDim2.fromOffset(130, 42),
			order = 1,
			onClick = function()
				finish(options.onCancel)
			end,
		})
	end
	Kit.button({
		parent = buttons,
		text = options.confirm or Content.text("common.ok"),
		style = "primary",
		size = UDim2.fromOffset(130, 42),
		order = 2,
		onClick = function()
			finish(options.onConfirm)
		end,
	})
	Kit.popIn(card, 0.86)
end

function UIController:Init()
	gui = Instance.new("ScreenGui")
	gui.Name = "FarbornUI"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.DisplayOrder = 20
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	gui.SafeAreaCompatibility = Enum.SafeAreaCompatibility.None
	gui.ScreenInsets = Enum.ScreenInsets.None

	canvas = Instance.new("Frame")
	canvas.Name = "Canvas"
	canvas.BackgroundTransparency = 1
	canvas.BorderSizePixel = 0
	canvas.Parent = gui

	-- The scale goes on the canvas (a UIScale on a ScreenGui does nothing); the canvas is sized to
	-- the screen divided by the scale, so it fills the screen and its children lay out in 600 px units.
	uiScale = Instance.new("UIScale")
	uiScale.Parent = canvas

	screensLayer = Kit.frame({ parent = canvas, size = UDim2.fromScale(1, 1), name = "Screens" })
	toastLayer = Kit.frame({ parent = canvas, size = UDim2.fromScale(1, 1), name = "Toasts", z = 50 })
	modalLayer = Kit.frame({ parent = canvas, size = UDim2.fromScale(1, 1), name = "Modals", z = 100 })

	context = {
		canvas = screensLayer,
		scale = UIController.scale,
		profile = ProfileController,
		starfall = StarfallController,
		ui = UIController,
	}
end

function UIController:Start()
	gui.Parent = player:WaitForChild("PlayerGui")
	relayout()
	gui:GetPropertyChangedSignal("AbsoluteSize"):Connect(relayout)
	ProfileController.onChanged(function()
		-- The text-size setting lives in the profile.
		local scale = currentScale()
		if math.abs(scale - uiScale.Scale) > 0.001 then
			relayout()
		end
	end)

	-- Escape (or B on a gamepad) closes whatever is open.
	ContextActionService:BindActionAtPriority("FarbornUIClose", function(_, state)
		if state == Enum.UserInputState.Begin and openId then
			UIController.close()
			return Enum.ContextActionResult.Sink
		end
		return Enum.ContextActionResult.Pass
	end, false, Enum.ContextActionPriority.High.Value + 300, Enum.KeyCode.Escape, Enum.KeyCode.ButtonB)

	-- N opens the Notebook where the player left it; M, B and P jump to a tab.
	local function bindTab(action: string, tab: string, ...: Enum.KeyCode)
		ContextActionService:BindAction(action, function(_, state)
			if state == Enum.UserInputState.Begin then
				if openId == "notebook" and UIController.currentTab == tab then
					UIController.close()
				else
					UIController.open("notebook", { tab = tab })
				end
			end
			return Enum.ContextActionResult.Sink
		end, false, ...)
	end
	ContextActionService:BindAction("FarbornNotebook", function(_, state)
		if state == Enum.UserInputState.Begin then
			UIController.toggle("notebook")
		end
		return Enum.ContextActionResult.Sink
	end, false, Enum.KeyCode.N, Enum.KeyCode.ButtonSelect)
	bindTab("FarbornMap", "map", Enum.KeyCode.M)
	bindTab("FarbornBag", "bag", Enum.KeyCode.B)
	bindTab("FarbornParty", "party", Enum.KeyCode.P)

	-- A small Notebook button that touch players (and everyone) can tap.
	local button = Kit.iconButton({
		parent = canvas,
		name = "NotebookButton",
		icon = "notebook",
		style = "dark",
		diameter = 44,
		position = UDim2.fromOffset(80, 10),
		z = 5,
		onClick = function()
			UIController.toggle("notebook")
		end,
	})
	button.Visible = true
	UIController.notebookButton = button
	UIController.onOpenChanged(function(id)
		button.Visible = id == nil
	end)
end

return UIController
