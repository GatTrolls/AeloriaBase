--!strict
--[[
	Ease

	Easing curves for animation keys. Each maps progress 0..1 to a blend 0..1; the overshooting
	curves ("back", "spring") briefly go past 1 on purpose, for the snap and settle anime
	combat leans on.

	  linear   constant speed
	  in       starts slow, ends fast (anticipation, winding up)
	  out      starts fast, ends slow (a strike landing)
	  inout    slow at both ends (idles, breathing)
	  snap     very fast start, long settle: the signature "hit and hold" of a heavy blow
	  back     overshoots the target a little, then returns
	  spring   overshoots and wobbles once, for cloth and tails
	  hold     stays on the previous pose until the next key arrives

	Pure Luau with no Roblox APIs; covered by tests/Anim.spec.luau.
]]

local Ease = {}

local BACK = 1.70158
local TAU = math.pi * 2

local curves: { [string]: (number) -> number } = {
	linear = function(t)
		return t
	end,
	["in"] = function(t)
		return t * t
	end,
	out = function(t)
		local u = 1 - t
		return 1 - u * u
	end,
	inout = function(t)
		return if t < 0.5 then 2 * t * t else 1 - (-2 * t + 2) ^ 2 / 2
	end,
	snap = function(t)
		local u = 1 - t
		return 1 - u * u * u * u
	end,
	back = function(t)
		local u = t - 1
		return 1 + (BACK + 1) * u * u * u + BACK * u * u
	end,
	spring = function(t)
		if t <= 0 then
			return 0
		elseif t >= 1 then
			return 1
		end
		return 2 ^ (-9 * t) * math.sin((t * 10 - 0.75) * (TAU / 3)) + 1
	end,
	hold = function(t)
		return if t >= 1 then 1 else 0
	end,
}

-- Applies the named curve; unknown or missing names are linear.
function Ease.apply(name: string?, t: number): number
	local progress = math.clamp(t, 0, 1)
	local curve = name and curves[name]
	if curve then
		return curve(progress)
	end
	return progress
end

function Ease.has(name: string): boolean
	return curves[name] ~= nil
end

return Ease
