--!strict
--[[
	TouchLayout

	Where the touch buttons go. Roblox draws its own jump button in the bottom-right corner
	(70 px on phones, 120 px on tablets), so the HUD's buttons are placed around it: attack to its
	left, dodge above it, then Technique, Finale and lock-on further out, all clear of the
	thumbstick on the left of the screen.

	Spots are centres measured from the bottom-right corner of the screen, so x and y are
	negative. Pure maths with no Roblox APIs; covered by tests/TouchLayout.spec.luau.
]]

export type Spot = { x: number, y: number, size: number }

local TouchLayout = {}

-- Roblox's jump button on a phone.
TouchLayout.PhoneJump = { x = -60, y = -55, size = 70 } :: Spot

-- Bigger jump buttons spread and grow the layout, up to this much.
TouchLayout.MaxScale = 1.4

-- Each button's centre relative to the jump button's centre, and its size, on a phone.
TouchLayout.Buttons = {
	Attack = { x = -90, y = -20, size = 80 },
	Dodge = { x = 0, y = -85, size = 52 },
	Technique = { x = -175, y = 0, size = 56 },
	Finale = { x = -155, y = -80, size = 64 },
	LockOn = { x = -230, y = -75, size = 40 },
} :: { [string]: Spot }

-- Returns each button's spot around a jump button at the given spot.
function TouchLayout.around(jump: Spot): { [string]: Spot }
	local scale = math.clamp(jump.size / TouchLayout.PhoneJump.size, 1, TouchLayout.MaxScale)
	local spots: { [string]: Spot } = {}
	for name, button in TouchLayout.Buttons do
		spots[name] = {
			x = jump.x + button.x * scale,
			y = jump.y + button.y * scale,
			size = math.floor(button.size * scale),
		}
	end
	return spots
end

return TouchLayout
