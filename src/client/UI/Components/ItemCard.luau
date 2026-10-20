--!strict
--[[
	ItemCard

	A character or weapon as a collectable card: a rarity-coloured frame, a dark portrait window
	with the item's emblem, a row of stars and a paper name strip. Used by Starfall (banners,
	results, Star Pick), the Bag and the Party screen, so every item looks the same everywhere.

	Characters show a medallion in their element's colour until portraits exist; weapons show their
	type's icon. The star count and the frame colour both carry the rarity, so colour is never the
	only cue (the colour-blind setting swaps the palette on top of that).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Content = require(ReplicatedStorage.Shared.Content)
local Heroes = require(ReplicatedStorage.Shared.Config.Heroes)
local Items = require(ReplicatedStorage.Shared.Config.Items)

local Kit = require(script.Parent.Parent.Kit)
local Theme = require(script.Parent.Parent.Theme)

local Color = Theme.Color

export type Options = {
	parent: Instance?,
	itemId: string,
	size: UDim2?,
	order: number?,
	position: UDim2?,
	anchor: Vector2?,
	-- Short label in the top corner ("NEW", "TARGET", "x2").
	badge: string?,
	badgeColor: Color3?,
	selected: boolean?,
	dim: boolean?,
	colorblind: string?,
	onClick: (() -> ())?,
}

local ItemCard = {}

local ELEMENT_ORDER = { "Flame", "Tide", "Terra", "Gale", "Frost", "Volt", "Astral" }

-- Characters without a kit yet borrow a stable element so the cards look varied.
local function elementOf(itemId: string): string
	local kit = Heroes[itemId]
	if kit then
		return kit.element
	end
	local sum = 0
	for index = 1, #itemId do
		sum += string.byte(itemId, index) * index
	end
	return ELEMENT_ORDER[sum % #ELEMENT_ORDER + 1]
end

local function shade(color: Color3, amount: number): Color3
	return if amount >= 0
		then color:Lerp(Color3.new(1, 1, 1), amount)
		else color:Lerp(Color3.new(0, 0, 0), -amount)
end

function ItemCard.new(options: Options): TextButton
	local item = Items.get(options.itemId)
	local rarity = if item then item.rarity else 3
	local isCharacter = item ~= nil and item.kind == "character"
	local accent = Theme.rarityFor(rarity, options.colorblind)
	local size = options.size or UDim2.fromOffset(132, 188)

	local button = Instance.new("TextButton")
	button.Name = "Card_" .. options.itemId
	button.AutoButtonColor = false
	button.BackgroundTransparency = 1
	button.Text = ""
	button.Size = size
	button.LayoutOrder = options.order or 0
	if options.position then
		button.Position = options.position
	end
	if options.anchor then
		button.AnchorPoint = options.anchor
	end
	local scale = Instance.new("UIScale")
	scale.Parent = button

	if rarity >= 5 then
		-- A soft halo behind five-star cards.
		local glow = Kit.frame({
			parent = button,
			size = UDim2.new(1, 14, 1, 14),
			position = UDim2.fromScale(0.5, 0.5),
			anchor = Vector2.new(0.5, 0.5),
			color = accent,
			transparency = 0.7,
			radius = 20,
			name = "Glow",
			z = 0,
		})
		Kit.gradient(glow, Color3.fromRGB(255, 255, 255), shade(accent, -0.2), 90)
	end

	local body = Kit.frame({
		parent = button,
		size = UDim2.fromScale(1, 1),
		color = accent,
		radius = 14,
		name = "Body",
		z = 1,
	})
	Kit.gradient(body, shade(accent, 0.35), shade(accent, -0.25), 90)
	local stroke = Kit.stroke(
		body,
		if options.selected then Color.textLight else shade(accent, -0.45),
		if options.selected then 4 else 3
	)

	-- Portrait window.
	local portrait = Kit.frame({
		parent = body,
		size = UDim2.new(1, -10, 0.74, -2),
		position = UDim2.fromOffset(5, 5),
		color = Color.night,
		radius = 10,
		clip = true,
		name = "Portrait",
		z = 2,
	})
	Kit.gradient(portrait, Color3.fromRGB(46, 58, 104), Color3.fromRGB(12, 16, 34), 90)

	local element = elementOf(options.itemId)
	local elementColor = Theme.element(element)

	-- A pale beam of light behind the emblem.
	local aura = Kit.frame({
		parent = portrait,
		size = UDim2.fromScale(0.9, 0.9),
		position = UDim2.fromScale(0.5, 0.46),
		anchor = Vector2.new(0.5, 0.5),
		color = if isCharacter then elementColor else accent,
		transparency = 0.72,
		radius = -1,
		name = "Aura",
		z = 2,
	})
	Kit.gradient(aura, Color3.fromRGB(255, 255, 255), Color3.fromRGB(80, 80, 80), 90)

	if isCharacter then
		local medallion = Kit.frame({
			parent = portrait,
			size = UDim2.fromScale(0.62, 0.62),
			position = UDim2.fromScale(0.5, 0.44),
			anchor = Vector2.new(0.5, 0.5),
			color = elementColor,
			radius = -1,
			name = "Medallion",
			z = 3,
		})
		medallion.SizeConstraint = Enum.SizeConstraint.RelativeXX
		Kit.gradient(medallion, shade(elementColor, 0.4), shade(elementColor, -0.3), 90)
		Kit.stroke(medallion, Color.paper, 3)
		local name = Content.itemName(options.itemId)
		Kit.text({
			parent = medallion,
			text = string.upper(string.sub(name, 1, 1)),
			font = "title",
			textSize = 44,
			color = Color.textLight,
			align = Enum.TextXAlignment.Center,
			size = UDim2.fromScale(1, 1),
			stroke = true,
			strokeTransparency = 0.35,
			z = 4,
		})
		-- Weapon type, bottom right.
		if item and item.weapon then
			local chip = Kit.frame({
				parent = portrait,
				size = UDim2.fromOffset(26, 26),
				position = UDim2.new(1, -6, 0, 6),
				anchor = Vector2.new(1, 0),
				color = Color.night,
				transparency = 0.2,
				radius = -1,
				name = "WeaponChip",
				z = 4,
			})
			Kit.stroke(chip, Color.inkLine, 1.5)
			Kit.icon({
				parent = chip,
				name = item.weapon,
				size = UDim2.fromScale(0.78, 0.78),
				position = UDim2.fromScale(0.5, 0.5),
				anchor = Vector2.new(0.5, 0.5),
				color = Color.textLight,
				glyphSize = 14,
				z = 5,
			})
		end
	else
		local weaponType = if item and item.weapon then item.weapon else "sword"
		Kit.icon({
			parent = portrait,
			name = weaponType,
			size = UDim2.fromScale(0.66, 0.66),
			position = UDim2.fromScale(0.5, 0.44),
			anchor = Vector2.new(0.5, 0.5),
			color = shade(accent, 0.25),
			glyphSize = 52,
			z = 3,
		})
	end

	-- Element dot, top left.
	local dot = Kit.frame({
		parent = portrait,
		size = UDim2.fromOffset(16, 16),
		position = UDim2.fromOffset(8, 8),
		color = elementColor,
		radius = -1,
		name = "Element",
		z = 4,
	})
	Kit.stroke(dot, Color.paper, 1.5)

	-- Stars along the foot of the portrait.
	local stars = Kit.stars({
		parent = portrait,
		filled = rarity,
		total = rarity,
		starSize = 15,
		color = accent,
		position = UDim2.new(0.5, 0, 1, -6),
		anchor = Vector2.new(0.5, 1),
		align = Enum.HorizontalAlignment.Center,
	})
	stars.ZIndex = 4

	-- Name strip.
	local strip = Kit.frame({
		parent = body,
		size = UDim2.new(1, -10, 0.26, -7),
		position = UDim2.new(0, 5, 0.74, 3),
		color = Color.paper,
		radius = 8,
		name = "Name",
		z = 2,
	})
	Kit.gradient(strip, Color3.fromRGB(70, 88, 140), Color3.fromRGB(34, 44, 82), 90)
	local widthPixels = size.X.Offset
	Kit.text({
		parent = strip,
		text = Content.itemName(options.itemId),
		font = "title",
		textSize = if widthPixels > 0 then math.clamp(math.floor(widthPixels * 0.115), 10, 18) else 15,
		color = Color.textDark,
		align = Enum.TextXAlignment.Center,
		size = UDim2.new(1, -8, 1, 0),
		position = UDim2.fromOffset(4, 0),
		truncate = true,
		z = 3,
	})

	if options.badge then
		local badge = Kit.frame({
			parent = body,
			size = UDim2.fromOffset(0, 20),
			position = UDim2.new(1, -4, 0, -8),
			anchor = Vector2.new(1, 0),
			color = options.badgeColor or Color.coral,
			radius = 10,
			name = "Badge",
			z = 6,
		})
		badge.AutomaticSize = Enum.AutomaticSize.X
		Kit.stroke(badge, Color.textLight, 1.5)
		Kit.padding(badge, 8, 0)
		Kit.text({
			parent = badge,
			text = options.badge,
			font = "heavy",
			textSize = 12,
			color = Color.textLight,
			size = UDim2.fromScale(0, 1),
			autoSize = Enum.AutomaticSize.X,
			stroke = true,
			strokeTransparency = 0.5,
			z = 7,
		})
	end

	if options.dim then
		local veil = Kit.frame({
			parent = body,
			size = UDim2.fromScale(1, 1),
			color = Color.black,
			transparency = 0.45,
			radius = 14,
			name = "Veil",
			z = 8,
		})
		veil.Active = false
	end

	button.MouseEnter:Connect(function()
		Kit.tween(scale, Theme.Tween.fast, { Scale = 1.04 })
	end)
	button.MouseLeave:Connect(function()
		Kit.tween(scale, Theme.Tween.fast, { Scale = 1 })
	end)
	button.InputBegan:Connect(function(input)
		if
			input.UserInputType == Enum.UserInputType.MouseButton1
			or input.UserInputType == Enum.UserInputType.Touch
		then
			Kit.tween(scale, Theme.Tween.fast, { Scale = 0.96 })
		end
	end)
	button.InputEnded:Connect(function(input)
		if
			input.UserInputType == Enum.UserInputType.MouseButton1
			or input.UserInputType == Enum.UserInputType.Touch
		then
			Kit.tween(scale, Theme.Tween.pop, { Scale = 1.04 })
		end
	end)
	button.Activated:Connect(function()
		if options.onClick then
			options.onClick()
		end
	end)
	stroke.Parent = body
	if options.parent then
		button.Parent = options.parent
	end
	return button
end

return ItemCard
