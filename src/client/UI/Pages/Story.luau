--!strict
--[[
	Story page

	Pocket's quest log. Open quests on the left (the tracked one is marked), the chosen quest's
	notes on the right: summary, each objective with its progress, and the reward. Completed
	quests collapse into a list under the open ones. Tracking is a request to QuestService.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Content = require(ReplicatedStorage.Shared.Content)
local Net = require(ReplicatedStorage.Shared.Net)
local Quests = require(ReplicatedStorage.Shared.Config.Quests)

local Kit = require(script.Parent.Parent.Kit)
local Theme = require(script.Parent.Parent.Theme)

local Color = Theme.Color

local Story = {}

Story.id = "story"
Story.icon = "story"

local function textOr(key: string, fallback: string): string
	local text = Content.text(key)
	return if text ~= key then text else fallback
end

local function title(id: string): string
	return textOr(`quest.{id}.title`, id)
end

function Story.build(parent: Frame, ctx: any)
	local root = Kit.frame({ parent = parent, size = UDim2.fromScale(1, 1), name = "Story" })
	local snapshot: any = ctx.profile.get()
	local selected = ""
	local refresh: () -> ()

	Kit.text({
		parent = root,
		text = Content.text("quest.title"),
		font = "title",
		textSize = Theme.TextSize.title,
		color = Color.textDark,
		size = UDim2.fromOffset(300, 44),
	})
	local list = Kit.scroll({
		parent = root,
		size = UDim2.new(0, 250, 1, -54),
		position = UDim2.fromOffset(0, 54),
		name = "List",
	})
	Kit.list(list, Enum.FillDirection.Vertical, 6)
	Kit.padding(list, 2, 2)
	local detail = Kit.panel({
		style = "soft",
		parent = root,
		size = UDim2.new(1, -266, 1, -54),
		position = UDim2.fromOffset(266, 54),
		radius = 14,
		name = "Detail",
	})
	detail.BackgroundColor3 = Color.paperShade
	for _, child in detail:GetChildren() do
		if child:IsA("UIStroke") then
			child.Color = Color.paperLine
		end
	end

	local function questState(): any
		return Quests.normalize(snapshot and snapshot.quests)
	end

	local function drawDetail(state: any)
		for _, child in detail:GetChildren() do
			if not child:IsA("UIStroke") and not child:IsA("UICorner") and not child:IsA("UIGradient") then
				child:Destroy()
			end
		end
		local quest = Quests.get(selected)
		if not quest then
			Kit.text({
				parent = detail,
				text = Content.text("quest.none"),
				font = "hand",
				textSize = Theme.TextSize.heading,
				color = Color.textFaint,
				align = Enum.TextXAlignment.Center,
				size = UDim2.fromScale(1, 1),
			})
			return
		end
		local progress = state.active[selected]
		local done = state.completed[selected] == true
		Kit.text({
			parent = detail,
			text = title(selected),
			font = "title",
			textSize = Theme.TextSize.heading,
			color = Color.textDark,
			size = UDim2.new(1, -170, 0, 36),
			position = UDim2.fromOffset(16, 10),
			truncate = true,
		})
		Kit.text({
			parent = detail,
			text = textOr(`quest.{selected}.summary`, ""),
			font = "hand",
			textSize = Theme.TextSize.label,
			color = Color.textFaint,
			size = UDim2.new(1, -32, 0, 56),
			position = UDim2.fromOffset(16, 48),
			wrap = true,
			valign = Enum.TextYAlignment.Top,
		})
		for index, objective in quest.objectives do
			local step = if done then #quest.objectives + 1 else (progress and progress.step or 1)
			local complete = index < step
			local current = index == step and not done
			local row = Kit.frame({
				parent = detail,
				size = UDim2.new(1, -32, 0, 30),
				position = UDim2.fromOffset(16, 112 + (index - 1) * 34),
			})
			Kit.icon({
				parent = row,
				name = if complete then "check" else "arrow",
				size = UDim2.fromOffset(22, 22),
				position = UDim2.fromOffset(0, 4),
				color = if complete then Color.leaf else Color.textFaint,
				tint = true,
				glyphSize = 16,
			})
			local label = textOr(`quest.{selected}.obj{index}`, `{objective.kind} {objective.target}`)
			if current and objective.count > 1 then
				label ..= ` ({progress.progress}/{objective.count})`
			end
			Kit.text({
				parent = row,
				text = label,
				font = if current then "heavy" else "body",
				textSize = Theme.TextSize.body,
				color = if complete then Color.textFaint else Color.textDark,
				size = UDim2.new(1, -32, 1, 0),
				position = UDim2.fromOffset(30, 0),
				truncate = true,
			})
		end
		local rewards = Kit.frame({
			parent = detail,
			size = UDim2.new(1, -32, 0, 34),
			position = UDim2.new(0, 16, 1, -46),
		})
		Kit.list(
			rewards,
			Enum.FillDirection.Horizontal,
			8,
			Enum.HorizontalAlignment.Left,
			Enum.VerticalAlignment.Center
		)
		for _, currency in { "glint", "starglass" } do
			local amount = (quest.reward :: any)[currency]
			if amount then
				Kit.chip({
					parent = rewards,
					style = "ink",
					size = UDim2.fromOffset(104, 30),
					icon = currency,
					text = Theme.count(amount),
				})
			end
		end
		if progress then
			local tracked = state.tracked == selected
			local button = Kit.button({
				parent = detail,
				text = Content.text(if tracked then "quest.tracking" else "quest.track"),
				style = if tracked then "paper" else "primary",
				size = UDim2.fromOffset(140, 36),
				position = UDim2.new(1, -14, 0, 12),
				anchor = Vector2.new(1, 0),
				textSize = Theme.TextSize.small,
				onClick = function()
					if ctx.quests then
						ctx.quests.track(selected)
					else
						Net.event(Net.Names.QuestEvent):FireServer("track", selected)
					end
				end,
			})
			Kit.setDisabled(button, tracked)
		elseif done then
			Kit.text({
				parent = detail,
				text = Content.text("quest.completed"),
				font = "heavy",
				textSize = Theme.TextSize.label,
				color = Color.leaf,
				size = UDim2.fromOffset(140, 36),
				position = UDim2.new(1, -14, 0, 12),
				anchor = Vector2.new(1, 0),
				align = Enum.TextXAlignment.Right,
			})
		end
	end

	refresh = function()
		snapshot = ctx.profile.get()
		local state = questState()
		for _, child in list:GetChildren() do
			if child:IsA("GuiObject") then
				child:Destroy()
			end
		end
		local order = 0
		local function entry(id: string, finished: boolean)
			order += 1
			local isSelected = id == selected
			local button = Kit.button({
				parent = list,
				text = "",
				style = if isSelected then "primary" else "paper",
				size = UDim2.new(1, -4, 0, 48),
				order = order,
				onClick = function()
					selected = id
					refresh()
				end,
			})
			Kit.text({
				parent = button,
				text = title(id),
				font = "bold",
				textSize = Theme.TextSize.body,
				color = if isSelected
					then Color3.fromRGB(46, 32, 14)
					elseif finished then Color.textFaint
					else Color.textDark,
				size = UDim2.new(1, -44, 1, 0),
				position = UDim2.fromOffset(12, 0),
				truncate = true,
			})
			if state.tracked == id and not finished then
				Kit.icon({
					parent = button,
					name = "star",
					size = UDim2.fromOffset(20, 20),
					position = UDim2.new(1, -10, 0.5, 0),
					anchor = Vector2.new(1, 0.5),
					color = Color.star,
					glyphSize = 16,
				})
			end
		end
		for _, quest in Quests.list do
			if state.active[quest.id] then
				entry(quest.id, false)
			end
		end
		for _, quest in Quests.list do
			if state.completed[quest.id] then
				entry(quest.id, true)
			end
		end
		if selected == "" or not (state.active[selected] or state.completed[selected]) then
			selected = if state.tracked ~= "" then state.tracked else ""
			if selected == "" then
				for _, quest in Quests.list do
					if state.active[quest.id] then
						selected = quest.id
						break
					end
				end
			end
		end
		drawDetail(state)
	end

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
		end,
		onHide = nil,
	}
end

return Story
