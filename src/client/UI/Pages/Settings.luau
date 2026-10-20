--!strict
--[[
	Settings page

	Assist mode, text size, reduced motion, colour-blind mode, volumes and HUD auto-hide. Every
	change is sent to SettingsService, which validates and stores it in the profile; the page
	redraws from the profile snapshot, so what you see is what is saved.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Content = require(ReplicatedStorage.Shared.Content)
local Net = require(ReplicatedStorage.Shared.Net)

local Kit = require(script.Parent.Parent.Kit)
local Theme = require(script.Parent.Parent.Theme)

local Color = Theme.Color

local Settings = {}

Settings.id = "settings"
Settings.icon = "settings"

local MODES = {
	{ id = "off", text = "Off" },
	{ id = "deuteranopia", text = "Green" },
	{ id = "protanopia", text = "Red" },
	{ id = "tritanopia", text = "Blue" },
}

function Settings.build(parent: Frame, ctx: any)
	local root = Kit.frame({ parent = parent, size = UDim2.fromScale(1, 1), name = "Settings" })
	Kit.text({
		parent = root,
		text = Content.text("settings.title"),
		font = "title",
		textSize = Theme.TextSize.title,
		color = Color.textDark,
		size = UDim2.new(1, 0, 0, 44),
	})

	local scroll =
		Kit.scroll({ parent = root, size = UDim2.new(1, 0, 1, -54), position = UDim2.fromOffset(0, 54) })
	Kit.list(scroll, Enum.FillDirection.Vertical, 10)
	Kit.padding(scroll, 2, 2)

	local refreshers: { (settings: any) -> () } = {}

	local function send(key: string, value: any)
		task.spawn(function()
			pcall(function()
				Net.func(Net.Names.SetSetting):InvokeServer(key, value)
			end)
		end)
	end

	local function row(order: number, title: string, help: string?, tall: boolean?): Frame
		local card = Kit.panel({
			style = "soft",
			parent = scroll,
			size = UDim2.new(1, -8, 0, if tall then 82 else 64),
			order = order,
			radius = 12,
		})
		card.BackgroundColor3 = Color.paperShade
		for _, child in card:GetChildren() do
			if child:IsA("UIStroke") then
				child.Color = Color.paperLine
			end
		end
		Kit.text({
			parent = card,
			text = title,
			font = "heavy",
			textSize = Theme.TextSize.label,
			color = Color.textDark,
			size = UDim2.new(0.55, 0, 0, 26),
			position = UDim2.fromOffset(16, if help then 8 else 18),
		})
		if help then
			Kit.text({
				parent = card,
				text = help,
				font = "body",
				textSize = Theme.TextSize.small,
				color = Color.textFaint,
				size = UDim2.new(0.55, 0, 0, 22),
				position = UDim2.fromOffset(16, 34),
				wrap = true,
				valign = Enum.TextYAlignment.Top,
			})
		end
		return card
	end

	local function toggleRow(order: number, key: string, title: string, help: string?)
		local card = row(order, title, help)
		local toggle = Kit.toggle({
			parent = card,
			position = UDim2.new(1, -16, 0.5, 0),
			anchor = Vector2.new(1, 0.5),
			onChanged = function(on: boolean)
				send(key, on)
			end,
		})
		table.insert(refreshers, function(settings: any)
			toggle.set(settings[key] == true, true)
		end)
	end

	local function sliderRow(
		order: number,
		key: string,
		title: string,
		min: number,
		max: number,
		step: number?
	)
		local card = row(order, title)
		local slider = Kit.slider({
			parent = card,
			size = UDim2.new(0.38, 0, 0, 28),
			position = UDim2.new(1, -16, 0.5, 0),
			anchor = Vector2.new(1, 0.5),
			min = min,
			max = max,
			step = step,
			onChanged = function(value: number)
				send(key, value)
			end,
		})
		table.insert(refreshers, function(settings: any)
			if type(settings[key]) == "number" then
				slider.set(settings[key])
			end
		end)
	end

	toggleRow(1, "assist", Content.text("settings.assist"), Content.text("settings.assistHelp"))
	sliderRow(2, "textScale", Content.text("settings.textScale"), 0.8, 1.4, 0.05)
	toggleRow(
		3,
		"reducedMotion",
		Content.text("settings.reducedMotion"),
		Content.text("settings.reducedMotionHelp")
	)

	-- Colour-blind mode as a row of choices.
	local modeCard = row(4, Content.text("settings.colorblind"))
	local modeRow = Kit.frame({
		parent = modeCard,
		size = UDim2.new(0.5, 0, 0, 38),
		position = UDim2.new(1, -16, 0.5, 0),
		anchor = Vector2.new(1, 0.5),
	})
	Kit.list(
		modeRow,
		Enum.FillDirection.Horizontal,
		6,
		Enum.HorizontalAlignment.Right,
		Enum.VerticalAlignment.Center
	)
	local modeButtons: { [string]: TextButton } = {}
	for index, mode in MODES do
		local button = Kit.button({
			parent = modeRow,
			text = mode.text,
			size = UDim2.fromOffset(78, 36),
			style = "paper",
			textSize = Theme.TextSize.small,
			order = index,
			onClick = function()
				send("colorblind", mode.id)
			end,
		})
		modeButtons[mode.id] = button
	end
	table.insert(refreshers, function(settings: any)
		for id, button in modeButtons do
			local selected = settings.colorblind == id
			button.BackgroundColor3 = if selected then Color.brass else Color.paper
		end
	end)

	sliderRow(5, "musicVolume", Content.text("settings.music"), 0, 1, 0.05)
	sliderRow(6, "sfxVolume", Content.text("settings.sfx"), 0, 1, 0.05)
	toggleRow(7, "hudAutoHide", Content.text("settings.hudAutoHide"))

	local unsubscribe: (() -> ())? = nil
	return {
		root = root,
		onShow = function()
			if not unsubscribe then
				unsubscribe = ctx.profile.onChanged(function(snapshot: any)
					local settings = snapshot and snapshot.settings
					if settings then
						for _, refresh in refreshers do
							refresh(settings)
						end
					end
				end)
			end
		end,
		onHide = nil,
	}
end

return Settings
