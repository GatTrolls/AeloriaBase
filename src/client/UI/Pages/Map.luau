--!strict
--[[
	Map page

	A parchment map of the current region: found Waystones, Starwells and landmarks as markers,
	the camp always, and a "You" dot that follows the character while the page is open. The list
	on the right names what has been found and how many are left to discover.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Content = require(ReplicatedStorage.Shared.Content)
local MapData = require(ReplicatedStorage.Shared.Config.MapData)

local Kit = require(script.Parent.Parent.Kit)
local Theme = require(script.Parent.Parent.Theme)

local Color = Theme.Color

local Map = {}

Map.id = "map"
Map.icon = "map"

local KIND_ICON = { waystone = "star", starwell = "Tide", camp = "map", landmark = "info" }
local KIND_COLOR = {
	waystone = Color.star,
	starwell = Color.sea,
	camp = Color.coral,
	landmark = Color.violet,
}

function Map.build(parent: Frame, ctx: any)
	local root = Kit.frame({ parent = parent, size = UDim2.fromScale(1, 1), name = "Map" })
	local region = MapData.Regions[1]
	local snapshot: any = ctx.profile.get()

	Kit.text({
		parent = root,
		text = Content.text("map.title"),
		font = "title",
		textSize = Theme.TextSize.title,
		color = Color.textDark,
		size = UDim2.fromOffset(240, 44),
	})
	local board = Kit.panel({
		style = "soft",
		parent = root,
		size = UDim2.new(1, -250, 1, -54),
		position = UDim2.fromOffset(0, 54),
		radius = 14,
		clip = true,
		name = "Board",
	})
	board.BackgroundColor3 = Color3.fromRGB(226, 208, 168)
	Kit.gradient(board, Color3.fromRGB(240, 226, 190), Color3.fromRGB(214, 192, 148), 90)
	for index = 1, 7 do
		Kit.frame({
			parent = board,
			size = UDim2.new(1, 0, 0, 1),
			position = UDim2.fromScale(0, index / 8),
			color = Color.paperLine,
			transparency = 0.5,
		})
		Kit.frame({
			parent = board,
			size = UDim2.new(0, 1, 1, 0),
			position = UDim2.fromScale(index / 8, 0),
			color = Color.paperLine,
			transparency = 0.5,
		})
	end
	local markers = Kit.frame({ parent = board, size = UDim2.fromScale(1, 1), name = "Markers" })
	local you = Kit.frame({
		parent = board,
		size = UDim2.fromOffset(18, 18),
		color = Color.coral,
		radius = -1,
		anchor = Vector2.new(0.5, 0.5),
		name = "You",
		z = 5,
	})
	Kit.stroke(you, Color.textLight, 2)
	local youLabel = Kit.text({
		parent = board,
		text = Content.text("map.you"),
		font = "heavy",
		textSize = Theme.TextSize.tiny,
		color = Color.textDark,
		size = UDim2.fromOffset(40, 14),
		anchor = Vector2.new(0.5, 0),
		align = Enum.TextXAlignment.Center,
		z = 5,
	})

	local side = Kit.scroll({
		parent = root,
		size = UDim2.new(0, 238, 1, -54),
		position = UDim2.new(1, 0, 0, 54),
		anchor = Vector2.new(1, 0),
		name = "Found",
	})
	Kit.list(side, Enum.FillDirection.Vertical, 6)
	Kit.padding(side, 2, 2)

	local function refresh()
		snapshot = ctx.profile.get()
		for _, child in markers:GetChildren() do
			child:Destroy()
		end
		for _, child in side:GetChildren() do
			if child:IsA("GuiObject") then
				child:Destroy()
			end
		end
		local shown = MapData.visible(region, snapshot and snapshot.flags)
		for index, point in shown do
			local u, v = MapData.project(region, point.x, point.z)
			local marker = Kit.frame({
				parent = markers,
				size = UDim2.fromOffset(30, 30),
				position = UDim2.fromScale(u, v),
				anchor = Vector2.new(0.5, 0.5),
				color = KIND_COLOR[point.kind],
				radius = -1,
			})
			Kit.stroke(marker, Color.textDark, 2)
			Kit.icon({
				parent = marker,
				name = KIND_ICON[point.kind],
				size = UDim2.fromOffset(18, 18),
				position = UDim2.fromScale(0.5, 0.5),
				anchor = Vector2.new(0.5, 0.5),
				color = Color.textDark,
				tint = true,
				glyphSize = 14,
			})
			local row = Kit.panel({
				style = "soft",
				parent = side,
				size = UDim2.new(1, -6, 0, 38),
				radius = 10,
				order = index,
			})
			row.BackgroundColor3 = Color.paperShade
			Kit.text({
				parent = row,
				text = Content.text(`map.{point.kind}`),
				font = "bold",
				textSize = Theme.TextSize.body,
				color = Color.textDark,
				size = UDim2.new(1, -16, 1, 0),
				position = UDim2.fromOffset(12, 0),
				truncate = true,
			})
		end
		local hidden = #region.points - #shown
		if hidden > 0 then
			Kit.text({
				parent = side,
				text = Content.format("map.undiscovered", { count = hidden }),
				font = "hand",
				textSize = Theme.TextSize.label,
				color = Color.textFaint,
				size = UDim2.new(1, -6, 0, 30),
				order = 100,
			})
		end
	end

	local function placeYou()
		local character = Players.LocalPlayer.Character
		local rootPart = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
		if not rootPart then
			you.Visible = false
			youLabel.Visible = false
			return
		end
		local u, v = MapData.project(region, rootPart.Position.X, rootPart.Position.Z)
		you.Visible = true
		youLabel.Visible = true
		you.Position = UDim2.fromScale(u, v)
		youLabel.Position = UDim2.new(u, 0, v, 12)
	end

	local connection: RBXScriptConnection? = nil
	local unsubscribe: (() -> ())? = nil
	return {
		root = root,
		onShow = function()
			if not unsubscribe then
				unsubscribe = ctx.profile.onChanged(function()
					if root.Visible then
						refresh()
					end
				end)
			end
			refresh()
			placeYou()
			if not connection then
				connection = RunService.Heartbeat:Connect(placeYou)
			end
		end,
		onHide = function()
			if connection then
				connection:Disconnect()
				connection = nil
			end
		end,
	}
end

return Map
