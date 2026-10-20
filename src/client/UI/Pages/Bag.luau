--!strict
--[[
	Bag page

	Everything the player owns that isn't a hero: weapons (with Polish), materials and Trinkets, in
	three tabs. Weapons use the shared ItemCard so they look the same here as in Starfall. Materials
	and Trinkets show an honest empty state until the systems that drop them arrive.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Content = require(ReplicatedStorage.Shared.Content)
local Items = require(ReplicatedStorage.Shared.Config.Items)

local ItemCard = require(script.Parent.Parent.Components.ItemCard)
local Kit = require(script.Parent.Parent.Kit)
local Theme = require(script.Parent.Parent.Theme)

local Color = Theme.Color

local Bag = {}

Bag.id = "bag"
Bag.icon = "bag"

local function sortedKeys(map: { [string]: any }, less: (string, string) -> boolean): { string }
	local keys = {}
	for key in map do
		table.insert(keys, key)
	end
	table.sort(keys, less)
	return keys
end

function Bag.build(parent: Frame, ctx: any)
	local root = Kit.frame({ parent = parent, size = UDim2.fromScale(1, 1), name = "Bag" })
	local activeTab = "weapons"
	local snapshot: any = ctx.profile.get()
	local refresh: () -> ()

	Kit.text({
		parent = root,
		text = Content.text("bag.title"),
		font = "title",
		textSize = Theme.TextSize.title,
		color = Color.textDark,
		size = UDim2.fromOffset(240, 44),
	})
	local tabs = Kit.tabs({
		parent = root,
		vertical = false,
		items = {
			{ id = "weapons", text = Content.text("bag.weapons") },
			{ id = "materials", text = Content.text("bag.materials") },
			{ id = "trinkets", text = Content.text("bag.trinkets") },
		},
		size = UDim2.fromOffset(440, 40),
		position = UDim2.new(1, 0, 0, 2),
		anchor = Vector2.new(1, 0),
		gap = 8,
		onSelect = function(id: string)
			activeTab = id
			refresh()
		end,
	})
	local body = Kit.frame({
		parent = root,
		size = UDim2.new(1, 0, 1, -54),
		position = UDim2.fromOffset(0, 54),
		name = "Body",
		clip = true,
	})

	local function empty(text: string)
		Kit.text({
			parent = body,
			text = text,
			font = "hand",
			textSize = Theme.TextSize.heading,
			color = Color.textFaint,
			size = UDim2.fromScale(1, 1),
			align = Enum.TextXAlignment.Center,
		})
	end

	local function drawWeapons()
		local weapons = snapshot and snapshot.weapons or {}
		local ids = sortedKeys(weapons, function(a, b)
			local ra = Items.get(a)
			local rb = Items.get(b)
			local sa = if ra then ra.rarity else 0
			local sb = if rb then rb.rarity else 0
			if sa ~= sb then
				return sa > sb
			end
			return Content.itemName(a) < Content.itemName(b)
		end)
		if #ids == 0 then
			empty(Content.text("bag.empty"))
			return
		end
		local scroll = Kit.scroll({ parent = body, size = UDim2.fromScale(1, 1) })
		Kit.grid(scroll, UDim2.fromOffset(132, 188), 12)
		Kit.padding(scroll, 6, 6)
		for index, id in ids do
			local entry = weapons[id]
			ItemCard.new({
				parent = scroll,
				itemId = id,
				order = index,
				badge = if (entry.polish or 1) > 1 then `P{entry.polish}` else nil,
				colorblind = snapshot and snapshot.settings and snapshot.settings.colorblind,
			})
		end
	end

	local function drawMaterials()
		local materials = snapshot and snapshot.materials or {}
		local ids = sortedKeys(materials, function(a, b)
			return a < b
		end)
		if #ids == 0 then
			empty(Content.text("bag.empty"))
			return
		end
		local scroll = Kit.scroll({ parent = body, size = UDim2.fromScale(1, 1) })
		Kit.list(scroll, Enum.FillDirection.Vertical, 6)
		Kit.padding(scroll, 2, 2)
		for index, id in ids do
			local row = Kit.panel({
				style = "soft",
				parent = scroll,
				size = UDim2.new(1, -8, 0, 40),
				radius = 10,
				order = index,
			})
			row.BackgroundColor3 = Color.paperShade
			Kit.text({
				parent = row,
				text = Content.itemName(id),
				font = "bold",
				textSize = Theme.TextSize.body,
				color = Color.textDark,
				size = UDim2.fromScale(0.7, 1),
				position = UDim2.fromOffset(14, 0),
			})
			Kit.text({
				parent = row,
				text = `x{Theme.count(materials[id])}`,
				font = "heavy",
				textSize = Theme.TextSize.body,
				color = Color.textDark,
				size = UDim2.new(0.3, -14, 1, 0),
				position = UDim2.fromScale(0.7, 0),
				align = Enum.TextXAlignment.Right,
			})
		end
	end

	refresh = function()
		snapshot = ctx.profile.get()
		for _, child in body:GetChildren() do
			child:Destroy()
		end
		if activeTab == "weapons" then
			drawWeapons()
		elseif activeTab == "materials" then
			drawMaterials()
		else
			empty(Content.text("bag.empty"))
		end
	end

	local unsubscribe: (() -> ())? = nil
	return {
		root = root,
		onShow = function()
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

return Bag
