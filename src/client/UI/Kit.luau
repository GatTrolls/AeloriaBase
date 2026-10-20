--!strict
--[[
	Kit

	The building blocks every screen is made of: panels, buttons, tabs, bars, switches, sliders
	and scrolling lists, all drawn in the notebook theme (Theme.luau) and built in code, so the
	interface needs no art assets beyond the icon atlas.

	Every constructor takes one props table and returns the instance. Common props:

	  parent, name, size, position, anchor, order (LayoutOrder), z (ZIndex), visible

	Buttons give feedback the way a phone game should: a quick squash on press, a lift on hover
	and a pop when something appears. Nothing here talks to the server; screens decide that.
]]

local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local Icons = require(script.Parent.Icons)
local Theme = require(script.Parent.Theme)

local Color = Theme.Color

export type Props = { [string]: any }

local Kit = {}

-- ---------------------------------------------------------------------------------------------
-- Helpers
-- ---------------------------------------------------------------------------------------------

local function place(instance: GuiObject, props: Props)
	if props.name then
		instance.Name = props.name
	end
	if props.size then
		instance.Size = props.size
	end
	if props.position then
		instance.Position = props.position
	end
	if props.anchor then
		instance.AnchorPoint = props.anchor
	end
	if props.order then
		instance.LayoutOrder = props.order
	end
	if props.z then
		instance.ZIndex = props.z
	end
	if props.visible ~= nil then
		instance.Visible = props.visible
	end
	-- Parent last, so the engine lays out an instance that is already finished.
	if props.parent then
		instance.Parent = props.parent
	end
end

function Kit.tween(instance: Instance, info: TweenInfo, goal: { [string]: any }): Tween
	local tween = TweenService:Create(instance, info, goal)
	tween:Play()
	return tween
end

function Kit.corner(parent: Instance, radius: number?): UICorner
	local corner = Instance.new("UICorner")
	corner.CornerRadius = if radius == nil
		then UDim.new(0, Theme.Radius.medium)
		elseif radius < 0 then UDim.new(1, 0)
		else UDim.new(0, radius)
	corner.Parent = parent
	return corner
end

function Kit.stroke(parent: Instance, color: Color3?, thickness: number?, transparency: number?): UIStroke
	local stroke = Instance.new("UIStroke")
	stroke.Color = color or Color.textDark
	stroke.Thickness = thickness or 2
	stroke.Transparency = transparency or 0
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	stroke.LineJoinMode = Enum.LineJoinMode.Round
	stroke.Parent = parent
	return stroke
end

function Kit.gradient(parent: Instance, top: Color3, bottom: Color3, rotation: number?): UIGradient
	local gradient = Instance.new("UIGradient")
	gradient.Color = ColorSequence.new(top, bottom)
	gradient.Rotation = rotation or 90
	gradient.Parent = parent
	return gradient
end

function Kit.padding(parent: Instance, all: number, vertical: number?): UIPadding
	local padding = Instance.new("UIPadding")
	local v = vertical or all
	padding.PaddingLeft = UDim.new(0, all)
	padding.PaddingRight = UDim.new(0, all)
	padding.PaddingTop = UDim.new(0, v)
	padding.PaddingBottom = UDim.new(0, v)
	padding.Parent = parent
	return padding
end

function Kit.list(
	parent: Instance,
	direction: Enum.FillDirection?,
	gap: number?,
	horizontal: Enum.HorizontalAlignment?,
	vertical: Enum.VerticalAlignment?
): UIListLayout
	local layout = Instance.new("UIListLayout")
	layout.FillDirection = direction or Enum.FillDirection.Vertical
	layout.Padding = UDim.new(0, gap or 8)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.HorizontalAlignment = horizontal or Enum.HorizontalAlignment.Left
	layout.VerticalAlignment = vertical or Enum.VerticalAlignment.Top
	layout.Parent = parent
	return layout
end

function Kit.grid(parent: Instance, cell: UDim2, gap: number?): UIGridLayout
	local grid = Instance.new("UIGridLayout")
	grid.CellSize = cell
	grid.CellPadding = UDim2.fromOffset(gap or 8, gap or 8)
	grid.SortOrder = Enum.SortOrder.LayoutOrder
	grid.HorizontalAlignment = Enum.HorizontalAlignment.Left
	grid.Parent = parent
	return grid
end

-- ---------------------------------------------------------------------------------------------
-- Basics
-- ---------------------------------------------------------------------------------------------

function Kit.frame(props: Props): Frame
	local frame = Instance.new("Frame")
	frame.BackgroundTransparency = if props.color then (props.transparency or 0) else 1
	frame.BackgroundColor3 = props.color or Color.paper
	frame.BorderSizePixel = 0
	if props.clip then
		frame.ClipsDescendants = true
	end
	if props.radius then
		Kit.corner(frame, props.radius)
	end
	place(frame, props)
	return frame
end

function Kit.text(props: Props): TextLabel
	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.BorderSizePixel = 0
	label.Text = tostring(props.text or "")
	label.FontFace = Theme.Font[props.font or "body"]
	label.TextSize = props.textSize or Theme.TextSize.body
	label.TextColor3 = props.color or Color.textLight
	label.TextXAlignment = props.align or Enum.TextXAlignment.Left
	label.TextYAlignment = props.valign or Enum.TextYAlignment.Center
	label.TextWrapped = props.wrap == true
	label.RichText = props.rich == true
	label.TextTruncate = if props.truncate then Enum.TextTruncate.AtEnd else Enum.TextTruncate.None
	if props.stroke then
		label.TextStrokeTransparency = props.strokeTransparency or 0.6
		label.TextStrokeColor3 = props.strokeColor or Color.black
	end
	if props.autoSize then
		label.AutomaticSize = props.autoSize
	end
	place(label, props)
	return label
end

function Kit.image(props: Props): ImageLabel
	local image = Instance.new("ImageLabel")
	image.BackgroundTransparency = 1
	image.BorderSizePixel = 0
	image.Image = props.image or ""
	image.ImageColor3 = props.color or Color3.new(1, 1, 1)
	image.ImageTransparency = props.transparency or 0
	image.ScaleType = props.scaleType or Enum.ScaleType.Fit
	if props.rectOffset then
		image.ImageRectOffset = props.rectOffset
	end
	if props.rectSize then
		image.ImageRectSize = props.rectSize
	end
	place(image, props)
	return image
end

-- An icon from the atlas, or a text glyph until the atlas exists. `color` tints either.
function Kit.icon(props: Props): GuiObject
	local name: string = props.name
	local size = props.size or UDim2.fromOffset(28, 28)
	local probe = Instance.new("ImageLabel")
	if Icons.apply(probe, name) then
		probe.BackgroundTransparency = 1
		probe.BorderSizePixel = 0
		-- Icons drawn in their own colours keep them unless the caller insists (props.tint).
		probe.ImageColor3 = if Icons.isColored(name) and not props.tint
			then Color3.new(1, 1, 1)
			else (props.color or Color3.new(1, 1, 1))
		probe.ScaleType = Enum.ScaleType.Fit
		place(probe, {
			size = size,
			name = props.name,
			parent = props.parent,
			position = props.position,
			anchor = props.anchor,
			order = props.order,
			z = props.z,
			visible = props.visible,
		})
		return probe
	end
	probe:Destroy()
	local glyph = Kit.text({
		text = Icons.glyph(name),
		font = "heavy",
		textSize = props.glyphSize or 20,
		color = props.color or Color.textLight,
		align = Enum.TextXAlignment.Center,
		name = props.name,
		size = size,
		position = props.position,
		anchor = props.anchor,
		order = props.order,
		z = props.z,
		visible = props.visible,
		parent = props.parent,
	})
	return glyph
end

-- ---------------------------------------------------------------------------------------------
-- Panels
-- ---------------------------------------------------------------------------------------------

-- style: "paper" (a notebook page), "ink" (a dark card), "glass" (see-through HUD card),
-- "soft" (a slightly lighter dark card for rows).
function Kit.panel(props: Props): Frame
	local style = props.style or "paper"
	local frame = Instance.new("Frame")
	frame.BorderSizePixel = 0
	local radius = props.radius or Theme.Radius.medium
	if style == "paper" then
		frame.BackgroundColor3 = Color.paper
		Kit.gradient(frame, Color3.fromRGB(70, 88, 140), Color3.fromRGB(34, 44, 82), 90)
		Kit.stroke(frame, Color.textDark, props.strokeThickness or 2.5)
	elseif style == "ink" then
		frame.BackgroundColor3 = Color.ink
		Kit.gradient(frame, Color3.fromRGB(255, 255, 255), Color3.fromRGB(205, 210, 230), 90)
		Kit.stroke(frame, Color.brass, props.strokeThickness or 2)
	elseif style == "soft" then
		frame.BackgroundColor3 = Color.inkSoft
		Kit.stroke(frame, Color.inkLine, props.strokeThickness or 1.5, 0.15)
	else -- glass
		frame.BackgroundColor3 = Color.night
		frame.BackgroundTransparency = props.transparency or 0.28
		Kit.stroke(frame, Color.textLight, props.strokeThickness or 1.5, 0.7)
	end
	if props.transparency and style ~= "glass" then
		frame.BackgroundTransparency = props.transparency
	end
	if props.clip then
		frame.ClipsDescendants = true
	end
	Kit.corner(frame, radius)
	place(frame, props)
	return frame
end

-- A page header strip: title on the left, optional subtitle, used at the top of tab pages.
function Kit.header(props: Props): Frame
	local frame = Kit.frame({
		size = props.size or UDim2.new(1, 0, 0, 44),
		parent = props.parent,
		order = props.order,
		name = props.name or "Header",
	})
	Kit.text({
		parent = frame,
		text = props.text,
		font = "title",
		textSize = props.textSize or Theme.TextSize.heading,
		color = props.color or Color.textDark,
		size = UDim2.fromScale(1, 1),
	})
	return frame
end

function Kit.divider(props: Props): Frame
	return Kit.frame({
		parent = props.parent,
		order = props.order,
		size = props.size or UDim2.new(1, 0, 0, 2),
		color = props.color or Color.paperLine,
		transparency = props.transparency or 0.2,
	})
end

-- ---------------------------------------------------------------------------------------------
-- Buttons
-- ---------------------------------------------------------------------------------------------

local BUTTON_STYLES: { [string]: { fill: Color3, text: Color3, stroke: Color3 } } = {
	primary = { fill = Color.brass, text = Color3.fromRGB(46, 32, 14), stroke = Color3.fromRGB(70, 48, 20) },
	paper = { fill = Color.paper, text = Color.textDark, stroke = Color.textDark },
	dark = { fill = Color.inkSoft, text = Color.textLight, stroke = Color.inkLine },
	ghost = { fill = Color.ink, text = Color.textLight, stroke = Color.inkLine },
	danger = { fill = Color.coral, text = Color3.fromRGB(60, 22, 18), stroke = Color3.fromRGB(86, 34, 28) },
	success = { fill = Color.leaf, text = Color3.fromRGB(24, 52, 28), stroke = Color3.fromRGB(34, 74, 40) },
}

local function lighten(color: Color3, amount: number): Color3
	return color:Lerp(Color3.new(1, 1, 1), amount)
end

-- A pressable button. props: text, icon, style, textSize, onClick, disabled, badge.
function Kit.button(props: Props): TextButton
	local style = BUTTON_STYLES[props.style or "primary"] or BUTTON_STYLES.primary
	local button = Instance.new("TextButton")
	button.AutoButtonColor = false
	button.BorderSizePixel = 0
	button.Text = ""
	button.BackgroundColor3 = style.fill
	button.Size = props.size or UDim2.fromOffset(160, 44)
	Kit.corner(button, props.radius or Theme.Radius.medium)
	Kit.gradient(button, Color3.fromRGB(255, 255, 255), Color3.fromRGB(208, 208, 208), 90)
	local stroke = Kit.stroke(button, style.stroke, 2)

	local scale = Instance.new("UIScale")
	scale.Parent = button

	local row = Kit.frame({ parent = button, size = UDim2.fromScale(1, 1) })
	Kit.list(
		row,
		Enum.FillDirection.Horizontal,
		6,
		Enum.HorizontalAlignment.Center,
		Enum.VerticalAlignment.Center
	)
	if props.icon then
		Kit.icon({
			parent = row,
			name = props.icon,
			size = UDim2.fromOffset(props.iconSize or 24, props.iconSize or 24),
			color = props.iconColor,
			order = 1,
			glyphSize = 18,
		})
	end
	local label = Kit.text({
		parent = row,
		text = props.text or "",
		font = props.font or "heavy",
		textSize = props.textSize or Theme.TextSize.label,
		color = style.text,
		align = Enum.TextXAlignment.Center,
		size = UDim2.fromScale(0, 1),
		autoSize = Enum.AutomaticSize.X,
		order = 2,
		name = "Label",
	})

	local disabled = props.disabled == true
	local function paint()
		if disabled then
			button.BackgroundColor3 = Color.paperShade:Lerp(Color.inkLine, 0.35)
			label.TextColor3 = Color.textFaint
			stroke.Color = Color.textFaint
		else
			button.BackgroundColor3 = style.fill
			label.TextColor3 = style.text
			stroke.Color = style.stroke
		end
	end
	paint()

	button.MouseEnter:Connect(function()
		if not disabled then
			Kit.tween(button, Theme.Tween.fast, { BackgroundColor3 = lighten(style.fill, 0.18) })
		end
	end)
	button.MouseLeave:Connect(function()
		if not disabled then
			Kit.tween(button, Theme.Tween.fast, { BackgroundColor3 = style.fill })
		end
		Kit.tween(scale, Theme.Tween.fast, { Scale = 1 })
	end)
	button.InputBegan:Connect(function(input)
		local kind = input.UserInputType
		if not disabled and (kind == Enum.UserInputType.MouseButton1 or kind == Enum.UserInputType.Touch) then
			Kit.tween(scale, Theme.Tween.fast, { Scale = 0.94 })
		end
	end)
	button.InputEnded:Connect(function(input)
		local kind = input.UserInputType
		if kind == Enum.UserInputType.MouseButton1 or kind == Enum.UserInputType.Touch then
			Kit.tween(scale, Theme.Tween.pop, { Scale = 1 })
		end
	end)
	button.Activated:Connect(function()
		if not disabled and props.onClick then
			props.onClick()
		end
	end)

	button:SetAttribute("Disabled", disabled)
	button:GetAttributeChangedSignal("Disabled"):Connect(function()
		disabled = button:GetAttribute("Disabled") == true
		paint()
	end)

	if props.badge then
		local badge = Kit.frame({
			parent = button,
			size = UDim2.fromOffset(16, 16),
			position = UDim2.new(1, -4, 0, 4),
			anchor = Vector2.new(1, 0),
			color = Color.danger,
			radius = -1,
			name = "Badge",
		})
		Kit.stroke(badge, Color.textLight, 1.5)
	end

	place(button, {
		name = props.name,
		position = props.position,
		anchor = props.anchor,
		order = props.order,
		z = props.z,
		visible = props.visible,
		parent = props.parent,
	})
	return button
end

function Kit.setDisabled(button: GuiObject, disabled: boolean)
	button:SetAttribute("Disabled", disabled)
end

function Kit.setLabel(button: GuiObject, text: string)
	local label = button:FindFirstChild("Label", true) :: TextLabel?
	if label then
		label.Text = text
	end
end

-- A round button with just an icon (close, back, settings).
function Kit.iconButton(props: Props): TextButton
	local style = BUTTON_STYLES[props.style or "dark"] or BUTTON_STYLES.dark
	local size = props.diameter or 44
	local button = Instance.new("TextButton")
	button.AutoButtonColor = false
	button.BorderSizePixel = 0
	button.Text = ""
	button.BackgroundColor3 = style.fill
	button.Size = UDim2.fromOffset(size, size)
	Kit.corner(button, -1)
	Kit.gradient(button, Color3.fromRGB(255, 255, 255), Color3.fromRGB(208, 208, 208), 90)
	Kit.stroke(button, style.stroke, 2)
	local scale = Instance.new("UIScale")
	scale.Parent = button
	Kit.icon({
		parent = button,
		name = props.icon,
		size = UDim2.fromOffset(size * 0.6, size * 0.6),
		position = UDim2.fromScale(0.5, 0.5),
		anchor = Vector2.new(0.5, 0.5),
		color = props.color or style.text,
		glyphSize = size * 0.5,
	})
	button.MouseEnter:Connect(function()
		Kit.tween(button, Theme.Tween.fast, { BackgroundColor3 = lighten(style.fill, 0.18) })
	end)
	button.MouseLeave:Connect(function()
		Kit.tween(button, Theme.Tween.fast, { BackgroundColor3 = style.fill })
		Kit.tween(scale, Theme.Tween.fast, { Scale = 1 })
	end)
	button.InputBegan:Connect(function(input)
		local kind = input.UserInputType
		if kind == Enum.UserInputType.MouseButton1 or kind == Enum.UserInputType.Touch then
			Kit.tween(scale, Theme.Tween.fast, { Scale = 0.9 })
		end
	end)
	button.InputEnded:Connect(function(input)
		local kind = input.UserInputType
		if kind == Enum.UserInputType.MouseButton1 or kind == Enum.UserInputType.Touch then
			Kit.tween(scale, Theme.Tween.pop, { Scale = 1 })
		end
	end)
	button.Activated:Connect(function()
		if props.onClick then
			props.onClick()
		end
	end)
	place(button, {
		name = props.name,
		position = props.position,
		anchor = props.anchor,
		order = props.order,
		z = props.z,
		visible = props.visible,
		parent = props.parent,
	})
	return button
end

-- ---------------------------------------------------------------------------------------------
-- Bars, switches, sliders
-- ---------------------------------------------------------------------------------------------

export type Bar = { frame: Frame, set: (value: number, animate: boolean?) -> (), fill: Frame }

-- A rounded progress bar. `set(0..1)` moves the fill, with an optional tween.
function Kit.bar(props: Props): Bar
	local frame = Kit.frame({
		size = props.size or UDim2.new(1, 0, 0, 12),
		color = props.trackColor or Color.night,
		transparency = props.trackTransparency or 0.15,
		radius = -1,
		clip = true,
		parent = props.parent,
		order = props.order,
		position = props.position,
		anchor = props.anchor,
		name = props.name,
	})
	Kit.stroke(frame, props.outline or Color.inkLine, 1.5, 0.3)
	local fill = Kit.frame({
		parent = frame,
		size = UDim2.fromScale(0, 1),
		color = props.color or Color.brass,
		radius = -1,
		name = "Fill",
	})
	if props.gradient ~= false then
		Kit.gradient(fill, Color3.fromRGB(255, 255, 255), Color3.fromRGB(190, 190, 190), 90)
	end
	local function set(value: number, animate: boolean?)
		local goal = UDim2.fromScale(math.clamp(value, 0, 1), 1)
		if animate then
			Kit.tween(fill, Theme.Tween.normal, { Size = goal })
		else
			fill.Size = goal
		end
	end
	set(props.value or 0)
	return { frame = frame, set = set, fill = fill }
end

export type Toggle = { frame: TextButton, set: (on: boolean, silent: boolean?) -> (), get: () -> boolean }

function Kit.toggle(props: Props): Toggle
	local on = props.value == true
	local button = Instance.new("TextButton")
	button.AutoButtonColor = false
	button.Text = ""
	button.BorderSizePixel = 0
	button.Size = props.size or UDim2.fromOffset(64, 32)
	Kit.corner(button, -1)
	Kit.stroke(button, Color.textDark, 2)
	local knob = Kit.frame({
		parent = button,
		size = UDim2.fromOffset(24, 24),
		anchor = Vector2.new(0, 0.5),
		color = Color.paper,
		radius = -1,
		name = "Knob",
	})
	Kit.stroke(knob, Color.textDark, 2)
	local function paint(animate: boolean)
		local fill = if on then Color.leaf else Color.paperLine
		local knobPosition = if on then UDim2.new(1, -28, 0.5, 0) else UDim2.new(0, 4, 0.5, 0)
		if animate then
			Kit.tween(button, Theme.Tween.fast, { BackgroundColor3 = fill })
			Kit.tween(knob, Theme.Tween.pop, { Position = knobPosition })
		else
			button.BackgroundColor3 = fill
			knob.Position = knobPosition
		end
	end
	paint(false)
	button.Activated:Connect(function()
		on = not on
		paint(true)
		if props.onChanged then
			props.onChanged(on)
		end
	end)
	place(button, props)
	return {
		frame = button,
		set = function(value: boolean, silent: boolean?)
			on = value
			paint(not silent)
		end,
		get = function()
			return on
		end,
	}
end

export type Slider = { frame: Frame, set: (value: number) -> (), get: () -> number }

-- A horizontal slider between min and max. onChanged fires while dragging.
function Kit.slider(props: Props): Slider
	local min, max = props.min or 0, props.max or 1
	local value = math.clamp(props.value or min, min, max)
	local frame = Kit.frame({
		size = props.size or UDim2.new(1, 0, 0, 28),
		parent = props.parent,
		order = props.order,
		position = props.position,
		anchor = props.anchor,
		name = props.name,
	})
	local track = Kit.frame({
		parent = frame,
		size = UDim2.new(1, -20, 0, 8),
		position = UDim2.new(0, 10, 0.5, 0),
		anchor = Vector2.new(0, 0.5),
		color = Color.paperLine,
		radius = -1,
	})
	Kit.stroke(track, Color.textDark, 1.5, 0.2)
	local fill = Kit.frame({ parent = track, size = UDim2.fromScale(0, 1), color = Color.brass, radius = -1 })
	local knob = Kit.frame({
		parent = track,
		size = UDim2.fromOffset(22, 22),
		anchor = Vector2.new(0.5, 0.5),
		color = Color.paper,
		radius = -1,
		z = 3,
	})
	Kit.stroke(knob, Color.textDark, 2)
	local function paint()
		local t = (value - min) / (max - min)
		fill.Size = UDim2.fromScale(t, 1)
		knob.Position = UDim2.fromScale(t, 0.5)
	end
	paint()
	local dragging = false
	local function move(x: number)
		local t = math.clamp((x - track.AbsolutePosition.X) / math.max(track.AbsoluteSize.X, 1), 0, 1)
		local step = props.step
		value = min + t * (max - min)
		if step then
			value = math.round(value / step) * step
		end
		paint()
		if props.onChanged then
			props.onChanged(value)
		end
	end
	frame.Active = true
	frame.InputBegan:Connect(function(input)
		if
			input.UserInputType == Enum.UserInputType.MouseButton1
			or input.UserInputType == Enum.UserInputType.Touch
		then
			dragging = true
			move(input.Position.X)
		end
	end)
	UserInputService.InputChanged:Connect(function(input)
		if
			dragging
			and (
				input.UserInputType == Enum.UserInputType.MouseMovement
				or input.UserInputType == Enum.UserInputType.Touch
			)
		then
			move(input.Position.X)
		end
	end)
	UserInputService.InputEnded:Connect(function(input)
		if
			input.UserInputType == Enum.UserInputType.MouseButton1
			or input.UserInputType == Enum.UserInputType.Touch
		then
			dragging = false
		end
	end)
	return {
		frame = frame,
		set = function(v: number)
			value = math.clamp(v, min, max)
			paint()
		end,
		get = function()
			return value
		end,
	}
end

-- ---------------------------------------------------------------------------------------------
-- Lists and tabs
-- ---------------------------------------------------------------------------------------------

-- A scrolling area with a slim brass scrollbar. Children go in the returned frame's layout.
function Kit.scroll(props: Props): ScrollingFrame
	local scroll = Instance.new("ScrollingFrame")
	scroll.BackgroundTransparency = 1
	scroll.BorderSizePixel = 0
	scroll.ScrollBarThickness = props.scrollBarThickness or 6
	scroll.ScrollBarImageColor3 = props.scrollBarColor or Color.brass
	scroll.ScrollBarImageTransparency = 0.1
	scroll.CanvasSize = UDim2.new()
	scroll.AutomaticCanvasSize = if props.horizontal then Enum.AutomaticSize.X else Enum.AutomaticSize.Y
	scroll.ScrollingDirection = if props.horizontal
		then Enum.ScrollingDirection.X
		else Enum.ScrollingDirection.Y
	scroll.ElasticBehavior = Enum.ElasticBehavior.WhenScrollable
	scroll.VerticalScrollBarInset = Enum.ScrollBarInset.None
	scroll.ClipsDescendants = true
	place(scroll, props)
	return scroll
end

export type TabItem = { id: string, text: string, icon: string?, badge: boolean? }
export type Tabs = {
	frame: Frame,
	select: (id: string, silent: boolean?) -> (),
	setBadge: (id: string, on: boolean) -> (),
	-- Icon-only tabs, for narrow screens.
	setCompact: (on: boolean) -> (),
}

-- Notebook index tabs. Vertical tabs stack on the page's left edge; horizontal tabs sit on top.
function Kit.tabs(props: Props): Tabs
	local vertical = props.vertical ~= false
	local items: { TabItem } = props.items
	local frame = Kit.frame({
		size = props.size or UDim2.fromOffset(vertical and 120 or 400, vertical and 300 or 44),
		parent = props.parent,
		position = props.position,
		anchor = props.anchor,
		order = props.order,
		name = props.name or "Tabs",
	})
	Kit.list(
		frame,
		if vertical then Enum.FillDirection.Vertical else Enum.FillDirection.Horizontal,
		props.gap or 8
	)
	local buttons: {
		[string]: {
			button: TextButton,
			label: TextLabel,
			badge: Frame,
			scale: UIScale,
			mark: Frame,
			icon: ImageLabel?,
		},
	} =
		{}
	local current = ""
	-- "chunky" (the old brass tabs), "rail" (vertical icon rail) or "line" (underlined text tabs).
	local tabStyle: string = props.tabStyle or "chunky"

	local function paint(id: string, selected: boolean)
		local entry = buttons[id]
		if not entry then
			return
		end
		if tabStyle ~= "chunky" then
			-- Reference-style tabs: no boxes, a gold mark and tint on the active one.
			Kit.tween(
				entry.button,
				Theme.Tween.fast,
				{ BackgroundTransparency = if selected then 0.78 else 1 }
			)
			entry.button.BackgroundColor3 = Color.brassLight
			entry.label.TextColor3 = if selected then Color.brassLight else Color.textMuted
			if entry.icon then
				entry.icon.ImageColor3 = if selected then Color.brassLight else Color.textMuted
			end
			Kit.tween(entry.mark, Theme.Tween.fast, { BackgroundTransparency = if selected then 0 else 1 })
			return
		end
		local fill = if selected then Color.paper else Color.brassDark
		Kit.tween(entry.button, Theme.Tween.fast, { BackgroundColor3 = fill })
		entry.label.TextColor3 = if selected then Color.textDark else Color.brassLight
		Kit.tween(entry.scale, Theme.Tween.pop, { Scale = if selected then 1.0 else 0.96 })
	end

	local function choose(id: string, silent: boolean?)
		if id == current then
			return
		end
		local previous = current
		current = id
		if previous ~= "" then
			paint(previous, false)
		end
		paint(id, true)
		if not silent and props.onSelect then
			props.onSelect(id)
		end
	end

	for order, item in items do
		local button = Instance.new("TextButton")
		button.Name = item.id
		button.AutoButtonColor = false
		button.Text = ""
		button.BorderSizePixel = 0
		button.LayoutOrder = order
		button.BackgroundColor3 = Color.brassDark
		if tabStyle ~= "chunky" then
			button.BackgroundTransparency = 1
		end
		button.Size = if vertical
			then UDim2.new(1, 0, 0, props.tabSize or 52)
			else UDim2.new(0, props.tabSize or 120, 1, 0)
		Kit.corner(button, if tabStyle == "chunky" then 12 else 8)
		if tabStyle == "chunky" then
			Kit.stroke(button, Color.textDark, 2)
		end
		local scale = Instance.new("UIScale")
		scale.Scale = 0.96
		scale.Parent = button
		local content = Kit.frame({ parent = button, size = UDim2.fromScale(1, 1) })
		Kit.list(
			content,
			Enum.FillDirection.Horizontal,
			6,
			Enum.HorizontalAlignment.Center,
			Enum.VerticalAlignment.Center
		)
		if item.icon then
			Kit.icon({
				parent = content,
				name = item.icon,
				size = UDim2.fromOffset(26, 26),
				color = Color.brassLight,
				order = 1,
				glyphSize = 20,
			})
		end
		local label = Kit.text({
			parent = content,
			text = item.text,
			font = "heavy",
			textSize = Theme.TextSize.small,
			color = Color.brassLight,
			align = Enum.TextXAlignment.Center,
			size = UDim2.fromScale(0, 1),
			autoSize = Enum.AutomaticSize.X,
			order = 2,
		})
		local badge = Kit.frame({
			parent = button,
			size = UDim2.fromOffset(14, 14),
			position = UDim2.new(1, -6, 0, 6),
			anchor = Vector2.new(1, 0),
			color = Color.danger,
			radius = -1,
			visible = item.badge == true,
			name = "Badge",
		})
		Kit.stroke(badge, Color.paper, 1.5)
		local mark = Kit.frame({
			parent = button,
			size = if vertical then UDim2.new(0, 3, 0.7, 0) else UDim2.new(0.8, 0, 0, 3),
			position = if vertical then UDim2.fromScale(0, 0.5) else UDim2.fromScale(0.5, 1),
			anchor = if vertical then Vector2.new(0, 0.5) else Vector2.new(0.5, 1),
			color = Color.brassLight,
			radius = -1,
			name = "Mark",
		})
		mark.BackgroundTransparency = 1
		local iconImage = content:FindFirstChildWhichIsA("ImageLabel")
		button.Activated:Connect(function()
			choose(item.id)
		end)
		button.Parent = frame
		buttons[item.id] = {
			button = button,
			label = label,
			badge = badge,
			scale = scale,
			mark = mark,
			icon = iconImage,
		}
		if tabStyle ~= "chunky" then
			label.TextColor3 = Color.textMuted
			if iconImage then
				iconImage.ImageColor3 = Color.textMuted
			end
		end
	end

	return {
		frame = frame,
		select = choose,
		setBadge = function(id: string, on: boolean)
			local entry = buttons[id]
			if entry then
				entry.badge.Visible = on
			end
		end,
		setCompact = function(on: boolean)
			for _, entry in buttons do
				entry.label.Visible = not on
			end
		end,
	}
end

-- ---------------------------------------------------------------------------------------------
-- Small widgets
-- ---------------------------------------------------------------------------------------------

-- A row of rarity stars. `filled` of `total` are lit in the rarity colour.
function Kit.stars(props: Props): Frame
	local total = props.total or props.filled or 5
	local filled = props.filled or total
	local size = props.starSize or 16
	local frame = Kit.frame({
		size = UDim2.fromOffset(total * (size + 2), size),
		parent = props.parent,
		order = props.order,
		position = props.position,
		anchor = props.anchor,
		name = props.name or "Stars",
	})
	Kit.list(
		frame,
		Enum.FillDirection.Horizontal,
		2,
		props.align or Enum.HorizontalAlignment.Left,
		Enum.VerticalAlignment.Center
	)
	local color = props.color or Theme.rarity(filled)
	for index = 1, total do
		Kit.icon({
			parent = frame,
			name = if index <= filled then "star" else "starEmpty",
			size = UDim2.fromOffset(size, size),
			color = if index <= filled then color else Color.textMuted,
			order = index,
			glyphSize = size,
		})
	end
	return frame
end

-- A pill showing an icon and a value: currency counters, small stats.
function Kit.chip(props: Props): { frame: Frame, set: (value: string) -> () }
	local frame = Kit.panel({
		style = props.style or "soft",
		size = props.size or UDim2.fromOffset(120, 32),
		parent = props.parent,
		order = props.order,
		position = props.position,
		anchor = props.anchor,
		name = props.name,
		radius = -1,
	})
	local row = Kit.frame({ parent = frame, size = UDim2.fromScale(1, 1) })
	Kit.padding(row, 8, 0)
	Kit.list(
		row,
		Enum.FillDirection.Horizontal,
		6,
		Enum.HorizontalAlignment.Left,
		Enum.VerticalAlignment.Center
	)
	if props.icon then
		Kit.icon({
			parent = row,
			name = props.icon,
			size = UDim2.fromOffset(22, 22),
			color = props.iconColor,
			order = 1,
			glyphSize = 16,
		})
	end
	local label = Kit.text({
		parent = row,
		text = props.text or "",
		font = "heavy",
		textSize = props.textSize or Theme.TextSize.small,
		color = props.color or Color.textLight,
		size = UDim2.new(1, -30, 1, 0),
		order = 2,
		name = "Value",
		truncate = true,
	})
	return {
		frame = frame,
		set = function(value: string)
			label.Text = value
		end,
	}
end

-- ---------------------------------------------------------------------------------------------
-- Motion
-- ---------------------------------------------------------------------------------------------

-- Scales a GuiObject in from `from` (default 0.88) with an overshoot and fades it up.
function Kit.popIn(gui: GuiObject, from: number?, delay: number?)
	local scale = gui:FindFirstChildOfClass("UIScale")
	if not scale then
		scale = Instance.new("UIScale")
		scale.Parent = gui
	end
	local s = scale :: UIScale
	s.Scale = from or 0.88
	local run = function()
		Kit.tween(s, Theme.Tween.pop, { Scale = 1 })
	end
	if delay and delay > 0 then
		task.delay(delay, run)
	else
		run()
	end
end

-- Counts a number label up (or down) to `target` over `seconds`.
function Kit.countTo(
	label: TextLabel,
	from: number,
	target: number,
	seconds: number,
	format: ((number) -> string)?
)
	local started = os.clock()
	local fmt = format or function(n: number)
		return Theme.count(n)
	end
	task.spawn(function()
		while label.Parent do
			local t = math.clamp((os.clock() - started) / math.max(seconds, 0.01), 0, 1)
			local eased = 1 - (1 - t) ^ 3
			label.Text = fmt(from + (target - from) * eased)
			if t >= 1 then
				break
			end
			task.wait()
		end
		label.Text = fmt(target)
	end)
end

return Kit
