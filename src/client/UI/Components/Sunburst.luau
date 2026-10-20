--!strict
--[[
	Sunburst

	Soft rays fanning out from a point, slowly turning, with a round glow in the middle: the light
	behind a banner's featured item. Two sprites from the effects atlas, so it costs almost nothing,
	and it only turns while it is started (the page starts it when shown and stops it when hidden).
]]

local TweenService = game:GetService("TweenService")

local Fx = require(script.Parent.Parent.Fx)
local Kit = require(script.Parent.Parent.Kit)

local Sunburst = {}

export type Burst = {
	frame: Frame,
	start: () -> (),
	stop: () -> (),
}

-- `radius` is how far the rays reach, in pixels.
function Sunburst.new(parent: Instance, color: Color3, radius: number, _rays: number?): Burst
	local holder = Kit.frame({
		parent = parent,
		size = UDim2.fromOffset(radius * 2, radius * 2),
		position = UDim2.fromScale(0.5, 0.5),
		anchor = Vector2.new(0.5, 0.5),
		name = "Sunburst",
		z = 1,
	})
	local rays = Fx.image("rays", {
		parent = holder,
		size = UDim2.fromScale(1, 1),
		position = UDim2.fromScale(0.5, 0.5),
		color = color,
		transparency = 0.45,
		z = 1,
	})
	Fx.image("glow", {
		parent = holder,
		size = UDim2.fromScale(0.62, 0.62),
		position = UDim2.fromScale(0.5, 0.5),
		color = color,
		transparency = 0.35,
		z = 2,
	})

	local tween: Tween? = nil
	return {
		frame = holder,
		start = function()
			if tween then
				return
			end
			local running = TweenService:Create(
				rays,
				TweenInfo.new(120, Enum.EasingStyle.Linear, Enum.EasingDirection.In, -1),
				{ Rotation = 360 }
			)
			tween = running
			running:Play()
		end,
		stop = function()
			if tween then
				tween:Cancel()
				tween = nil
			end
		end,
	}
end

return Sunburst
