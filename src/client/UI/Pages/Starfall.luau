--!strict
--[[
	Starfall page

	The wish screen. Banner tabs across the top, the banner's showcase on the left and the
	player's own odds on the right: the 5-star chance on the next wish, pity, the 50/50 guarantee
	and Star Pick, kept honest by the same shared module the server rolls with. Details lists every
	result's chance, History shows six months of wishes, Exchange turns earned currency into tokens.

	Everything the player is told here comes from the profile snapshot and Shared.Gacha; the server
	decides every result (see GachaService). The layout scales with the space it is given, so it
	holds up from a phone's wide screen to a tablet's narrow one.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Banners = require(ReplicatedStorage.Shared.Config.Banners)
local Content = require(ReplicatedStorage.Shared.Content)
local Economy = require(ReplicatedStorage.Shared.Config.Economy)
local Gacha = require(ReplicatedStorage.Shared.Gacha)
local Items = require(ReplicatedStorage.Shared.Config.Items)

local ItemCard = require(script.Parent.Parent.Components.ItemCard)
local Kit = require(script.Parent.Parent.Kit)
local Sunburst = require(script.Parent.Parent.Components.Sunburst)
local Theme = require(script.Parent.Parent.Theme)
local WishResults = require(script.Parent.Parent.Screens.WishResults)

local Color = Theme.Color

local Starfall = {}

Starfall.id = "starfall"
Starfall.icon = "starfall"

local function percent(value: number, decimals: number?): string
	return string.format(`%.{decimals or 1}f%%`, value * 100)
end

local function currencyName(id: string): string
	local currency = Economy.Currencies[id]
	return if currency then Content.text(currency.textKey) else id
end

local function errorText(code: string?): string
	local key = `starfall.error.{code or "network"}`
	local text = Content.text(key)
	if text ~= key then
		return text
	end
	if code == "not_enough_currency" then
		return Content.text("starfall.notEnough")
	elseif code == "restricted" then
		return Content.text("starfall.restricted")
	elseif code == "locked" then
		return Content.text("starfall.locked")
	end
	return Content.text("starfall.error.network")
end

-- Pity for a banner out of the profile snapshot (a copy, so reading never changes the snapshot).
local function pityOf(snapshot: any, banner: Gacha.Banner): Gacha.PityState
	local saved = snapshot and snapshot.pity and snapshot.pity[Banners.pityKey(banner)]
	return Gacha.normalizeState(if saved then table.clone(saved) else nil)
end

-- The weapon an Armoury player is aiming at (their choice, else the first featured one).
local function targetOf(snapshot: any, banner: Gacha.Banner): string?
	if not banner.targetPick then
		return nil
	end
	local chosen = snapshot and snapshot.flags and snapshot.flags.armouryTarget
	if type(chosen) == "string" and table.find(banner.featured5, chosen) then
		return chosen
	end
	return banner.featured5[1]
end

-- The banner as this player rolls it (an Armoury banner is aimed at their target).
local function liveBanner(snapshot: any, banner: Gacha.Banner): Gacha.Banner
	local target = targetOf(snapshot, banner)
	return if target then (Gacha.withTarget(banner, target) or banner) else banner
end

local BURST_COLORS: { [string]: Color3 } = {
	featured = Color.star,
	armoury = Color.coral,
	everlit = Color.sea,
	firstLight = Color.leaf,
}

function Starfall.build(parent: Frame, ctx: any)
	local root = Kit.frame({ parent = parent, size = UDim2.fromScale(1, 1), name = "Starfall" })
	local api = ctx.starfall
	local snapshot: any = ctx.profile.get()
	local selectedId: string = Banners.Active[1]
	local busy = false
	local refresh: () -> ()

	local function modalLayer(): Instance
		return if ctx.ui.layer then ctx.ui.layer("modals") else root
	end
	local function toast(text: string, icon: string?)
		if ctx.ui.toast then
			ctx.ui.toast({ text = text, icon = icon or "info" })
		end
	end
	local function setting(key: string): any
		local settings = snapshot and snapshot.settings
		return settings and settings[key]
	end
	local function currentBanner(): Gacha.Banner
		return Banners.byId[selectedId]
	end

	-- Header ---------------------------------------------------------------------------------------------
	Kit.text({
		parent = root,
		text = Content.text("starfall.title"),
		font = "title",
		textSize = Theme.TextSize.title,
		color = Color.textDark,
		size = UDim2.fromOffset(260, 44),
	})
	local headerButtons = Kit.frame({
		parent = root,
		size = UDim2.fromOffset(220, 36),
		position = UDim2.new(1, 0, 0, 4),
		anchor = Vector2.new(1, 0),
		name = "HeaderButtons",
	})
	Kit.list(
		headerButtons,
		Enum.FillDirection.Horizontal,
		8,
		Enum.HorizontalAlignment.Right,
		Enum.VerticalAlignment.Center
	)
	local detailsButton = Kit.button({
		parent = headerButtons,
		text = Content.text("starfall.details"),
		icon = "info",
		style = "dark",
		size = UDim2.fromOffset(104, 34),
		textSize = Theme.TextSize.small,
		iconSize = 20,
		order = 1,
	})
	local historyButton = Kit.button({
		parent = headerButtons,
		text = Content.text("starfall.history"),
		icon = "notebook",
		style = "dark",
		size = UDim2.fromOffset(104, 34),
		textSize = Theme.TextSize.small,
		iconSize = 20,
		order = 2,
	})

	-- Banner tabs ----------------------------------------------------------------------------------------------
	local tabs = Kit.frame({
		parent = root,
		size = UDim2.new(1, 0, 0, 46),
		position = UDim2.fromOffset(0, 46),
		name = "Banners",
	})
	Kit.list(
		tabs,
		Enum.FillDirection.Horizontal,
		8,
		Enum.HorizontalAlignment.Left,
		Enum.VerticalAlignment.Top
	)
	local bannerCards: {
		[string]: {
			card: Frame,
			stroke: UIStroke,
			title: TextLabel,
			note: TextLabel,
			count: TextLabel,
			slot: Frame,
		},
	} =
		{}

	-- Body: showcase and the player's panel ------------------------------------------------------------------------
	local body = Kit.frame({
		parent = root,
		size = UDim2.new(1, 0, 1, -100),
		position = UDim2.fromOffset(0, 100),
		name = "Body",
	})
	local panelWidth = 250

	local showcase = Kit.panel({
		style = "ink",
		parent = body,
		size = UDim2.new(1, -(panelWidth + 12), 1, 0),
		radius = 16,
		clip = true,
		name = "Showcase",
	})
	Kit.gradient(showcase, Color3.fromRGB(70, 86, 150), Color3.fromRGB(16, 22, 48), 90)
	local dust = Random.new(5)
	for index = 1, 26 do
		local size = dust:NextInteger(2, 4)
		Kit.frame({
			parent = showcase,
			size = UDim2.fromOffset(size, size),
			position = UDim2.fromScale(dust:NextNumber(), dust:NextNumber()),
			color = Color.textLight,
			transparency = dust:NextNumber(0.35, 0.85),
			radius = -1,
			name = `Dust{index}`,
		})
	end
	local showcaseContent = Kit.frame({ parent = showcase, size = UDim2.fromScale(1, 1), name = "Content" })

	local panel = Kit.panel({
		style = "paper",
		parent = body,
		size = UDim2.new(0, panelWidth, 1, 0),
		position = UDim2.fromScale(1, 0),
		anchor = Vector2.new(1, 0),
		radius = 16,
		name = "WishPanel",
	})
	Kit.padding(panel, 12, 10)
	local rows = Kit.frame({ parent = panel, size = UDim2.fromScale(1, 1) })
	Kit.list(rows, Enum.FillDirection.Vertical, 6)

	-- Row A: the chance on the next wish.
	local chanceRow = Kit.frame({ parent = rows, size = UDim2.new(1, 0, 0, 46), order = 1, name = "Chance" })
	local chanceLabel = Kit.text({
		parent = chanceRow,
		text = "0.8%",
		font = "title",
		textSize = 36,
		color = Color.textDark,
		size = UDim2.new(0, 104, 1, 0),
	})
	Kit.text({
		parent = chanceRow,
		text = Content.text("starfall.next5"),
		font = "body",
		textSize = Theme.TextSize.tiny,
		color = Color.textFaint,
		size = UDim2.new(1, -108, 1, 0),
		position = UDim2.fromOffset(108, 0),
		wrap = true,
	})

	-- Row B: pity.
	local pityRow = Kit.frame({ parent = rows, size = UDim2.new(1, 0, 0, 50), order = 2, name = "Pity" })
	local pityBar = Kit.bar({
		parent = pityRow,
		size = UDim2.new(1, 0, 0, 12),
		position = UDim2.fromOffset(0, 2),
		color = Color.brass,
		trackColor = Color.paperLine,
		trackTransparency = 0.1,
		outline = Color.textDark,
	})
	local softMarker = Kit.frame({
		parent = pityRow,
		size = UDim2.fromOffset(3, 18),
		position = UDim2.fromOffset(0, -1),
		color = Color.coral,
		radius = 2,
		name = "SoftPity",
		z = 3,
	})
	local pityCaption = Kit.text({
		parent = pityRow,
		text = "",
		font = "body",
		textSize = Theme.TextSize.tiny,
		color = Color.textFaint,
		size = UDim2.new(1, 0, 0, 32),
		position = UDim2.fromOffset(0, 18),
		wrap = true,
		valign = Enum.TextYAlignment.Top,
	})

	-- Row C: the 50/50 or target guarantee.
	local guaranteeRow =
		Kit.frame({ parent = rows, size = UDim2.new(1, 0, 0, 34), order = 3, name = "Guarantee" })
	Kit.icon({
		parent = guaranteeRow,
		name = "star",
		size = UDim2.fromOffset(20, 20),
		position = UDim2.fromOffset(0, 7),
		color = Color.brass,
		glyphSize = 16,
	})
	local guaranteeText = Kit.text({
		parent = guaranteeRow,
		text = "",
		font = "bold",
		textSize = 13,
		color = Color.textDark,
		size = UDim2.new(1, -26, 1, 0),
		position = UDim2.fromOffset(26, 0),
		wrap = true,
	})

	-- Row D: Star Pick.
	local pickRow = Kit.frame({ parent = rows, size = UDim2.new(1, 0, 0, 40), order = 4, name = "StarPick" })
	local pickText = Kit.text({
		parent = pickRow,
		text = "",
		font = "bold",
		textSize = 13,
		color = Color.textDark,
		size = UDim2.new(1, 0, 0, 20),
		wrap = true,
	})
	local pickBar = Kit.bar({
		parent = pickRow,
		size = UDim2.new(1, 0, 0, 8),
		position = UDim2.fromOffset(0, 26),
		color = Color.sea,
		trackColor = Color.paperLine,
		trackTransparency = 0.1,
		outline = Color.textDark,
	})
	local pickButton = Kit.button({
		parent = pickRow,
		text = Content.text("starfall.starPickTitle"),
		icon = "star",
		style = "success",
		size = UDim2.new(1, 0, 0, 36),
		visible = false,
		name = "PickButton",
		textSize = Theme.TextSize.small,
	})

	-- Row E: the two wish buttons side by side, each with its price underneath.
	local buttons = Kit.frame({ parent = rows, size = UDim2.new(1, 0, 0, 66), order = 5, name = "Buttons" })
	Kit.list(buttons, Enum.FillDirection.Horizontal, 8)
	local function wishButton(
		text: string,
		style: string,
		order: number,
		name: string
	): (TextButton, (string, number, boolean) -> ())
		local button = Kit.button({
			parent = buttons,
			text = "",
			style = style,
			size = UDim2.new(0.5, -4, 1, 0),
			order = order,
			name = name,
		})
		Kit.text({
			parent = button,
			text = text,
			font = "heavy",
			textSize = Theme.TextSize.body,
			color = if style == "primary" then Color3.fromRGB(46, 32, 14) else Color.textDark,
			align = Enum.TextXAlignment.Center,
			size = UDim2.new(1, 0, 0, 28),
			position = UDim2.fromOffset(0, 6),
			z = 4,
		})
		local tag = Kit.frame({
			parent = button,
			size = UDim2.fromOffset(72, 24),
			position = UDim2.new(0.5, 0, 1, -7),
			anchor = Vector2.new(0.5, 1),
			color = Color.night,
			transparency = 0.15,
			radius = -1,
			name = "Price",
			z = 6,
		})
		local slot = Kit.frame({
			parent = tag,
			size = UDim2.fromOffset(20, 20),
			position = UDim2.fromOffset(6, 2),
			z = 7,
		})
		local label = Kit.text({
			parent = tag,
			text = "",
			font = "heavy",
			textSize = Theme.TextSize.small,
			color = Color.textLight,
			size = UDim2.new(1, -32, 1, 0),
			position = UDim2.fromOffset(28, 0),
			align = Enum.TextXAlignment.Center,
			z = 7,
		})
		return button,
			function(currency: string, cost: number, affordable: boolean)
				for _, child in slot:GetChildren() do
					child:Destroy()
				end
				Kit.icon({
					parent = slot,
					name = currency,
					size = UDim2.fromScale(1, 1),
					glyphSize = 16,
					z = 8,
				})
				label.Text = tostring(cost)
				label.TextColor3 = if affordable then Color.textLight else Color.coral
			end
	end
	local wish1, setPrice1 = wishButton(Content.text("starfall.pull1"), "paper", 1, "Wish1")
	local wish10, setPrice10 = wishButton(Content.text("starfall.pull10"), "primary", 2, "Wish10")

	-- Row F: balance and exchange.
	local owned = Kit.frame({ parent = rows, size = UDim2.new(1, 0, 0, 32), order = 6, name = "Owned" })
	local ownedSlot =
		Kit.frame({ parent = owned, size = UDim2.fromOffset(26, 26), position = UDim2.fromOffset(0, 3) })
	local ownedText = Kit.text({
		parent = owned,
		text = "0",
		font = "heavy",
		textSize = Theme.TextSize.body,
		color = Color.textDark,
		size = UDim2.new(0, 70, 1, 0),
		position = UDim2.fromOffset(32, 0),
	})
	local exchangeButton = Kit.button({
		parent = owned,
		text = Content.text("starfall.exchange"),
		style = "paper",
		size = UDim2.fromOffset(104, 30),
		position = UDim2.new(1, 0, 0, 1),
		anchor = Vector2.new(1, 0),
		textSize = Theme.TextSize.small,
	})

	-- Modals ----------------------------------------------------------------------------------------------------

	local function openModal(title: string, size: Vector2): (Frame, () -> ())
		local dim = Kit.frame({
			parent = modalLayer(),
			size = UDim2.fromScale(1, 1),
			color = Color.black,
			transparency = 0.5,
			name = "StarfallModal",
			z = 70,
		})
		dim.Active = true
		local card = Kit.panel({
			style = "paper",
			parent = dim,
			size = UDim2.fromOffset(size.X, size.Y),
			position = UDim2.fromScale(0.5, 0.5),
			anchor = Vector2.new(0.5, 0.5),
			radius = 18,
		})
		Kit.padding(card, 20, 16)
		Kit.text({
			parent = card,
			text = title,
			font = "title",
			textSize = Theme.TextSize.heading,
			color = Color.textDark,
			size = UDim2.new(1, -50, 0, 36),
		})
		local function close()
			dim:Destroy()
		end
		Kit.iconButton({
			parent = card,
			icon = "close",
			diameter = 34,
			style = "danger",
			position = UDim2.fromScale(1, 0),
			anchor = Vector2.new(1, 0),
			onClick = close,
		})
		Kit.popIn(card, 0.9)
		return card, close
	end

	local function openDetails()
		local banner = currentBanner()
		local live = liveBanner(snapshot, banner)
		local card =
			openModal(`{Content.text("starfall.detailsTitle")}: {banner.displayName}`, Vector2.new(720, 440))
		local rules = Kit.frame({
			parent = card,
			size = UDim2.new(0, 270, 1, -50),
			position = UDim2.fromOffset(0, 46),
			name = "Rules",
		})
		Kit.list(rules, Enum.FillDirection.Vertical, 8)
		local function rule(text: string, order: number)
			Kit.text({
				parent = rules,
				text = text,
				font = "body",
				textSize = Theme.TextSize.small,
				color = Color.textDark,
				size = UDim2.fromScale(1, 0),
				autoSize = Enum.AutomaticSize.Y,
				wrap = true,
				order = order,
				valign = Enum.TextYAlignment.Top,
			})
		end
		Kit.text({
			parent = rules,
			text = Content.text("starfall.rules"),
			font = "title",
			textSize = Theme.TextSize.label,
			color = Color.brassDark,
			size = UDim2.new(1, 0, 0, 24),
			order = 0,
		})
		rule(Content.format("starfall.ruleBase", { percent = percent(banner.baseRate5, 1) }), 1)
		rule(Content.format("starfall.ruleSoft", { count = banner.softPity5 }), 2)
		rule(Content.format("starfall.ruleHard", { count = banner.hardPity5 }), 3)
		rule(Content.format("starfall.ruleOverall", { percent = percent(Gacha.overallRate5(banner), 1) }), 4)
		rule(Content.format("starfall.ruleFourBase", { percent = percent(banner.baseRate4, 1) }), 5)
		rule(Content.format("starfall.ruleFour", { count = banner.hardPity4 }), 6)
		if banner.targetPick then
			rule(
				Content.format("starfall.ruleTarget", { percent = percent(banner.targetChance5 or 0.375, 1) }),
				7
			)
		elseif #banner.featured5 > 0 then
			rule(Content.format("starfall.ruleFeatured", { percent = percent(banner.featuredChance5, 0) }), 7)
		end
		if banner.starPickAt then
			local key = if banner.starPickOnce then "starfall.starPickOnce" else "starfall.starPickIn"
			rule(Content.format(key, { count = banner.starPickAt }), 8)
		end
		if banner.newPlayerGuarantee then
			rule(Content.format("starfall.ruleNewPlayer", { count = banner.newPlayerGuarantee.pulls }), 9)
		end
		rule(Content.text("starfall.ruleShared"), 10)

		Kit.text({
			parent = card,
			text = Content.text("starfall.listOdds"),
			font = "title",
			textSize = Theme.TextSize.label,
			color = Color.brassDark,
			size = UDim2.new(1, -290, 0, 24),
			position = UDim2.fromOffset(290, 46),
		})
		local scroll = Kit.scroll({
			parent = card,
			size = UDim2.new(1, -290, 1, -86),
			position = UDim2.fromOffset(290, 78),
		})
		Kit.list(scroll, Enum.FillDirection.Vertical, 4)
		local odds = Gacha.itemOdds(live)
		table.sort(odds, function(a, b)
			if a.rarity ~= b.rarity then
				return a.rarity > b.rarity
			end
			if a.featured ~= b.featured then
				return a.featured
			end
			return Content.itemName(a.itemId) < Content.itemName(b.itemId)
		end)
		for index, entry in odds do
			local row = Kit.frame({
				parent = scroll,
				size = UDim2.new(1, -8, 0, 26),
				color = if index % 2 == 0 then Color.paperShade else Color.paper,
				radius = 6,
				order = index,
			})
			Kit.frame({
				parent = row,
				size = UDim2.fromOffset(6, 18),
				position = UDim2.fromOffset(4, 4),
				color = Theme.rarityFor(entry.rarity, setting("colorblind")),
				radius = 3,
			})
			local name = Content.itemName(entry.itemId)
			Kit.text({
				parent = row,
				text = `{entry.rarity}★  {name}{if entry.featured then "  (rate-up)" else ""}`,
				font = "bold",
				textSize = Theme.TextSize.small,
				color = Color.textDark,
				size = UDim2.new(1, -90, 1, 0),
				position = UDim2.fromOffset(18, 0),
				truncate = true,
			})
			Kit.text({
				parent = row,
				text = percent(entry.chance, 3),
				font = "heavy",
				textSize = Theme.TextSize.small,
				color = Color.textDark,
				size = UDim2.fromOffset(70, 26),
				position = UDim2.new(1, -6, 0, 0),
				anchor = Vector2.new(1, 0),
				align = Enum.TextXAlignment.Right,
			})
		end
	end

	local function openHistory()
		local card = openModal(Content.text("starfall.historyTitle"), Vector2.new(560, 440))
		local scroll =
			Kit.scroll({ parent = card, size = UDim2.new(1, 0, 1, -100), position = UDim2.fromOffset(0, 46) })
		Kit.list(scroll, Enum.FillDirection.Vertical, 4)
		local empty = Kit.text({
			parent = card,
			text = Content.text("starfall.historyEmpty"),
			font = "body",
			textSize = Theme.TextSize.body,
			color = Color.textFaint,
			size = UDim2.new(1, 0, 0, 30),
			position = UDim2.fromOffset(0, 60),
			visible = false,
		})
		local more = Kit.button({
			parent = card,
			text = Content.text("starfall.historyMore"),
			style = "paper",
			size = UDim2.fromOffset(160, 38),
			position = UDim2.fromScale(0.5, 1),
			anchor = Vector2.new(0.5, 1),
			visible = false,
			textSize = Theme.TextSize.small,
		})
		local offset = 0
		local total = 0
		local function load()
			local answer = api.history(offset, 20)
			if not answer.ok then
				toast(errorText(answer.error))
				return
			end
			total = answer.total
			for _, entry in answer.entries do
				offset += 1
				local row = Kit.frame({
					parent = scroll,
					size = UDim2.new(1, -8, 0, 28),
					color = if offset % 2 == 0 then Color.paperShade else Color.paper,
					radius = 6,
					order = offset,
				})
				Kit.frame({
					parent = row,
					size = UDim2.fromOffset(6, 20),
					position = UDim2.fromOffset(4, 4),
					color = Theme.rarityFor(entry.rarity, setting("colorblind")),
					radius = 3,
				})
				local when = os.date("%b %d %H:%M", entry.at)
				local banner = Banners.get(entry.banner)
				Kit.text({
					parent = row,
					text = `{entry.rarity}★  {Content.itemName(entry.itemId)}`,
					font = "bold",
					textSize = Theme.TextSize.small,
					color = Color.textDark,
					size = UDim2.fromScale(0.5, 1),
					position = UDim2.fromOffset(18, 0),
					truncate = true,
				})
				Kit.text({
					parent = row,
					text = `{if banner then banner.displayName else entry.banner}  {when}`,
					font = "body",
					textSize = Theme.TextSize.tiny,
					color = Color.textFaint,
					size = UDim2.new(0.5, -24, 1, 0),
					position = UDim2.new(1, -6, 0, 0),
					anchor = Vector2.new(1, 0),
					align = Enum.TextXAlignment.Right,
					truncate = true,
				})
			end
			empty.Visible = total == 0
			more.Visible = offset < total
		end
		more.Activated:Connect(load)
		task.spawn(load)
	end

	local function openExchange()
		local banner = currentBanner()
		local card, close = openModal(Content.text("starfall.exchangeTitle"), Vector2.new(460, 330))
		local count = 1
		local usePure = false
		local selected = banner.currency or "silverStar"

		local picker =
			Kit.frame({ parent = card, size = UDim2.new(1, 0, 0, 44), position = UDim2.fromOffset(0, 50) })
		Kit.list(
			picker,
			Enum.FillDirection.Horizontal,
			10,
			Enum.HorizontalAlignment.Left,
			Enum.VerticalAlignment.Center
		)
		local costLine = Kit.text({
			parent = card,
			text = "",
			font = "bold",
			textSize = Theme.TextSize.body,
			color = Color.textDark,
			size = UDim2.new(1, 0, 0, 26),
			position = UDim2.fromOffset(0, 150),
		})
		local haveLine = Kit.text({
			parent = card,
			text = "",
			font = "body",
			textSize = Theme.TextSize.small,
			color = Color.textFaint,
			size = UDim2.new(1, 0, 0, 22),
			position = UDim2.fromOffset(0, 176),
		})
		local countLabel: TextLabel
		local choices: { [string]: TextButton } = {}

		local function source(): string
			return if usePure then "pureStarglass" else "starglass"
		end
		local function paint()
			countLabel.Text = `x{count}`
			local cost = count * Economy.StarCost
			costLine.Text = Content.format(
				"starfall.exchangeCost",
				{ cost = Theme.count(cost), currency = currencyName(source()) }
			)
			local have = ctx.profile.currency(source())
			haveLine.Text = Content.format("starfall.exchangeHave", { count = Theme.count(have) })
			haveLine.TextColor3 = if have >= cost then Color.textFaint else Color.danger
			for id, button in choices do
				button.BackgroundColor3 = if id == selected then Color.brass else Color.paperShade
			end
		end
		for index, id in { "goldStar", "silverStar" } do
			local button = Kit.button({
				parent = picker,
				text = currencyName(id),
				icon = id,
				style = "paper",
				size = UDim2.new(0.5, -5, 1, 0),
				textSize = Theme.TextSize.small,
				order = index,
				onClick = function()
					selected = id
					paint()
				end,
			})
			choices[id] = button
		end

		local stepper =
			Kit.frame({ parent = card, size = UDim2.new(1, 0, 0, 44), position = UDim2.fromOffset(0, 100) })
		Kit.list(
			stepper,
			Enum.FillDirection.Horizontal,
			12,
			Enum.HorizontalAlignment.Center,
			Enum.VerticalAlignment.Center
		)
		Kit.iconButton({
			parent = stepper,
			icon = "minus",
			diameter = 40,
			style = "dark",
			order = 1,
			onClick = function()
				count = math.max(1, count - 1)
				paint()
			end,
		})
		countLabel = Kit.text({
			parent = stepper,
			text = "x1",
			font = "title",
			textSize = Theme.TextSize.heading,
			color = Color.textDark,
			size = UDim2.fromOffset(90, 40),
			align = Enum.TextXAlignment.Center,
			order = 2,
		})
		Kit.iconButton({
			parent = stepper,
			icon = "plus",
			diameter = 40,
			style = "dark",
			order = 3,
			onClick = function()
				count = math.min(50, count + 1)
				paint()
			end,
		})

		if ctx.profile.currency("pureStarglass") > 0 then
			local row = Kit.frame({
				parent = card,
				size = UDim2.new(1, 0, 0, 34),
				position = UDim2.fromOffset(0, 208),
			})
			Kit.text({
				parent = row,
				text = Content.text("starfall.exchangeUsePure"),
				font = "bold",
				textSize = Theme.TextSize.small,
				color = Color.textDark,
				size = UDim2.new(1, -80, 1, 0),
			})
			Kit.toggle({
				parent = row,
				position = UDim2.fromScale(1, 0.5),
				anchor = Vector2.new(1, 0.5),
				size = UDim2.fromOffset(60, 30),
				onChanged = function(on: boolean)
					usePure = on
					paint()
				end,
			})
		end

		Kit.button({
			parent = card,
			text = Content.text("common.confirm"),
			style = "primary",
			size = UDim2.fromOffset(180, 46),
			position = UDim2.fromScale(1, 1),
			anchor = Vector2.new(1, 1),
			onClick = function()
				local answer = api.exchange(selected, count, usePure)
				if answer.ok then
					toast(Content.format("starfall.exchangeDone", { count = answer.count }), selected)
					close()
				else
					toast(errorText(answer.error))
				end
				paint()
			end,
		})
		paint()
	end

	-- Results ------------------------------------------------------------------------------------------------------

	local function showResults(answer: { [string]: any }, title: string)
		WishResults.show(modalLayer(), answer.results, {
			title = title,
			colorblind = setting("colorblind"),
			reducedMotion = setting("reducedMotion") == true,
			onDone = function()
				if answer.reminder then
					toast(Content.text("starfall.reminder"), "info")
				end
				refresh()
			end,
		})
	end

	local function wish(count: number)
		if busy then
			return
		end
		local banner = currentBanner()
		local cost = Gacha.cost(banner, count)
		if ctx.profile.currency(banner.currency or "silverStar") < cost then
			toast(Content.text("starfall.notEnough"), banner.currency)
			return
		end
		busy = true
		local answer = api.pull(banner.id, count)
		busy = false
		if not answer.ok then
			toast(errorText(answer.error))
			refresh()
			return
		end
		showResults(
			answer,
			if count == 1 then Content.text("starfall.pull1") else Content.text("starfall.wishResults")
		)
	end

	local function openStarPick()
		local banner = currentBanner()
		local card, close = openModal(Content.text("starfall.chooseStar"), Vector2.new(560, 360))
		local row =
			Kit.frame({ parent = card, size = UDim2.new(1, 0, 0, 200), position = UDim2.fromOffset(0, 60) })
		Kit.list(
			row,
			Enum.FillDirection.Horizontal,
			14,
			Enum.HorizontalAlignment.Center,
			Enum.VerticalAlignment.Center
		)
		for index, itemId in Gacha.starPickChoices(banner) do
			ItemCard.new({
				parent = row,
				itemId = itemId,
				size = UDim2.fromOffset(118, 168),
				order = index,
				colorblind = setting("colorblind"),
				onClick = function()
					close()
					if ctx.ui.modal then
						ctx.ui.modal({
							title = Content.text("starfall.starPickTitle"),
							body = Content.format(
								"starfall.starPickConfirm",
								{ name = Content.itemName(itemId) }
							),
							confirm = Content.text("common.confirm"),
							cancel = Content.text("common.cancel"),
							onConfirm = function()
								local answer = api.starPick(banner.id, itemId)
								if answer.ok then
									showResults(answer, Content.text("starfall.starPickTitle"))
								else
									toast(errorText(answer.error))
								end
							end,
						})
					end
				end,
			})
		end
	end

	-- Showcase -------------------------------------------------------------------------------------------------------

	local function clear(container: Instance)
		for _, child in container:GetChildren() do
			child:Destroy()
		end
	end

	local targetCards: { [string]: TextButton } = {}
	local burst: Sunburst.Burst? = nil
	local shown = false
	local builtScale = 0

	local function paintTargets()
		local banner = currentBanner()
		local target = targetOf(snapshot, banner)
		for id, card in targetCards do
			local badge = card:FindFirstChild("Badge", true)
			if badge then
				badge.Visible = id == target
			end
			local bodyFrame = card:FindFirstChild("Body")
			local stroke = bodyFrame and bodyFrame:FindFirstChildOfClass("UIStroke")
			if stroke then
				(stroke :: UIStroke).Color = if id == target
					then Color.textLight
					else Theme.rarityFor(5, setting("colorblind")):Lerp(Color3.new(0, 0, 0), 0.45)
			end
		end
	end

	-- How much room the showcase has, as a scale on its designed size (a 576 x 356 canvas).
	local function showcaseScale(): number
		local scale = math.max(ctx.scale(), 0.01)
		local width = showcase.AbsoluteSize.X / scale
		local height = showcase.AbsoluteSize.Y / scale
		if width < 10 or height < 10 then
			return 1
		end
		return math.clamp(math.min(width / 560, height / 352), 0.6, 1.15)
	end

	local function buildShowcase()
		if burst then
			burst.stop()
		end
		burst = nil
		clear(showcaseContent)
		table.clear(targetCards)
		local banner = currentBanner()
		local kind = banner.kind or "everlit"
		local inner = showcaseContent
		local k = showcaseScale()
		builtScale = k
		local function s(value: number): number
			return math.floor(value * k + 0.5)
		end
		local function miniGrid(ids: { string }, size: Vector2, x: number, y: number, perRow: number)
			for index, id in ids do
				local column = (index - 1) % perRow
				local row = math.floor((index - 1) / perRow)
				ItemCard.new({
					parent = inner,
					itemId = id,
					size = UDim2.fromOffset(size.X, size.Y),
					position = UDim2.fromOffset(x + column * (size.X + s(8)), y + row * (size.Y + s(8))),
					colorblind = setting("colorblind"),
				})
			end
		end
		local function label(text: string, x: number, y: number)
			Kit.text({
				parent = inner,
				text = text,
				font = "heavy",
				textSize = Theme.TextSize.small,
				color = Color.brassLight,
				size = UDim2.fromOffset(s(320), 20),
				position = UDim2.fromOffset(x, y),
			})
		end
		local function note(text: string, x: number, y: number, width: number)
			Kit.text({
				parent = inner,
				text = text,
				font = "body",
				textSize = Theme.TextSize.tiny,
				color = Color.textMuted,
				size = UDim2.fromOffset(width, 0),
				autoSize = Enum.AutomaticSize.Y,
				position = UDim2.fromOffset(x, y),
				wrap = true,
				valign = Enum.TextYAlignment.Top,
			})
		end

		local margin = s(24)
		local heroW, heroH, heroTop, heroCount
		if kind == "featured" then
			heroW, heroH, heroTop, heroCount = s(184), s(256), math.max(s(74), 72), 1
		elseif kind == "armoury" then
			heroW, heroH, heroTop, heroCount = s(148), s(210), math.max(s(90), 86), 2
		else
			heroW, heroH, heroTop, heroCount = s(158), s(222), math.max(s(78), 72), #Items.StandardFive
		end
		local heroGap = s(14)
		local heroSpan = heroCount * heroW + (heroCount - 1) * heroGap

		local rays = Sunburst.new(inner, BURST_COLORS[kind] or Color.star, s(340), 16)
		rays.frame.Position = UDim2.fromOffset(margin + heroSpan / 2, heroTop + heroH / 2)
		burst = rays
		if shown then
			rays.start()
		end

		Kit.text({
			parent = inner,
			text = banner.displayName,
			font = "title",
			textSize = Theme.TextSize.heading,
			color = Color.textLight,
			size = UDim2.new(1, -margin * 2, 0, 30),
			position = UDim2.fromOffset(margin, s(12)),
			stroke = true,
			strokeTransparency = 0.5,
			z = 5,
		})
		Kit.text({
			parent = inner,
			text = Content.text(`starfall.tagline.{kind}`),
			font = "body",
			textSize = Theme.TextSize.small,
			color = Color.textMuted,
			size = UDim2.new(1, -margin * 2, 0, 20),
			position = UDim2.fromOffset(margin, s(42)),
			truncate = true,
			z = 5,
		})

		local side = margin + heroSpan + s(22)
		if kind == "featured" then
			ItemCard.new({
				parent = inner,
				itemId = banner.featured5[1],
				size = UDim2.fromOffset(heroW, heroH),
				position = UDim2.fromOffset(margin, heroTop),
				colorblind = setting("colorblind"),
				badge = Content.text("starfall.featuredLabel"),
				badgeColor = Color.brass,
			})
			label(Content.text("starfall.rateUp"), side, heroTop + 2)
			miniGrid(banner.featured4, Vector2.new(s(92), s(132)), side, heroTop + s(28), 3)
			note(
				Content.format("starfall.ruleFeatured", { percent = percent(banner.featuredChance5, 0) }),
				side,
				heroTop + s(176),
				s(300)
			)
		elseif kind == "armoury" then
			label(Content.text("starfall.pickTarget"), margin, heroTop - s(24))
			for index, itemId in banner.featured5 do
				local card = ItemCard.new({
					parent = inner,
					itemId = itemId,
					size = UDim2.fromOffset(heroW, heroH),
					position = UDim2.fromOffset(margin + (index - 1) * (heroW + heroGap), heroTop),
					colorblind = setting("colorblind"),
					badge = Content.text("starfall.target"),
					badgeColor = Color.leaf,
					onClick = function()
						if busy then
							return
						end
						local answer = api.setTarget(itemId)
						if answer.ok then
							snapshot = snapshot or {}
							snapshot.flags = snapshot.flags or {}
							snapshot.flags.armouryTarget = itemId
							paintTargets()
							refresh()
						else
							toast(errorText(answer.error))
						end
					end,
				})
				targetCards[itemId] = card
			end
			label(Content.text("starfall.rateUp"), side, heroTop + 2)
			miniGrid(banner.featured4, Vector2.new(s(70), s(100)), side, heroTop + s(28), 3)
			note(
				Content.format(
					"starfall.targetChance",
					{ percent = percent(banner.targetChance5 or 0.375, 1) }
				),
				side,
				heroTop + s(150),
				s(230)
			)
			paintTargets()
		else
			for index, itemId in Items.StandardFive do
				ItemCard.new({
					parent = inner,
					itemId = itemId,
					size = UDim2.fromOffset(heroW, heroH),
					position = UDim2.fromOffset(margin + (index - 1) * (heroW + heroGap), heroTop),
					colorblind = setting("colorblind"),
				})
			end
			note(Content.text("starfall.tagline.everlit"), margin, heroTop + heroH + s(10), heroSpan)
		end
	end

	-- Banner tabs ----------------------------------------------------------------------------------------------------------

	local function paintBannerCards()
		-- Narrow screens use the short banner names.
		local tabWidth = tabs.AbsoluteSize.X / math.max(ctx.scale(), 0.01) / #Banners.Active
		for id, entry in bannerCards do
			local selected = id == selectedId
			entry.stroke.Color = if selected then Color.brass else Color.inkLine
			entry.stroke.Thickness = if selected then 3 else 1.5
			entry.card.BackgroundColor3 = if selected then Color.inkSoft else Color.ink
			local banner = Banners.byId[id]
			entry.title.Text = if tabWidth < 190
				then (banner.tabName or banner.displayName)
				else banner.displayName
			local currency = banner.currency or "silverStar"
			entry.count.Text = Theme.count(ctx.profile.currency(currency))
			if banner.maxPulls then
				local used = snapshot and snapshot.flags and snapshot.flags.firstLightPulls or 0
				entry.note.Text =
					Content.format("starfall.left", { count = math.max(0, banner.maxPulls - used) })
			else
				entry.note.Text = Content.text(`starfall.kind.{banner.kind or "everlit"}`)
			end
		end
	end

	for index, id in Banners.Active do
		local banner = Banners.byId[id]
		local card = Kit.panel({
			style = "ink",
			parent = tabs,
			size = UDim2.new(1 / #Banners.Active, -6, 1, 0),
			order = index,
			radius = 12,
			name = id,
		})
		card.Active = true
		local title = Kit.text({
			parent = card,
			text = banner.displayName,
			font = "title",
			textSize = 16,
			color = Color.textLight,
			size = UDim2.new(1, -84, 0, 22),
			position = UDim2.fromOffset(10, 3),
			truncate = true,
		})
		local note = Kit.text({
			parent = card,
			text = "",
			font = "body",
			textSize = 12,
			color = Color.textMuted,
			size = UDim2.new(1, -84, 0, 16),
			position = UDim2.fromOffset(10, 24),
			truncate = true,
		})
		local currency = banner.currency or "silverStar"
		local slot = Kit.frame({
			parent = card,
			size = UDim2.fromOffset(22, 22),
			position = UDim2.new(1, -66, 0.5, 0),
			anchor = Vector2.new(0, 0.5),
		})
		Kit.icon({ parent = slot, name = currency, size = UDim2.fromScale(1, 1), glyphSize = 16 })
		local count = Kit.text({
			parent = card,
			text = "0",
			font = "heavy",
			textSize = Theme.TextSize.small,
			color = Color.textLight,
			size = UDim2.fromOffset(40, 22),
			position = UDim2.new(1, -40, 0.5, 0),
			anchor = Vector2.new(0, 0.5),
		})
		local button = Instance.new("TextButton")
		button.BackgroundTransparency = 1
		button.Text = ""
		button.Size = UDim2.fromScale(1, 1)
		button.ZIndex = 5
		button.Parent = card
		bannerCards[id] = {
			card = card,
			stroke = card:FindFirstChildOfClass("UIStroke") :: UIStroke,
			title = title,
			note = note,
			count = count,
			slot = slot,
		}
		button.Activated:Connect(function()
			if selectedId == id then
				return
			end
			selectedId = id
			buildShowcase()
			paintBannerCards()
			refresh()
		end)
	end

	-- The player's panel ----------------------------------------------------------------------------------------------------

	refresh = function()
		snapshot = ctx.profile.get() or snapshot
		local banner = currentBanner()
		local live = liveBanner(snapshot, banner)
		local state = pityOf(snapshot, banner)
		local currency = banner.currency or "silverStar"
		paintBannerCards()

		-- Odds right now.
		local rate = Gacha.nextRate5(live, state)
		chanceLabel.Text = percent(rate, if rate < 0.1 then 1 else 0)
		pityBar.set(state.sinceLast5 / banner.hardPity5, true)
		softMarker.Position = UDim2.new((banner.softPity5 - 1) / banner.hardPity5, -1, 0, -1)
		local toGo = Gacha.pullsToGuarantee(live, state)
		pityCaption.Text =
			`{Content.format("starfall.sinceLast", { count = state.sinceLast5 })}\n{Content.format(
				"starfall.toGuarantee",
				{ count = toGo }
			)}`

		-- The guarantee line.
		if banner.targetPick then
			guaranteeText.Text = if state.guaranteedFeatured5
				then Content.text("starfall.targetNext")
				else Content.format(
					"starfall.targetChance",
					{ percent = percent(banner.targetChance5 or 0.375, 1) }
				)
			guaranteeRow.Visible = true
		elseif #banner.featured5 > 0 then
			guaranteeText.Text = if state.guaranteedFeatured5
				then Content.text("starfall.featuredNext")
				else Content.text("starfall.featuredHalf")
			guaranteeRow.Visible = true
		else
			guaranteeRow.Visible = false
		end
		guaranteeText.TextColor3 = if state.guaranteedFeatured5
			then Color3.fromRGB(40, 120, 60)
			else Color.textDark

		-- Star Pick.
		local ready = Gacha.starPickReady(banner, state)
		local left = Gacha.starPickIn(banner, state)
		pickRow.Visible = banner.starPickAt ~= nil
		pickButton.Visible = ready
		pickText.Visible = not ready
		pickBar.frame.Visible = not ready
		if banner.starPickAt and not ready then
			if left == nil then
				pickText.Text = Content.text("starfall.starPickUsed")
				pickBar.set(1)
			else
				local key = if banner.starPickOnce then "starfall.starPickOnce" else "starfall.starPickIn"
				pickText.Text = Content.format(key, { count = left })
				local progress = if banner.starPickOnce
					then state.pullsMade / banner.starPickAt
					else state.sinceFeatured5 / banner.starPickAt
				pickBar.set(progress, true)
			end
		end

		-- Buttons and balance.
		local have = ctx.profile.currency(currency)
		local used = snapshot and snapshot.flags and snapshot.flags.firstLightPulls or 0
		local cost1, cost10 = Gacha.cost(banner, 1), Gacha.cost(banner, 10)
		local out1 = have < cost1 or (banner.maxPulls ~= nil and used + 1 > banner.maxPulls)
		local out10 = have < cost10 or (banner.maxPulls ~= nil and used + 10 > banner.maxPulls)
		setPrice1(currency, cost1, not out1)
		setPrice10(currency, cost10, not out10)
		wish1.BackgroundTransparency = if out1 then 0.5 else 0
		wish10.BackgroundTransparency = if out10 then 0.5 else 0
		ownedText.Text = Theme.count(have)
		for _, child in ownedSlot:GetChildren() do
			child:Destroy()
		end
		Kit.icon({ parent = ownedSlot, name = currency, size = UDim2.fromScale(1, 1), glyphSize = 20 })
	end

	wish1.Activated:Connect(function()
		wish(1)
	end)
	wish10.Activated:Connect(function()
		wish(10)
	end)
	pickButton.Activated:Connect(openStarPick)
	exchangeButton.Activated:Connect(openExchange)
	detailsButton.Activated:Connect(openDetails)
	historyButton.Activated:Connect(openHistory)

	tabs:GetPropertyChangedSignal("AbsoluteSize"):Connect(paintBannerCards)

	-- Rebuild the showcase when the room it has changes noticeably (rotating a tablet, say).
	showcase:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
		task.defer(function()
			if math.abs(showcaseScale() - builtScale) > 0.05 then
				buildShowcase()
				refresh()
			end
		end)
	end)

	local unsubscribe: (() -> ())? = nil
	buildShowcase()
	paintBannerCards()

	return {
		root = root,
		onShow = function()
			shown = true
			if burst then
				burst.start()
			end
			if not unsubscribe then
				unsubscribe = ctx.profile.onChanged(function(next: any)
					snapshot = next
					refresh()
				end)
			end
			if math.abs(showcaseScale() - builtScale) > 0.05 then
				buildShowcase()
			end
			refresh()
		end,
		onHide = function()
			shown = false
			if burst then
				burst.stop()
			end
		end,
	}
end

return Starfall
