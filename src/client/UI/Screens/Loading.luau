--!strict
--[[
	Loading screen

	Shown while the game readies itself (joining, teleporting): the game's name, a bar that fills
	toward `setProgress`, and a tip that changes every few seconds. Pure presentation; whoever
	shows it decides when it is done.

	  local loading = Loading.build(parentGui)
	  loading.show()  loading.setProgress(0..1)  loading.hide()
]]

local Content = require(game:GetService("ReplicatedStorage").Shared.Content)

local Kit = require(script.Parent.Parent.Kit)
local Theme = require(script.Parent.Parent.Theme)

local Color = Theme.Color

local Loading = {}

local TIP_COUNT = 6
local TIP_SECONDS = 4

function Loading.build(parent: Instance)
	local root = Kit.frame({
		parent = parent,
		size = UDim2.fromScale(1, 1),
		name = "Loading",
		color = Color.night,
		z = 90,
	})
	root.Active = true
	root.Visible = false
	Kit.gradient(root, Color3.fromRGB(26, 36, 70), Color3.fromRGB(6, 8, 20), 90)

	Kit.text({
		parent = root,
		text = Content.text("title.name"),
		font = "title",
		textSize = 64,
		color = Color.textLight,
		align = Enum.TextXAlignment.Center,
		size = UDim2.new(1, 0, 0, 80),
		position = UDim2.fromScale(0.5, 0.38),
		anchor = Vector2.new(0.5, 0.5),
	})
	local bar = Kit.bar({
		parent = root,
		size = UDim2.fromOffset(360, 10),
		position = UDim2.fromScale(0.5, 0.62),
		anchor = Vector2.new(0.5, 0.5),
		color = Color.brass,
		trackColor = Color.paperLine,
		trackTransparency = 0,
		outline = Color.paperLine,
	})
	local tip = Kit.text({
		parent = root,
		text = "",
		font = "hand",
		textSize = Theme.TextSize.heading,
		color = Color.brassLight,
		align = Enum.TextXAlignment.Center,
		size = UDim2.new(0.8, 0, 0, 56),
		position = UDim2.fromScale(0.5, 0.74),
		anchor = Vector2.new(0.5, 0.5),
		wrap = true,
	})

	local showing = false
	local function nextTip(index: number)
		local key = `loading.tip{index}`
		local text = Content.text(key)
		tip.Text = if text ~= key then text else ""
	end

	return {
		root = root,
		show = function()
			if showing then
				return
			end
			showing = true
			root.Visible = true
			bar.set(0.05)
			task.spawn(function()
				local index = math.random(1, TIP_COUNT)
				while showing do
					nextTip(index)
					index = index % TIP_COUNT + 1
					task.wait(TIP_SECONDS)
				end
			end)
		end,
		setProgress = function(fraction: number)
			bar.set(math.clamp(fraction, 0, 1), true)
		end,
		hide = function()
			showing = false
			root.Visible = false
		end,
	}
end

return Loading
