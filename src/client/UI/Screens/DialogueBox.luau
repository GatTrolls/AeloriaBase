--!strict
--[[
	DialogueBox

	The conversation box at the bottom of the screen: speaker name tab, text that types itself
	out (tap to finish a line, tap again for the next), Skip, Auto and choice buttons. A
	conversation is a list of lines; a line may carry choices that jump to another line index.

	  local box = DialogueBox.build(parentFrame)
	  box.play({ { speaker = "Pocket", text = "..." }, { text = "...", choices = { { text = "Sure", next = 3 } } } }, onDone)

	Pure presentation: the server (or a cutscene) decides what is said; this just shows it, with the
	design plan's rules: short lines, always skippable, auto-advance available.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Content = require(ReplicatedStorage.Shared.Content)

local Kit = require(script.Parent.Parent.Kit)
local Theme = require(script.Parent.Parent.Theme)

local Color = Theme.Color

export type Choice = { text: string, next: number? }
export type Line = { speaker: string?, text: string, choices: { Choice }? }

local DialogueBox = {}

local CHARS_PER_SECOND = 55
local AUTO_DELAY = 1.6

function DialogueBox.build(parent: Instance)
	local root = Kit.frame({ parent = parent, size = UDim2.fromScale(1, 1), name = "Dialogue" })
	root.Visible = false
	root.Active = true

	local card = Kit.panel({
		style = "paper",
		parent = root,
		size = UDim2.new(0.8, 0, 0, 168),
		position = UDim2.new(0.5, 0, 1, -16),
		anchor = Vector2.new(0.5, 1),
		radius = 18,
		name = "Card",
	})
	local constraint = Instance.new("UISizeConstraint")
	constraint.MaxSize = Vector2.new(860, 168)
	constraint.MinSize = Vector2.new(420, 150)
	constraint.Parent = card

	local nameTab = Kit.panel({
		style = "ink",
		parent = card,
		size = UDim2.fromOffset(190, 34),
		position = UDim2.fromOffset(20, -18),
		radius = 14,
		name = "Speaker",
	})
	local nameLabel = Kit.text({
		parent = nameTab,
		text = "",
		font = "heavy",
		textSize = Theme.TextSize.body,
		color = Color.textLight,
		align = Enum.TextXAlignment.Center,
		size = UDim2.fromScale(1, 1),
		truncate = true,
	})
	local body = Kit.text({
		parent = card,
		text = "",
		font = "body",
		textSize = Theme.TextSize.label,
		color = Color.textDark,
		size = UDim2.new(1, -40, 1, -64),
		position = UDim2.fromOffset(20, 22),
		wrap = true,
		valign = Enum.TextYAlignment.Top,
		name = "Text",
	})
	local prompt = Kit.icon({
		parent = card,
		name = "arrow",
		size = UDim2.fromOffset(22, 22),
		position = UDim2.new(1, -20, 1, -50),
		anchor = Vector2.new(1, 1),
		color = Color.brassDark,
		tint = true,
		glyphSize = 18,
	})
	local buttons = Kit.frame({
		parent = card,
		size = UDim2.new(1, -40, 0, 34),
		position = UDim2.new(0, 20, 1, -42),
		name = "Buttons",
	})
	Kit.list(
		buttons,
		Enum.FillDirection.Horizontal,
		8,
		Enum.HorizontalAlignment.Right,
		Enum.VerticalAlignment.Center
	)
	local autoOn = false
	local autoButton: TextButton
	local choiceHost = Kit.frame({
		parent = root,
		size = UDim2.fromOffset(360, 0),
		position = UDim2.new(0.5, 0, 1, -196),
		anchor = Vector2.new(0.5, 1),
		name = "Choices",
	})
	choiceHost.AutomaticSize = Enum.AutomaticSize.Y
	Kit.list(
		choiceHost,
		Enum.FillDirection.Vertical,
		8,
		Enum.HorizontalAlignment.Center,
		Enum.VerticalAlignment.Bottom
	)

	local script: { Line } = {}
	local index = 0
	local typing = false
	local typedAt = 0
	local current: Line? = nil
	local onDone: (() -> ())? = nil
	local token = 0
	local advance: () -> ()

	local function finish()
		token += 1
		root.Visible = false
		local done = onDone
		onDone = nil
		if done then
			done()
		end
	end

	local function clearChoices()
		for _, child in choiceHost:GetChildren() do
			if child:IsA("GuiObject") then
				child:Destroy()
			end
		end
	end

	local function showLine(i: number)
		local line = script[i]
		if not line then
			finish()
			return
		end
		index = i
		current = line
		token += 1
		local mine = token
		clearChoices()
		nameTab.Visible = line.speaker ~= nil and line.speaker ~= ""
		nameLabel.Text = line.speaker or ""
		body.Text = line.text
		body.MaxVisibleGraphemes = 0
		prompt.Visible = false
		typing = true
		typedAt = os.clock()
		task.spawn(function()
			local total = utf8.len(line.text) or #line.text
			while typing and token == mine do
				local shown = math.floor((os.clock() - typedAt) * CHARS_PER_SECOND)
				if shown >= total then
					break
				end
				body.MaxVisibleGraphemes = shown
				task.wait()
			end
			if token ~= mine then
				return
			end
			typing = false
			body.MaxVisibleGraphemes = -1
			if line.choices and #line.choices > 0 then
				prompt.Visible = false
				for order, choice in line.choices do
					Kit.button({
						parent = choiceHost,
						text = choice.text,
						style = "primary",
						size = UDim2.fromOffset(360, 40),
						order = order,
						onClick = function()
							clearChoices()
							showLine(choice.next or (i + 1))
						end,
					})
				end
			else
				prompt.Visible = true
				if autoOn then
					task.delay(AUTO_DELAY, function()
						if token == mine and autoOn then
							advance()
						end
					end)
				end
			end
		end)
	end

	advance = function()
		local line = current
		if not line then
			return
		end
		if typing then
			typing = false
			body.MaxVisibleGraphemes = -1
			return
		end
		if line.choices and #line.choices > 0 then
			return
		end
		showLine(index + 1)
	end

	Kit.button({
		parent = buttons,
		text = Content.text("dialogue.skip"),
		style = "paper",
		size = UDim2.fromOffset(84, 32),
		textSize = Theme.TextSize.small,
		order = 2,
		onClick = function()
			finish()
		end,
	})
	autoButton = Kit.button({
		parent = buttons,
		text = Content.text("dialogue.auto"),
		style = "paper",
		size = UDim2.fromOffset(84, 32),
		textSize = Theme.TextSize.small,
		order = 1,
		onClick = function()
			autoOn = not autoOn
			autoButton.BackgroundColor3 = if autoOn then Color.brass else Color.paper
			if autoOn and not typing then
				advance()
			end
		end,
	})
	local tap = Instance.new("TextButton")
	tap.Name = "Tap"
	tap.BackgroundTransparency = 1
	tap.Text = ""
	tap.Size = UDim2.new(1, 0, 1, -44)
	tap.Parent = card
	tap.Activated:Connect(advance)

	return {
		root = root,
		play = function(lines: { Line }, done: (() -> ())?)
			script = lines
			onDone = done
			root.Visible = true
			showLine(1)
		end,
		stop = finish,
		isOpen = function(): boolean
			return root.Visible
		end,
	}
end

return DialogueBox
