--!strict
--[[
	Notebook

	The menu hub: Pocket's field notebook. A night sky behind an open book; index tabs down the
	left edge (Story, Party, Bag, Starfall, Map, Settings) and the player's currencies along the
	top. Each tab is a page module in UI/Pages that builds itself on first visit.

	A page is `{ build = function(parent, ctx) -> { root, onShow(params), onHide() } }`.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Content = require(ReplicatedStorage.Shared.Content)
local Economy = require(ReplicatedStorage.Shared.Config.Economy)

local Kit = require(script.Parent.Parent.Kit)
local Theme = require(script.Parent.Parent.Theme)

local Color = Theme.Color

export type Page = {
	root: GuiObject,
	onShow: ((params: any?) -> ())?,
	onHide: (() -> ())?,
}

export type PageDef = {
	id: string,
	icon: string,
	build: (parent: Frame, ctx: any) -> Page,
}

local Notebook = {}

local TABS = {
	{ id = "story", icon = "story", key = "tab.story" },
	{ id = "party", icon = "party", key = "tab.party" },
	{ id = "bag", icon = "bag", key = "tab.bag" },
	{ id = "starfall", icon = "starfall", key = "tab.starfall" },
	{ id = "map", icon = "map", key = "tab.map" },
	{ id = "settings", icon = "settings", key = "tab.settings" },
}

local pageDefs: { [string]: PageDef } = {}

function Notebook.registerPage(def: PageDef)
	pageDefs[def.id] = def
end

-- A scatter of twinkling stars behind the book. They only animate while the screen is visible.
local function buildSky(parent: Frame): { stop: () -> (), start: () -> () }
	local sky = Kit.frame({
		parent = parent,
		size = UDim2.fromScale(1, 1),
		color = Color.night,
		name = "Sky",
		clip = true,
	})
	Kit.gradient(sky, Color3.fromRGB(34, 46, 88), Color3.fromRGB(10, 14, 30), 90)
	local rng = Random.new(7)
	local stars: { Frame } = {}
	for index = 1, 46 do
		local size = rng:NextInteger(2, 5)
		local star = Kit.frame({
			parent = sky,
			size = UDim2.fromOffset(size, size),
			position = UDim2.fromScale(rng:NextNumber(), rng:NextNumber()),
			color = Color.textLight,
			radius = -1,
			transparency = rng:NextNumber(0.2, 0.7),
			name = `Star{index}`,
		})
		stars[index] = star
	end
	-- A pale compass ring in the lower corner, the kit's signature.
	local ring = Kit.frame({
		parent = sky,
		size = UDim2.fromOffset(520, 520),
		position = UDim2.new(1, -120, 1, -80),
		anchor = Vector2.new(0.5, 0.5),
		radius = -1,
		name = "Compass",
	})
	ring.BackgroundTransparency = 1
	Kit.stroke(ring, Color.brass, 3, 0.82)
	local inner = Kit.frame({
		parent = ring,
		size = UDim2.fromScale(0.78, 0.78),
		position = UDim2.fromScale(0.5, 0.5),
		anchor = Vector2.new(0.5, 0.5),
		radius = -1,
	})
	inner.BackgroundTransparency = 1
	Kit.stroke(inner, Color.brass, 2, 0.88)
	for _, rotation in { 0, 45, 90, 135 } do
		local spoke = Kit.frame({
			parent = ring,
			size = UDim2.new(1, 0, 0, 2),
			position = UDim2.fromScale(0.5, 0.5),
			anchor = Vector2.new(0.5, 0.5),
			color = Color.brass,
			transparency = 0.9,
		})
		spoke.Rotation = rotation
	end

	local running = false
	local function twinkle()
		task.spawn(function()
			while running do
				local star = stars[rng:NextInteger(1, #stars)]
				if star.Parent then
					local to = rng:NextNumber(0.1, 0.8)
					Kit.tween(
						star,
						TweenInfo.new(
							rng:NextNumber(0.6, 1.4),
							Enum.EasingStyle.Sine,
							Enum.EasingDirection.InOut
						),
						{ BackgroundTransparency = to }
					)
				end
				task.wait(0.07)
			end
		end)
	end
	return {
		start = function()
			if not running then
				running = true
				twinkle()
			end
		end,
		stop = function()
			running = false
		end,
	}
end

function Notebook.build(ctx: any)
	local root = Kit.frame({ size = UDim2.fromScale(1, 1), name = "Notebook" })
	root.Active = true
	local sky = buildSky(root)

	-- The book.
	local book = Kit.panel({
		style = "paper",
		parent = root,
		name = "Book",
		size = UDim2.fromScale(0.95, 0.9),
		position = UDim2.fromScale(0.5, 0.5),
		anchor = Vector2.new(0.5, 0.5),
		radius = 20,
		strokeThickness = 3,
	})
	local constraint = Instance.new("UISizeConstraint")
	constraint.MaxSize = Vector2.new(1160, 600)
	constraint.MinSize = Vector2.new(640, 330)
	constraint.Parent = book

	-- Spine shadow down the page gutter.
	local gutter = Kit.frame({
		parent = book,
		size = UDim2.new(0, 6, 1, -28),
		position = UDim2.fromOffset(142, 14),
		color = Color.paperShade,
		radius = 3,
	})
	gutter.BackgroundTransparency = 0.4

	-- Index tabs sit on the left edge, half outside the page like real notebook tabs.
	local tabItems = {}
	for _, tab in TABS do
		table.insert(tabItems, { id = tab.id, text = Content.text(tab.key), icon = tab.icon })
	end
	local pages: { [string]: Page } = {}
	local current = ""
	local contentHost = Kit.frame({
		parent = book,
		size = UDim2.new(1, -176, 1, -86),
		position = UDim2.fromOffset(160, 70),
		name = "Content",
		clip = true,
	})

	local tabs: any
	local function show(id: string, params: any?)
		if current ~= "" and pages[current] then
			local old = pages[current]
			if old.onHide then
				old.onHide()
			end
			old.root.Visible = false
		end
		current = id
		ctx.ui.currentTab = id
		local page = pages[id]
		if not page then
			local def = pageDefs[id]
			if not def then
				return
			end
			page = def.build(contentHost, ctx)
			page.root.Size = UDim2.fromScale(1, 1)
			pages[id] = page
		end
		page.root.Visible = true
		if page.onShow then
			page.onShow(params)
		end
		Kit.popIn(page.root, 0.97)
	end

	tabs = Kit.tabs({
		parent = book,
		items = tabItems,
		vertical = true,
		size = UDim2.new(0, 132, 1, -40),
		position = UDim2.fromOffset(-30, 20),
		tabSize = 54,
		gap = 10,
		onSelect = function(id: string)
			show(id)
		end,
	})
	tabs.frame.ZIndex = 5

	-- Top bar: page title area is drawn by pages; here are currencies and the close button.
	local bar = Kit.frame({
		parent = book,
		size = UDim2.new(1, -176, 0, 40),
		position = UDim2.fromOffset(160, 14),
		name = "TopBar",
	})
	local chips = Kit.frame({ parent = bar, size = UDim2.new(1, -52, 1, 0), name = "Currencies" })
	Kit.list(
		chips,
		Enum.FillDirection.Horizontal,
		8,
		Enum.HorizontalAlignment.Right,
		Enum.VerticalAlignment.Center
	)
	local chipRefs: { [string]: { frame: Frame, set: (string) -> () } } = {}
	for index, id in Economy.Order do
		if id == "pureStarglass" then
			continue
		end
		local currency = Economy.Currencies[id]
		local chip = Kit.chip({
			parent = chips,
			style = "ink",
			size = UDim2.fromOffset(112, 32),
			icon = id,
			iconColor = Color3.fromRGB(currency.color[1], currency.color[2], currency.color[3]),
			text = "0",
			color = Color.textLight,
			order = index,
			name = id,
		})
		chipRefs[id] = chip
	end
	Kit.iconButton({
		parent = bar,
		icon = "close",
		diameter = 36,
		style = "danger",
		position = UDim2.fromScale(1, 0.5),
		anchor = Vector2.new(1, 0.5),
		onClick = function()
			ctx.ui.close()
		end,
	})

	-- Narrow screens (a tablet held in landscape) get icon-only tabs and smaller currency chips, which
	-- gives the pages back about 90 virtual pixels.
	local function applyLayout()
		local scale = math.max(if ctx.scale then ctx.scale() else 1, 0.01)
		local width = book.AbsoluteSize.X / scale
		local compact = width < 900
		local left = if compact then 76 else 160
		tabs.frame.Size = UDim2.new(0, if compact then 60 else 132, 1, -40)
		tabs.frame.Position = UDim2.fromOffset(if compact then -22 else -30, 20)
		tabs.setCompact(compact)
		contentHost.Position = UDim2.fromOffset(left, 70)
		contentHost.Size = UDim2.new(1, -(left + 16), 1, -86)
		bar.Position = UDim2.fromOffset(left, 14)
		bar.Size = UDim2.new(1, -(left + 16), 0, 40)
		gutter.Position = UDim2.fromOffset(left - 18, 14)
		for _, chip in chipRefs do
			chip.frame.Size = UDim2.fromOffset(if compact then 86 else 112, if compact then 30 else 32)
		end
	end
	book:GetPropertyChangedSignal("AbsoluteSize"):Connect(applyLayout)

	local function refreshCurrencies(profile: any)
		local currencies = profile and profile.currencies or {}
		for id, chip in chipRefs do
			chip.set(Theme.count(currencies[id] or 0))
		end
	end
	local unsubscribe: (() -> ())? = nil

	return {
		root = root,
		open = function(params: any?)
			applyLayout()
			local tab = (params and params.tab) or (current ~= "" and current) or "story"
			sky.start()
			if not unsubscribe then
				unsubscribe = ctx.profile.onChanged(refreshCurrencies)
			end
			tabs.select(tab, true)
			show(tab, params)
			Kit.popIn(book, 0.94)
		end,
		close = function()
			sky.stop()
			if current ~= "" and pages[current] and pages[current].onHide then
				(pages[current].onHide :: () -> ())()
			end
		end,
		selectTab = function(id: string)
			tabs.select(id, true)
			show(id)
		end,
	}
end

return Notebook
