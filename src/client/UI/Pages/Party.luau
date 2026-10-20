--!strict
--[[
	Party page

	The roster down the left, the chosen hero's sheet on the right: level and ascension, Awakenings
	and Friendship, then tabs for stats, talents and gear. The four party slots sit under the
	roster; tapping a slot puts the selected hero there, and the server keeps the saved party.

	Costs and caps come from Shared.Config.Progression, the same module ProgressionService charges
	with, so a button never promises what the server refuses. Every change is a request; the page
	redraws from the next profile snapshot.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Content = require(ReplicatedStorage.Shared.Content)
local GameConfig = require(ReplicatedStorage.Shared.Config.GameConfig)
local Heroes = require(ReplicatedStorage.Shared.Config.Heroes)
local Items = require(ReplicatedStorage.Shared.Config.Items)
local Net = require(ReplicatedStorage.Shared.Net)
local Progression = require(ReplicatedStorage.Shared.Config.Progression)

local Kit = require(script.Parent.Parent.Kit)
local Theme = require(script.Parent.Parent.Theme)

local Color = Theme.Color

local Party = {}

Party.id = "party"
Party.icon = "party"

local LEFT_WIDTH = 236
local TRINKET_SLOTS = { "badge", "bracelet", "compass", "lantern", "ring" }
local STAT_ROWS: { { key: string, icon: string, stat: string, percent: boolean? } } = {
	{ key = "party.stat.hp", icon = "hp", stat = "hp" },
	{ key = "party.stat.atk", icon = "atk", stat = "atk" },
	{ key = "party.stat.def", icon = "def", stat = "def" },
	{ key = "party.stat.critRate", icon = "critRate", stat = "critRate", percent = true },
	{ key = "party.stat.critDamage", icon = "critDamage", stat = "critDamage", percent = true },
	{ key = "party.stat.energy", icon = "energy", stat = "energy", percent = true },
	{ key = "party.stat.synergy", icon = "synergy", stat = "synergy", percent = true },
}
local TALENTS: { { id: string, key: string } } = {
	{ id = "basic", key = "party.talent.basic" },
	{ id = "technique", key = "party.talent.technique" },
	{ id = "finale", key = "party.talent.finale" },
}
local ROMAN = { "I", "II", "III", "IV", "V", "VI" }

local function textOr(key: string, fallback: string): string
	local text = Content.text(key)
	return if text ~= key then text else fallback
end

local function errorText(code: string?): string
	return textOr(`party.error.{code or "network"}`, Content.text("party.error.network"))
end

-- Heroes the player owns: the free team first, then everything pulled, best rarity first.
local function ownedHeroes(snapshot: any): { string }
	local list: { string } = {}
	local seen: { [string]: boolean } = {}
	for _, heroId in GameConfig.Party.StarterParty do
		if Heroes[heroId] and not seen[heroId] then
			seen[heroId] = true
			table.insert(list, heroId)
		end
	end
	local extra: { string } = {}
	local roster = snapshot and snapshot.roster or {}
	for heroId in roster do
		local item = Items.get(heroId)
		if not seen[heroId] and (Heroes[heroId] or (item and item.kind == "character")) then
			seen[heroId] = true
			table.insert(extra, heroId)
		end
	end
	table.sort(extra, function(a, b)
		local ra = if Heroes[a] then Heroes[a].rarity else (Items.get(a) :: any).rarity
		local rb = if Heroes[b] then Heroes[b].rarity else (Items.get(b) :: any).rarity
		if ra ~= rb then
			return ra > rb
		end
		return Content.heroName(a) < Content.heroName(b)
	end)
	for _, heroId in extra do
		table.insert(list, heroId)
	end
	return list
end

local function currentParty(snapshot: any): { string }
	local saved = snapshot and snapshot.party
	if type(saved) == "table" and #saved > 0 then
		return table.clone(saved)
	end
	return table.clone(GameConfig.Party.StarterParty)
end

local function entryOf(snapshot: any, heroId: string): Progression.Entry?
	local roster = snapshot and snapshot.roster
	return roster and roster[heroId]
end

local function rarityOf(heroId: string): number
	local kit = Heroes[heroId]
	if kit then
		return kit.rarity
	end
	local item = Items.get(heroId)
	return if item then item.rarity else 4
end

local function elementOf(heroId: string): string?
	local kit = Heroes[heroId]
	return kit and kit.element
end

local function weaponOf(heroId: string): string?
	local kit = Heroes[heroId]
	if kit then
		return kit.weapon
	end
	local item = Items.get(heroId)
	return item and item.weapon
end

-- A round element medallion used wherever a hero needs a face until portraits exist.
local function medallion(parent: Instance, heroId: string, diameter: number, order: number?): Frame
	local element = elementOf(heroId)
	local tint = if element then Theme.element(element) else Theme.rarity(rarityOf(heroId))
	local disc = Kit.frame({
		parent = parent,
		size = UDim2.fromOffset(diameter, diameter),
		color = tint,
		radius = -1,
		order = order,
		name = "Medallion",
	})
	Kit.gradient(disc, Color3.fromRGB(255, 255, 255), Color3.fromRGB(150, 150, 160), 90)
	Kit.stroke(disc, Color.textDark, 2)
	Kit.icon({
		parent = disc,
		name = element or "star",
		size = UDim2.fromScale(0.58, 0.58),
		position = UDim2.fromScale(0.5, 0.5),
		anchor = Vector2.new(0.5, 0.5),
		color = Color.textLight,
		tint = true,
		glyphSize = math.floor(diameter * 0.5),
	})
	return disc
end

function Party.build(parent: Frame, ctx: any)
	local root = Kit.frame({ parent = parent, size = UDim2.fromScale(1, 1), name = "Party" })
	local snapshot: any = ctx.profile.get()
	local selectedId: string = GameConfig.Party.StarterParty[1]
	local activeTab = "stats"
	local busy = false
	local refresh: () -> ()

	local function toast(text: string, icon: string?)
		if ctx.ui.toast then
			ctx.ui.toast({ text = text, icon = icon or "info" })
		end
	end
	local function glint(): number
		local currencies = snapshot and snapshot.currencies
		return if currencies and currencies.glint then currencies.glint else 0
	end

	-- Requests go through ctx.progression / ctx.party when a harness provides them, else the remotes.
	local function act(action: string, heroId: string, talent: string?): { [string]: any }
		if ctx.progression then
			return ctx.progression.act(action, heroId, talent)
		end
		local ok, result = pcall(function()
			return Net.func(Net.Names.Progression):InvokeServer(action, heroId, talent)
		end)
		return if ok and type(result) == "table" then result else { ok = false, error = "network" }
	end
	local function editParty(heroIds: { string }): { [string]: any }
		if ctx.party then
			return ctx.party.edit(heroIds)
		end
		local ok, result = pcall(function()
			return Net.func(Net.Names.PartyEdit):InvokeServer(heroIds)
		end)
		return if ok and type(result) == "table" then result else { ok = false, error = "network" }
	end
	local function request(run: () -> { [string]: any }, successText: string?)
		if busy then
			return
		end
		busy = true
		task.spawn(function()
			local result = run()
			busy = false
			if result.ok then
				if successText then
					toast(successText, "check")
				end
			else
				toast(errorText(result.error), "info")
			end
		end)
	end

	-- Left column: title, roster, party slots ---------------------------------------------------------
	local left = Kit.frame({ parent = root, size = UDim2.new(0, LEFT_WIDTH, 1, 0), name = "Left" })
	Kit.text({
		parent = left,
		text = Content.text("party.title"),
		font = "title",
		textSize = Theme.TextSize.title,
		color = Color.textDark,
		size = UDim2.new(1, 0, 0, 44),
	})
	local slotsPanel = Kit.panel({
		style = "soft",
		parent = left,
		size = UDim2.new(1, -8, 0, 118),
		position = UDim2.fromScale(0, 1),
		anchor = Vector2.new(0, 1),
		radius = 12,
		name = "Slots",
	})
	slotsPanel.BackgroundColor3 = Color.paperShade
	for _, child in slotsPanel:GetChildren() do
		if child:IsA("UIStroke") then
			child.Color = Color.paperLine
		end
	end
	Kit.text({
		parent = slotsPanel,
		text = Content.text("party.inParty"),
		font = "heavy",
		textSize = Theme.TextSize.small,
		color = Color.textFaint,
		size = UDim2.new(1, -16, 0, 22),
		position = UDim2.fromOffset(10, 4),
	})
	local slotGrid = Kit.frame({
		parent = slotsPanel,
		size = UDim2.new(1, -16, 0, 84),
		position = UDim2.fromOffset(8, 28),
		name = "SlotGrid",
	})
	Kit.grid(slotGrid, UDim2.new(0.5, -4, 0, 38), 6)
	local roster = Kit.scroll({
		parent = left,
		size = UDim2.new(1, -8, 1, -44 - 126),
		position = UDim2.fromOffset(0, 48),
		name = "Roster",
	})
	Kit.list(roster, Enum.FillDirection.Vertical, 6)
	Kit.padding(roster, 2, 2)

	-- Right column: the sheet and its tabs --------------------------------------------------------------
	local right = Kit.frame({
		parent = root,
		size = UDim2.new(1, -(LEFT_WIDTH + 12), 1, 0),
		position = UDim2.fromOffset(LEFT_WIDTH + 12, 0),
		name = "Right",
	})
	local sheet = Kit.panel({
		style = "soft",
		parent = right,
		size = UDim2.new(1, 0, 0, 196),
		radius = 14,
		name = "Sheet",
	})
	sheet.BackgroundColor3 = Color.paperShade
	for _, child in sheet:GetChildren() do
		if child:IsA("UIStroke") then
			child.Color = Color.paperLine
		end
	end
	-- Portrait window.
	local window = Kit.panel({
		style = "ink",
		parent = sheet,
		size = UDim2.fromOffset(150, 150),
		position = UDim2.fromOffset(14, 14),
		radius = 14,
		clip = true,
		name = "Portrait",
	})
	local portraitHost = Kit.frame({ parent = window, size = UDim2.fromScale(1, 1), name = "Host" })
	local weaponBadge = Kit.frame({
		parent = window,
		size = UDim2.fromOffset(38, 38),
		position = UDim2.new(1, -6, 1, -6),
		anchor = Vector2.new(1, 1),
		color = Color.paper,
		radius = -1,
		name = "WeaponBadge",
	})
	Kit.stroke(weaponBadge, Color.textDark, 2)
	local weaponIcon = Kit.icon({
		parent = weaponBadge,
		name = "sword",
		size = UDim2.fromOffset(24, 24),
		position = UDim2.fromScale(0.5, 0.5),
		anchor = Vector2.new(0.5, 0.5),
		color = Color.textDark,
		tint = true,
		glyphSize = 18,
	})
	local rarityStrip = Kit.frame({
		parent = window,
		size = UDim2.new(1, 0, 0, 6),
		position = UDim2.fromScale(0, 1),
		anchor = Vector2.new(0, 1),
		color = Color.star,
		radius = -1,
		name = "RarityStrip",
	})

	local info = Kit.frame({
		parent = sheet,
		size = UDim2.new(1, -190, 0, 170),
		position = UDim2.fromOffset(176, 10),
		name = "Info",
	})
	local nameLabel = Kit.text({
		parent = info,
		text = "",
		font = "title",
		textSize = Theme.TextSize.heading,
		color = Color.textDark,
		size = UDim2.new(1, -150, 0, 34),
		truncate = true,
		name = "Name",
	})
	local roleLabel = Kit.text({
		parent = info,
		text = "",
		font = "hand",
		textSize = Theme.TextSize.label,
		color = Color.textFaint,
		size = UDim2.new(1, -150, 0, 24),
		position = UDim2.fromOffset(0, 32),
		truncate = true,
		name = "Role",
	})
	local chips = Kit.frame({
		parent = info,
		size = UDim2.new(1, -150, 0, 28),
		position = UDim2.fromOffset(0, 60),
		name = "Chips",
	})
	Kit.list(
		chips,
		Enum.FillDirection.Horizontal,
		8,
		Enum.HorizontalAlignment.Left,
		Enum.VerticalAlignment.Center
	)
	local elementChip = Kit.chip({
		parent = chips,
		style = "ink",
		size = UDim2.fromOffset(112, 28),
		icon = "Flame",
		text = "",
		order = 1,
		name = "Element",
	})
	local starsHost =
		Kit.frame({ parent = chips, size = UDim2.fromOffset(110, 28), order = 2, name = "Stars" })
	local starsRow: Frame? = nil

	local partyButton = Kit.button({
		parent = info,
		text = Content.text("party.addToParty"),
		style = "primary",
		size = UDim2.fromOffset(140, 38),
		position = UDim2.fromScale(1, 0),
		anchor = Vector2.new(1, 0),
		textSize = Theme.TextSize.small,
		name = "PartyButton",
		onClick = function()
			local party = currentParty(snapshot)
			if table.find(party, selectedId) then
				toast(Content.text("party.inParty"), "check")
				return
			end
			if #party < GameConfig.Party.MaxMembers then
				table.insert(party, selectedId)
			else
				party[#party] = selectedId
			end
			request(function()
				return editParty(party)
			end, Content.text("party.saved"))
		end,
	})

	-- Level and ascension.
	local levelLabel = Kit.text({
		parent = info,
		text = "",
		font = "heavy",
		textSize = Theme.TextSize.label,
		color = Color.textDark,
		size = UDim2.new(0.5, 0, 0, 26),
		position = UDim2.fromOffset(0, 92),
		name = "Level",
	})
	local ascensionLabel = Kit.text({
		parent = info,
		text = "",
		font = "bold",
		textSize = Theme.TextSize.small,
		color = Color.textFaint,
		size = UDim2.new(0.5, 0, 0, 26),
		position = UDim2.new(0.5, 0, 0, 92),
		align = Enum.TextXAlignment.Right,
		name = "Ascension",
	})
	local levelBar = Kit.bar({
		parent = info,
		size = UDim2.new(1, 0, 0, 10),
		position = UDim2.fromOffset(0, 120),
		color = Color.brass,
		trackColor = Color.paperLine,
		trackTransparency = 0,
		outline = Color.paperLine,
		name = "LevelBar",
	})
	local growRow = Kit.frame({
		parent = info,
		size = UDim2.new(1, 0, 0, 36),
		position = UDim2.fromOffset(0, 136),
		name = "Grow",
	})
	Kit.list(
		growRow,
		Enum.FillDirection.Horizontal,
		8,
		Enum.HorizontalAlignment.Left,
		Enum.VerticalAlignment.Center
	)
	local levelButton = Kit.button({
		parent = growRow,
		text = Content.text("party.levelUp"),
		style = "primary",
		size = UDim2.fromOffset(150, 34),
		textSize = Theme.TextSize.small,
		order = 1,
		onClick = function()
			request(function()
				return act("levelUp", selectedId)
			end)
		end,
	})
	local ascendButton = Kit.button({
		parent = growRow,
		text = Content.text("party.ascend"),
		style = "paper",
		size = UDim2.fromOffset(150, 34),
		textSize = Theme.TextSize.small,
		order = 2,
		onClick = function()
			request(function()
				return act("ascend", selectedId)
			end)
		end,
	})
	-- Awakenings and Friendship, on the far right.
	local marks = Kit.frame({
		parent = info,
		size = UDim2.fromOffset(150, 70),
		position = UDim2.new(1, 0, 0, 44),
		anchor = Vector2.new(1, 0),
		name = "Marks",
	})
	Kit.text({
		parent = marks,
		text = Content.text("party.awakenings"),
		font = "heavy",
		textSize = Theme.TextSize.tiny,
		color = Color.textFaint,
		size = UDim2.new(1, 0, 0, 16),
	})
	local pipRow =
		Kit.frame({ parent = marks, size = UDim2.new(1, 0, 0, 20), position = UDim2.fromOffset(0, 16) })
	Kit.list(
		pipRow,
		Enum.FillDirection.Horizontal,
		4,
		Enum.HorizontalAlignment.Left,
		Enum.VerticalAlignment.Center
	)
	local pips: { Frame } = {}
	for index = 1, 6 do
		local pip = Kit.frame({
			parent = pipRow,
			size = UDim2.fromOffset(20, 20),
			color = Color.paperLine,
			radius = -1,
			order = index,
		})
		Kit.stroke(pip, Color.textDark, 1.5, 0.4)
		Kit.text({
			parent = pip,
			text = ROMAN[index],
			font = "heavy",
			textSize = 11,
			color = Color.textDark,
			align = Enum.TextXAlignment.Center,
			size = UDim2.fromScale(1, 1),
		})
		pips[index] = pip
	end
	Kit.text({
		parent = marks,
		text = Content.text("party.friendship"),
		font = "heavy",
		textSize = Theme.TextSize.tiny,
		color = Color.textFaint,
		size = UDim2.new(0.6, 0, 0, 16),
		position = UDim2.fromOffset(0, 42),
	})
	local friendshipLabel = Kit.text({
		parent = marks,
		text = "",
		font = "heavy",
		textSize = Theme.TextSize.tiny,
		color = Color.textDark,
		size = UDim2.new(0.4, 0, 0, 16),
		position = UDim2.new(0.6, 0, 0, 42),
		align = Enum.TextXAlignment.Right,
	})
	local friendshipBar = Kit.bar({
		parent = marks,
		size = UDim2.new(1, 0, 0, 8),
		position = UDim2.fromOffset(0, 60),
		color = Color.coral,
		trackColor = Color.paperLine,
		trackTransparency = 0,
		outline = Color.paperLine,
	})

	-- Tabs under the sheet.
	local tabContent = Kit.frame({
		parent = right,
		size = UDim2.new(1, 0, 1, -252),
		position = UDim2.fromOffset(0, 252),
		name = "TabContent",
		clip = true,
	})
	local tabs = Kit.tabs({
		parent = right,
		vertical = false,
		tabStyle = "line",
		items = {
			{ id = "stats", text = Content.text("party.stats") },
			{ id = "talents", text = Content.text("party.talents") },
			{ id = "gear", text = Content.text("party.gear") },
		},
		size = UDim2.new(1, 0, 0, 40),
		position = UDim2.fromOffset(0, 204),
		gap = 8,
		onSelect = function(id: string)
			activeTab = id
			refresh()
		end,
	})

	-- Drawing ---------------------------------------------------------------------------------------------
	local function card(host: Instance, height: number, order: number): Frame
		local frame = Kit.panel({
			style = "soft",
			parent = host,
			size = UDim2.new(1, -8, 0, height),
			radius = 12,
			order = order,
		})
		frame.BackgroundColor3 = Color.paperShade
		for _, child in frame:GetChildren() do
			if child:IsA("UIStroke") then
				child.Color = Color.paperLine
			end
		end
		return frame
	end

	local function drawStats(host: Instance, kit: Heroes.Kit?, entry: Progression.Entry?)
		local scroll = Kit.scroll({ parent = host, size = UDim2.fromScale(1, 1) })
		Kit.list(scroll, Enum.FillDirection.Vertical, 6)
		Kit.padding(scroll, 2, 2)
		if not kit then
			Kit.text({
				parent = scroll,
				text = Content.text("party.kitSoon"),
				font = "hand",
				textSize = Theme.TextSize.label,
				color = Color.textFaint,
				size = UDim2.new(1, -8, 0, 40),
			})
			return
		end
		local stats = Progression.stats(kit, entry)
		for index, row in STAT_ROWS do
			local line = card(scroll, 34, index)
			Kit.icon({
				parent = line,
				name = row.icon,
				size = UDim2.fromOffset(22, 22),
				position = UDim2.fromOffset(10, 6),
				color = Color.textDark,
				tint = true,
				glyphSize = 16,
			})
			Kit.text({
				parent = line,
				text = Content.text(row.key),
				font = "bold",
				textSize = Theme.TextSize.body,
				color = Color.textDark,
				size = UDim2.new(0.6, -40, 1, 0),
				position = UDim2.fromOffset(40, 0),
			})
			local value = (stats :: any)[row.stat]
			Kit.text({
				parent = line,
				text = if row.percent then string.format("%.1f%%", value * 100) else Theme.count(value),
				font = "heavy",
				textSize = Theme.TextSize.body,
				color = Color.textDark,
				size = UDim2.new(0.4, -12, 1, 0),
				position = UDim2.fromScale(0.6, 0),
				align = Enum.TextXAlignment.Right,
			})
		end
	end

	local function talentLine(kit: Heroes.Kit, talent: string): string
		local custom = Content.text(`hero.{kit.id}.{talent}`)
		if custom ~= `hero.{kit.id}.{talent}` then
			return custom
		end
		if talent == "basic" then
			return Content.format("party.talentBasicHint", { hits = #kit.chain })
		elseif talent == "technique" then
			return Content.format("party.talentTechniqueHint", { seconds = kit.technique.cooldown })
		end
		return Content.format("party.talentFinaleHint", { energy = kit.finale.energyCost })
	end

	local function drawTalents(host: Instance, kit: Heroes.Kit?, entry: Progression.Entry?)
		local scroll = Kit.scroll({ parent = host, size = UDim2.fromScale(1, 1) })
		Kit.list(scroll, Enum.FillDirection.Vertical, 8)
		Kit.padding(scroll, 2, 2)
		if not kit then
			Kit.text({
				parent = scroll,
				text = Content.text("party.kitSoon"),
				font = "hand",
				textSize = Theme.TextSize.label,
				color = Color.textFaint,
				size = UDim2.new(1, -8, 0, 40),
			})
			return
		end
		for index, talent in TALENTS do
			local level = Progression.talentLevel(entry, talent.id)
			local line = card(scroll, 78, index)
			Kit.text({
				parent = line,
				text = Content.text(talent.key),
				font = "heavy",
				textSize = Theme.TextSize.label,
				color = Color.textDark,
				size = UDim2.new(0.3, -12, 0, 26),
				position = UDim2.fromOffset(14, 8),
			})
			Kit.text({
				parent = line,
				text = Content.format("party.talentLevel", { level = level, max = Progression.MaxTalent }),
				font = "bold",
				textSize = Theme.TextSize.small,
				color = Color.textFaint,
				size = UDim2.new(0.3, -12, 0, 26),
				position = UDim2.fromOffset(14, 32),
			})
			Kit.text({
				parent = line,
				text = talentLine(kit, talent.id),
				font = "body",
				textSize = Theme.TextSize.small,
				color = Color.textDark,
				size = UDim2.new(0.7, -190, 0, 62),
				position = UDim2.new(0.3, 0, 0, 8),
				wrap = true,
				valign = Enum.TextYAlignment.Top,
			})
			local maxed = level >= Progression.MaxTalent
			local cost = Progression.talentCost(level)
			local button = Kit.button({
				parent = line,
				text = if maxed
					then Content.text("common.max")
					else Content.format("party.raiseFor", { cost = Theme.count(cost) }),
				style = if maxed then "paper" else "primary",
				size = UDim2.fromOffset(150, 34),
				position = UDim2.new(1, -12, 0.5, 0),
				anchor = Vector2.new(1, 0.5),
				textSize = Theme.TextSize.small,
				onClick = function()
					request(function()
						return act("talent", selectedId, talent.id)
					end)
				end,
			})
			Kit.setDisabled(button, maxed or glint() < cost)
		end
	end

	local function drawGear(host: Instance, kit: Heroes.Kit?)
		local scroll = Kit.scroll({ parent = host, size = UDim2.fromScale(1, 1) })
		Kit.list(scroll, Enum.FillDirection.Vertical, 8)
		Kit.padding(scroll, 2, 2)
		local weaponCard = card(scroll, 64, 1)
		Kit.icon({
			parent = weaponCard,
			name = weaponOf(selectedId) or "sword",
			size = UDim2.fromOffset(34, 34),
			position = UDim2.fromOffset(14, 15),
			color = Color.textDark,
			tint = true,
			glyphSize = 24,
		})
		Kit.text({
			parent = weaponCard,
			text = Content.text("party.weapon"),
			font = "heavy",
			textSize = Theme.TextSize.label,
			color = Color.textDark,
			size = UDim2.new(1, -70, 0, 26),
			position = UDim2.fromOffset(60, 8),
		})
		Kit.text({
			parent = weaponCard,
			text = if kit
				then Content.format("party.trainingWeapon", { kind = Content.text(`weapon.{kit.weapon}`) })
				else Content.text("party.noWeapon"),
			font = "body",
			textSize = Theme.TextSize.small,
			color = Color.textFaint,
			size = UDim2.new(1, -70, 0, 22),
			position = UDim2.fromOffset(60, 32),
			truncate = true,
		})
		local trinketCard = card(scroll, 112, 2)
		Kit.text({
			parent = trinketCard,
			text = Content.text("party.trinkets"),
			font = "heavy",
			textSize = Theme.TextSize.label,
			color = Color.textDark,
			size = UDim2.new(0.5, 0, 0, 26),
			position = UDim2.fromOffset(14, 8),
		})
		Kit.text({
			parent = trinketCard,
			text = Content.format("party.locked", { rank = 10 }),
			font = "hand",
			textSize = Theme.TextSize.small,
			color = Color.textFaint,
			size = UDim2.new(0.5, -14, 0, 26),
			position = UDim2.new(0.5, 0, 0, 8),
			align = Enum.TextXAlignment.Right,
		})
		local row = Kit.frame({
			parent = trinketCard,
			size = UDim2.new(1, -28, 0, 60),
			position = UDim2.fromOffset(14, 40),
		})
		Kit.list(
			row,
			Enum.FillDirection.Horizontal,
			10,
			Enum.HorizontalAlignment.Left,
			Enum.VerticalAlignment.Center
		)
		for index, slot in TRINKET_SLOTS do
			local cell = Kit.frame({
				parent = row,
				size = UDim2.fromOffset(72, 60),
				order = index,
			})
			local box = Kit.frame({
				parent = cell,
				size = UDim2.fromOffset(40, 40),
				position = UDim2.fromScale(0.5, 0),
				anchor = Vector2.new(0.5, 0),
				color = Color.paper,
				radius = 10,
			})
			Kit.stroke(box, Color.paperLine, 1.5)
			Kit.icon({
				parent = box,
				name = "lock",
				size = UDim2.fromOffset(20, 20),
				position = UDim2.fromScale(0.5, 0.5),
				anchor = Vector2.new(0.5, 0.5),
				color = Color.paperLine,
				tint = true,
				glyphSize = 16,
			})
			Kit.text({
				parent = cell,
				text = Content.text(`party.trinketSlot.{slot}`),
				font = "bold",
				textSize = Theme.TextSize.tiny,
				color = Color.textFaint,
				align = Enum.TextXAlignment.Center,
				size = UDim2.new(1, 0, 0, 18),
				position = UDim2.fromOffset(0, 42),
			})
		end
	end

	local function drawSlots(party: { string })
		for _, child in slotGrid:GetChildren() do
			if child:IsA("GuiObject") then
				child:Destroy()
			end
		end
		for slot = 1, GameConfig.Party.MaxMembers do
			local heroId = party[slot]
			local button = Kit.button({
				parent = slotGrid,
				text = "",
				style = if heroId then "dark" else "paper",
				order = slot,
				onClick = function()
					local next = currentParty(snapshot)
					local existing = table.find(next, selectedId)
					if existing == slot then
						return
					end
					if existing then
						next[existing], next[slot] = next[slot], next[existing]
					else
						next[slot] = selectedId
					end
					-- Slots stay packed from the front.
					local packed = {}
					for index = 1, GameConfig.Party.MaxMembers do
						if next[index] then
							table.insert(packed, next[index])
						end
					end
					request(function()
						return editParty(packed)
					end, Content.text("party.saved"))
				end,
			})
			if heroId then
				medallion(button, heroId, 26).Position = UDim2.fromOffset(6, 6)
				Kit.text({
					parent = button,
					text = Content.heroName(heroId),
					font = "bold",
					textSize = Theme.TextSize.tiny,
					color = Color.textLight,
					size = UDim2.new(1, -40, 1, 0),
					position = UDim2.fromOffset(36, 0),
					truncate = true,
				})
				if heroId == selectedId then
					Kit.stroke(button, Color.brass, 2.5)
				end
			else
				Kit.text({
					parent = button,
					text = Content.format("party.slot", { slot = slot }),
					font = "bold",
					textSize = Theme.TextSize.tiny,
					color = Color.textFaint,
					align = Enum.TextXAlignment.Center,
					size = UDim2.fromScale(1, 1),
				})
			end
		end
	end

	local function drawRoster(heroes: { string }, party: { string })
		for _, child in roster:GetChildren() do
			if child:IsA("GuiObject") then
				child:Destroy()
			end
		end
		for index, heroId in heroes do
			local selected = heroId == selectedId
			local entry = entryOf(snapshot, heroId)
			local row = Kit.button({
				parent = roster,
				text = "",
				style = if selected then "primary" else "paper",
				size = UDim2.new(1, -4, 0, 60),
				order = index,
				onClick = function()
					selectedId = heroId
					refresh()
				end,
			})
			medallion(row, heroId, 44).Position = UDim2.fromOffset(8, 8)
			Kit.text({
				parent = row,
				text = Content.heroName(heroId),
				font = "heavy",
				textSize = Theme.TextSize.body,
				color = if selected then Color3.fromRGB(46, 32, 14) else Color.textDark,
				size = UDim2.new(1, -66, 0, 24),
				position = UDim2.fromOffset(60, 6),
				truncate = true,
			})
			Kit.text({
				parent = row,
				text = Content.format("party.level", { level = if entry then entry.level else 1 }),
				font = "bold",
				textSize = Theme.TextSize.tiny,
				color = if selected then Color3.fromRGB(70, 48, 20) else Color.textFaint,
				size = UDim2.fromOffset(60, 18),
				position = UDim2.fromOffset(60, 32),
			})
			Kit.stars({
				parent = row,
				filled = rarityOf(heroId),
				total = rarityOf(heroId),
				starSize = 11,
				position = UDim2.fromOffset(118, 34),
			})
			if table.find(party, heroId) then
				Kit.icon({
					parent = row,
					name = "check",
					size = UDim2.fromOffset(18, 18),
					position = UDim2.new(1, -8, 0, 8),
					anchor = Vector2.new(1, 0),
					color = if selected then Color3.fromRGB(46, 32, 14) else Color.leaf,
					tint = true,
					glyphSize = 14,
				})
			end
		end
	end

	local function drawSheet(kit: Heroes.Kit?, entry: Progression.Entry?, party: { string })
		for _, child in portraitHost:GetChildren() do
			child:Destroy()
		end
		local disc = medallion(portraitHost, selectedId, 104)
		disc.Position = UDim2.fromScale(0.5, 0.46)
		disc.AnchorPoint = Vector2.new(0.5, 0.5)
		Kit.gradient(portraitHost, Color.inkSoft, Color.night, 90)
		local weapon = weaponOf(selectedId) or "sword"
		local replaced = Kit.icon({
			parent = weaponBadge,
			name = weapon,
			size = UDim2.fromOffset(24, 24),
			position = UDim2.fromScale(0.5, 0.5),
			anchor = Vector2.new(0.5, 0.5),
			color = Color.textDark,
			tint = true,
			glyphSize = 18,
		})
		weaponIcon:Destroy()
		weaponIcon = replaced
		local rarity = rarityOf(selectedId)
		rarityStrip.BackgroundColor3 = Theme.rarity(rarity)

		nameLabel.Text = Content.heroName(selectedId)
		roleLabel.Text = if kit
			then `{kit.role} · {Content.text(`weapon.{kit.weapon}`)}`
			else Content.text("party.kitSoon")
		local element = elementOf(selectedId)
		elementChip.frame.Visible = element ~= nil
		if element then
			local icon = elementChip.frame:FindFirstChild(element, true)
				or elementChip.frame:FindFirstChildWhichIsA("ImageLabel", true)
			local row = elementChip.frame:FindFirstChildWhichIsA("Frame")
			if row then
				for _, child in row:GetChildren() do
					if child:IsA("ImageLabel") or (child:IsA("TextLabel") and child.Name ~= "Value") then
						child:Destroy()
					end
				end
				Kit.icon({
					parent = row,
					name = element,
					size = UDim2.fromOffset(22, 22),
					color = Theme.element(element),
					order = 1,
					glyphSize = 16,
				})
			end
			elementChip.set(Content.text(`element.{element}`))
			local _ = icon
		end
		if starsRow then
			starsRow:Destroy()
		end
		starsRow = Kit.stars({ parent = starsHost, filled = rarity, total = rarity, starSize = 16 })
		starsRow.Position = UDim2.fromScale(0, 0.5)
		starsRow.AnchorPoint = Vector2.new(0, 0.5)

		local level = if entry then entry.level else 1
		local ascension = if entry then entry.ascension else 0
		local cap = Progression.cap(ascension)
		levelLabel.Text = Content.format("party.levelOf", { level = level, cap = cap })
		ascensionLabel.Text =
			Content.format("party.ascensionOf", { step = ascension, max = Progression.MaxAscension })
		levelBar.set(level / Progression.MaxLevel, true)

		local inParty = table.find(party, selectedId) ~= nil
		Kit.setLabel(partyButton, Content.text(if inParty then "party.inParty" else "party.addToParty"))
		Kit.setDisabled(partyButton, inParty or kit == nil)

		local levelBlock = if kit then Progression.levelBlock(snapshot or {}, selectedId) else "not_owned"
		local ascendBlock = if kit then Progression.ascendBlock(snapshot or {}, selectedId) else "not_owned"
		Kit.setLabel(
			levelButton,
			if level >= cap
				then Content.text("common.max")
				else Content.format(
					"party.levelFor",
					{ cost = Theme.count(Progression.levelCost(level)) }
				)
		)
		Kit.setDisabled(levelButton, levelBlock ~= nil)
		Kit.setLabel(
			ascendButton,
			if ascension >= Progression.MaxAscension
				then Content.text("common.max")
				else Content.format(
					"party.ascendFor",
					{ cost = Theme.count(Progression.ascendCost(ascension)) }
				)
		)
		Kit.setDisabled(ascendButton, ascendBlock ~= nil)
		ascendButton.Visible = level >= cap or ascension > 0

		local awakening = if entry then entry.awakening else 0
		for index, pip in pips do
			pip.BackgroundColor3 = if index <= awakening then Color.star else Color.paperLine
		end
		local friendship = if entry then entry.friendship else 0
		friendshipLabel.Text = `{friendship} / {Progression.MaxFriendship}`
		friendshipBar.set(friendship / Progression.MaxFriendship, true)
	end

	refresh = function()
		snapshot = ctx.profile.get()
		local heroes = ownedHeroes(snapshot)
		if not table.find(heroes, selectedId) then
			selectedId = heroes[1] or selectedId
		end
		local party = currentParty(snapshot)
		local kit = Heroes[selectedId]
		local entry = entryOf(snapshot, selectedId)
		drawRoster(heroes, party)
		drawSlots(party)
		drawSheet(kit, entry, party)
		for _, child in tabContent:GetChildren() do
			child:Destroy()
		end
		if activeTab == "stats" then
			drawStats(tabContent, kit, entry)
		elseif activeTab == "talents" then
			drawTalents(tabContent, kit, entry)
		else
			drawGear(tabContent, kit)
		end
	end

	local unsubscribe: (() -> ())? = nil
	return {
		root = root,
		onShow = function(params: any?)
			if params and type(params.heroId) == "string" then
				selectedId = params.heroId
			end
			if params and type(params.section) == "string" then
				activeTab = params.section
			end
			tabs.select(activeTab, true)
			if not unsubscribe then
				unsubscribe = ctx.profile.onChanged(function()
					if root.Visible then
						refresh()
					end
				end)
			end
			refresh()
		end,
		onHide = nil,
	}
end

return Party
