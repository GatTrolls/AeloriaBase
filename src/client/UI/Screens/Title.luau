--!strict
--[[
	Title screen

	The first thing a player sees: the game's name over a slow starfield, a pulsing "tap to begin"
	line and a version tag. Everything else (settings, credits) sits as small buttons in the
	corners. Tapping anywhere starts the game: the screen fades out and calls ctx.onStart.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Content = require(ReplicatedStorage.Shared.Content)

local Kit = require(script.Parent.Parent.Kit)
local Theme = require(script.Parent.Parent.Theme)

local Color = Theme.Color

local Title = {}

function Title.build(ctx: any)
	local root = Kit.frame({ size = UDim2.fromScale(1, 1), name = "Title", color = Color.night })
	root.Active = true
	Kit.gradient(root, Color3.fromRGB(40, 58, 110), Color3.fromRGB(8, 10, 24), 90)

	-- Stars: two layers drifting at different speeds.
	local rng = Random.new(11)
	local stars: { { frame: Frame, speed: number } } = {}
	for index = 1, 70 do
		local size = rng:NextInteger(2, 5)
		local frame = Kit.frame({
			parent = root,
			size = UDim2.fromOffset(size, size),
			position = UDim2.fromScale(rng:NextNumber(), rng:NextNumber()),
			color = Color.textLight,
			radius = -1,
			transparency = rng:NextNumber(0.15, 0.75),
			name = `Star{index}`,
		})
		stars[index] = { frame = frame, speed = rng:NextNumber(0.004, 0.02) }
	end

	-- Horizon glow.
	local glow = Kit.frame({
		parent = root,
		size = UDim2.fromScale(1, 0.45),
		position = UDim2.fromScale(0, 1),
		anchor = Vector2.new(0, 1),
		color = Color.sea,
		transparency = 0.82,
		name = "Glow",
	})
	Kit.gradient(glow, Color3.fromRGB(255, 255, 255), Color3.fromRGB(40, 90, 140), 90).Transparency =
		NumberSequence.new({
			NumberSequenceKeypoint.new(0, 1),
			NumberSequenceKeypoint.new(1, 0),
		})

	Kit.text({
		parent = root,
		text = Content.text("title.name"),
		font = "title",
		textSize = 96,
		color = Color.textLight,
		align = Enum.TextXAlignment.Center,
		size = UDim2.new(1, 0, 0, 110),
		position = UDim2.fromScale(0.5, 0.34),
		anchor = Vector2.new(0.5, 0.5),
		stroke = true,
		strokeTransparency = 0.5,
		name = "Name",
	})
	Kit.text({
		parent = root,
		text = Content.text("title.tagline"),
		font = "hand",
		textSize = Theme.TextSize.heading,
		color = Color.brassLight,
		align = Enum.TextXAlignment.Center,
		size = UDim2.new(1, 0, 0, 36),
		position = UDim2.fromScale(0.5, 0.46),
		anchor = Vector2.new(0.5, 0.5),
		name = "Tagline",
	})
	local prompt = Kit.text({
		parent = root,
		text = Content.text("title.tap"),
		font = "bold",
		textSize = Theme.TextSize.label,
		color = Color.textLight,
		align = Enum.TextXAlignment.Center,
		size = UDim2.new(1, 0, 0, 30),
		position = UDim2.fromScale(0.5, 0.78),
		anchor = Vector2.new(0.5, 0.5),
		name = "Prompt",
	})
	Kit.text({
		parent = root,
		text = Content.text("title.version"),
		font = "body",
		textSize = Theme.TextSize.tiny,
		color = Color.textMuted,
		align = Enum.TextXAlignment.Right,
		size = UDim2.fromOffset(200, 18),
		position = UDim2.new(1, -16, 1, -12),
		anchor = Vector2.new(1, 1),
	})
	Kit.iconButton({
		parent = root,
		icon = "settings",
		diameter = 40,
		style = "dark",
		position = UDim2.new(1, -16, 0, 16),
		anchor = Vector2.new(1, 0),
		onClick = function()
			if ctx.ui and ctx.ui.open then
				ctx.ui.open("notebook", { tab = "settings" })
			end
		end,
	})

	local running = false
	local starting = false
	local function animate()
		task.spawn(function()
			local t = 0
			while running do
				local dt = task.wait()
				t += dt
				prompt.TextTransparency = 0.25 + 0.4 * (0.5 + 0.5 * math.sin(t * 2.6))
				for _, star in stars do
					local p = star.frame.Position
					local x = p.X.Scale - star.speed * dt
					if x < -0.01 then
						x += 1.02
					end
					star.frame.Position = UDim2.fromScale(x, p.Y.Scale)
				end
			end
		end)
	end

	local tap = Instance.new("TextButton")
	tap.Name = "Tap"
	tap.BackgroundTransparency = 1
	tap.Text = ""
	tap.Size = UDim2.new(1, -80, 1, 0)
	tap.Parent = root
	tap.Activated:Connect(function()
		if starting then
			return
		end
		starting = true
		Kit.tween(root, Theme.Tween.slow, { BackgroundTransparency = 1 })
		for _, child in root:GetChildren() do
			if child:IsA("GuiObject") and child ~= tap then
				child.Visible = false
			end
		end
		task.delay(0.5, function()
			root.Visible = false
			running = false
			if ctx.onStart then
				ctx.onStart()
			end
		end)
	end)

	return {
		root = root,
		open = function()
			starting = false
			root.Visible = true
			root.BackgroundTransparency = 0
			for _, child in root:GetChildren() do
				if child:IsA("GuiObject") then
					child.Visible = true
				end
			end
			if not running then
				running = true
				animate()
			end
		end,
		close = function()
			running = false
		end,
	}
end

return Title
