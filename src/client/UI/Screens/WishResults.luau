--!strict
--[[
	WishResults

	The moment a Starfall wish lands: a star streaks down in the colour of the best result, flashes
	where it hits, then the cards pop out one by one. The star's colour tells the rarity from the
	first frame (there are no fake-outs), and Skip jumps straight to the finished screen.

	With reduced motion on, the streak and the flash are replaced by a plain fade.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Content = require(ReplicatedStorage.Shared.Content)

local Fx = require(script.Parent.Parent.Fx)
local ItemCard = require(script.Parent.Parent.Components.ItemCard)
local Kit = require(script.Parent.Parent.Kit)
local Theme = require(script.Parent.Parent.Theme)

local Color = Theme.Color

export type Result = {
	itemId: string,
	rarity: number,
	featured: boolean?,
	kind: string?,
	isNew: boolean?,
	moonflakes: number?,
	awakening: number?,
	polish: number?,
	maxed: boolean?,
}

export type Options = {
	colorblind: string?,
	reducedMotion: boolean?,
	onDone: (() -> ())?,
	-- Shown above the cards.
	title: string?,
}

local WishResults = {}

local function badgeFor(result: Result): (string?, Color3?)
	if result.maxed then
		return Content.text("common.max"), Color.violet
	elseif result.isNew then
		return Content.text("common.new"), Color.coral
	elseif result.rarity >= 4 then
		if result.kind == "weapon" then
			return `P{result.polish or 1}`, Color.brassDark
		end
		return `A{result.awakening or 1}`, Color.brassDark
	end
	return nil, nil
end

-- A small spray of stars flying out from a point.
local function burst(parent: GuiObject, centre: UDim2, color: Color3, count: number)
	local rng = Random.new()
	for _ = 1, count do
		local diameter = rng:NextInteger(18, 44)
		local star = Fx.image(if rng:NextNumber() < 0.5 then "sparkle4" else "sparkle8", {
			parent = parent,
			size = UDim2.fromOffset(diameter, diameter),
			position = centre,
			color = color:Lerp(Color3.new(1, 1, 1), 0.35),
			z = 40,
		})
		local angle = rng:NextNumber(0, math.pi * 2)
		local distance = rng:NextNumber(70, 200)
		local seconds = rng:NextNumber(0.6, 1.1)
		Kit.tween(star, TweenInfo.new(seconds, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
			Position = UDim2.new(
				centre.X.Scale,
				centre.X.Offset + math.cos(angle) * distance,
				centre.Y.Scale,
				centre.Y.Offset + math.sin(angle) * distance
			),
			ImageTransparency = 1,
			Rotation = rng:NextNumber(-180, 180),
			Size = UDim2.fromOffset(diameter * 0.4, diameter * 0.4),
		})
		task.delay(seconds + 0.05, function()
			star:Destroy()
		end)
	end
end

function WishResults.show(layer: Instance, results: { Result }, options: Options)
	local reduced = options.reducedMotion == true
	local best = 3
	local moonflakes = 0
	for _, result in results do
		best = math.max(best, result.rarity)
		moonflakes += result.moonflakes or 0
	end
	local starColor = Theme.rarityFor(best, options.colorblind)

	local alive = true
	local skipped = false

	local dim = Kit.frame({
		parent = layer,
		size = UDim2.fromScale(1, 1),
		color = Color.night,
		name = "WishResults",
		z = 60,
	})
	dim.Active = true
	Kit.gradient(dim, Color3.fromRGB(46, 58, 112), Color3.fromRGB(8, 10, 24), 90)
	dim.BackgroundTransparency = 1
	Kit.tween(dim, Theme.Tween.normal, { BackgroundTransparency = 0 })

	-- Backdrop stars.
	local rng = Random.new(11)
	for index = 1, 40 do
		local size = rng:NextInteger(2, 4)
		Kit.frame({
			parent = dim,
			size = UDim2.fromOffset(size, size),
			position = UDim2.fromScale(rng:NextNumber(), rng:NextNumber()),
			color = Color.textLight,
			transparency = rng:NextNumber(0.3, 0.8),
			radius = -1,
			name = `Dust{index}`,
		})
	end

	local stage = Kit.frame({ parent = dim, size = UDim2.fromScale(1, 1), name = "Stage", z = 2 })
	local title = Kit.text({
		parent = stage,
		text = options.title or "",
		font = "title",
		textSize = Theme.TextSize.heading,
		color = Color.textLight,
		align = Enum.TextXAlignment.Center,
		size = UDim2.new(1, 0, 0, 40),
		position = UDim2.fromOffset(0, 18),
		stroke = true,
		strokeTransparency = 0.5,
		z = 5,
	})
	title.TextTransparency = 1

	local cards: { GuiObject } = {}
	local cardAnchors: { UDim2 } = {}
	local footer = Kit.frame({
		parent = stage,
		size = UDim2.new(1, 0, 0, 60),
		position = UDim2.new(0, 0, 1, -76),
		name = "Footer",
		z = 6,
	})
	footer.Visible = false
	Kit.list(
		footer,
		Enum.FillDirection.Horizontal,
		18,
		Enum.HorizontalAlignment.Center,
		Enum.VerticalAlignment.Center
	)

	local function finish()
		if not alive then
			return
		end
		alive = false
		Kit.tween(dim, Theme.Tween.fast, { BackgroundTransparency = 1 })
		task.delay(0.15, function()
			dim:Destroy()
		end)
		if options.onDone then
			options.onDone()
		end
	end

	-- Footer: what the wishes paid back, and the way out.
	if moonflakes > 0 then
		local chip = Kit.chip({
			parent = footer,
			style = "ink",
			size = UDim2.fromOffset(150, 40),
			icon = "moonflakes",
			iconColor = Theme.Color.textMuted,
			text = `+{Theme.count(moonflakes)}`,
			color = Color.textLight,
			textSize = Theme.TextSize.body,
			order = 1,
		})
		chip.frame.Name = "Moonflakes"
	end
	local doneButton = Kit.button({
		parent = footer,
		text = Content.text("starfall.continue"),
		style = "primary",
		size = UDim2.fromOffset(190, 46),
		order = 2,
		onClick = finish,
	})
	doneButton.Name = "Continue"

	-- Layout of the cards: one big card, or a 5 x 2 grid.
	local count = #results
	local cardSize = if count == 1 then Vector2.new(210, 300) else Vector2.new(128, 182)
	local columns = if count == 1 then 1 else 5
	local gap = 14
	local rows = math.ceil(count / columns)
	local gridWidth = columns * cardSize.X + (columns - 1) * gap
	local gridHeight = rows * cardSize.Y + (rows - 1) * gap

	local function showCard(index: number)
		local result = results[index]
		local column = (index - 1) % columns
		local row = math.floor((index - 1) / columns)
		local position = UDim2.new(
			0.5,
			-gridWidth / 2 + column * (cardSize.X + gap) + cardSize.X / 2,
			0.5,
			-gridHeight / 2 + row * (cardSize.Y + gap) + cardSize.Y / 2 - 6
		)
		local badge, badgeColor = badgeFor(result)
		local card = ItemCard.new({
			parent = stage,
			itemId = result.itemId,
			size = UDim2.fromOffset(cardSize.X, cardSize.Y),
			position = position,
			anchor = Vector2.new(0.5, 0.5),
			badge = badge,
			badgeColor = badgeColor,
			colorblind = options.colorblind,
		})
		card.ZIndex = 8
		cards[index] = card
		cardAnchors[index] = position
		if not skipped and not reduced then
			card.Position = position + UDim2.fromOffset(0, 26)
			Kit.tween(card, Theme.Tween.pop, { Position = position })
			Kit.popIn(card, 0.5)
		end
		if result.rarity >= 4 and not skipped and not reduced then
			burst(
				stage,
				position,
				Theme.rarityFor(result.rarity, options.colorblind),
				if result.rarity >= 5 then 14 else 7
			)
		end
	end

	local skipButton: TextButton? = nil

	local function revealAll()
		skipped = true
		for index = 1, count do
			if not cards[index] then
				showCard(index)
			end
		end
		title.TextTransparency = 0
		footer.Visible = true
		if skipButton then
			skipButton.Visible = false
		end
	end

	local skip = Kit.button({
		name = "Skip",
		parent = stage,
		text = Content.text("starfall.skip"),
		style = "dark",
		size = UDim2.fromOffset(110, 38),
		position = UDim2.new(1, -20, 0, 16),
		anchor = Vector2.new(1, 0),
		z = 20,
		onClick = function()
			if footer.Visible then
				return
			end
			revealAll()
		end,
	})
	skipButton = skip

	-- The show.
	task.spawn(function()
		local centre = UDim2.fromScale(0.5, 0.5)
		if not reduced then
			-- A star falls out of the top left and strikes the centre.
			local size = 560
			local headOffset = size * 0.242
			local falling = Fx.image("fallingStar", {
				parent = stage,
				size = UDim2.fromOffset(size, size),
				position = UDim2.new(0.5, -headOffset - 760, 0.5, -headOffset - 760),
				color = starColor:Lerp(Color3.new(1, 1, 1), 0.3),
				z = 10,
			})
			local fall = TweenInfo.new(0.8, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
			Kit.tween(falling, fall, { Position = UDim2.new(0.5, -headOffset, 0.5, -headOffset) })
			local waited = 0
			while waited < 0.8 and alive and not skipped do
				waited += task.wait()
			end
			falling:Destroy()
			if not alive then
				return
			end
			if not skipped then
				-- Impact: a flash of light, a ring and a flare.
				local flash = Kit.frame({
					parent = dim,
					size = UDim2.fromScale(1, 1),
					color = Color3.new(1, 1, 1),
					transparency = 0.35,
					name = "Flash",
					z = 30,
				})
				Kit.tween(
					flash,
					TweenInfo.new(0.45, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
					{ BackgroundTransparency = 1 }
				)
				task.delay(0.5, function()
					flash:Destroy()
				end)
				local glow = Fx.image("glow", {
					parent = stage,
					size = UDim2.fromOffset(120, 120),
					position = centre,
					color = starColor,
					z = 9,
				})
				Kit.tween(
					glow,
					TweenInfo.new(0.9, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
					{ Size = UDim2.fromOffset(1500, 1500), ImageTransparency = 1 }
				)
				local ring = Fx.image("ringDouble", {
					parent = stage,
					size = UDim2.fromOffset(80, 80),
					position = centre,
					color = starColor:Lerp(Color3.new(1, 1, 1), 0.4),
					z = 11,
				})
				Kit.tween(
					ring,
					TweenInfo.new(0.9, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
					{ Size = UDim2.fromOffset(1400, 1400), ImageTransparency = 1 }
				)
				local flare = Fx.image("flare", {
					parent = stage,
					size = UDim2.fromOffset(160, 160),
					position = centre,
					color = Color3.new(1, 1, 1),
					z = 12,
				})
				Kit.tween(
					flare,
					TweenInfo.new(0.7, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
					{ Size = UDim2.fromOffset(900, 900), ImageTransparency = 1, Rotation = 25 }
				)
				task.delay(1, function()
					glow:Destroy()
					ring:Destroy()
					flare:Destroy()
				end)
				burst(stage, centre, starColor, 12)
				task.wait(0.35)
			end
		else
			task.wait(0.2)
		end
		if not alive then
			return
		end
		Kit.tween(title, Theme.Tween.normal, { TextTransparency = 0 })
		for index = 1, count do
			if not alive or skipped then
				break
			end
			if not cards[index] then
				showCard(index)
			end
			task.wait(if count == 1 then 0.1 else 0.13)
		end
		if alive then
			revealAll()
		end
	end)

	return {
		close = finish,
		root = dim,
	}
end

return WishResults
