--!strict
local TestKit = require("./TestKit")
local TouchLayout = require("../src/client/TouchLayout")

type Spot = TouchLayout.Spot

-- Roblox's jump button: 70 px on screens up to 500 px tall, 120 px on bigger ones.
local PHONE_JUMP = TouchLayout.PhoneJump
local TABLET_JUMP: Spot = { x = -110, y = -150, size = 120 }

local function clear(a: Spot, b: Spot): boolean
	local distance = math.sqrt((a.x - b.x) ^ 2 + (a.y - b.y) ^ 2)
	return distance >= (a.size + b.size) / 2
end

local function checkNoOverlaps(jump: Spot)
	local spots = TouchLayout.around(jump)
	local names = {}
	for name in spots do
		table.insert(names, name)
	end
	table.sort(names)
	for index, name in names do
		TestKit.truthy(clear(spots[name], jump), `{name} overlaps the jump button`)
		for otherIndex = index + 1, #names do
			local other = names[otherIndex]
			TestKit.truthy(clear(spots[name], spots[other]), `{name} overlaps {other}`)
		end
	end
end

return {
	["phone buttons sit where they were tuned"] = function()
		local spots = TouchLayout.around(PHONE_JUMP)
		TestKit.equal(spots.Attack.x, -150)
		TestKit.equal(spots.Attack.y, -75)
		TestKit.equal(spots.Attack.size, 80)
		TestKit.equal(spots.Technique.x, -235)
		TestKit.equal(spots.Finale.y, -135)
	end,

	["no button overlaps another or the jump button on a phone"] = function()
		checkNoOverlaps(PHONE_JUMP)
	end,

	["no button overlaps another or the jump button on a tablet"] = function()
		checkNoOverlaps(TABLET_JUMP)
	end,

	["buttons stay on screen and clear of the thumbstick"] = function()
		-- The thumbstick takes the left 40% of the screen. The smallest landscape phone is 667 x 375.
		local cases = {
			{ jump = PHONE_JUMP, width = 667, height = 375 },
			{ jump = TABLET_JUMP, width = 1024, height = 768 },
		}
		for _, case in cases do
			for name, spot in TouchLayout.around(case.jump) do
				local half = spot.size / 2
				TestKit.truthy(spot.x - half > -case.width * 0.6, `{name} reaches the thumbstick`)
				TestKit.truthy(spot.y - half > -case.height, `{name} goes off the top`)
				TestKit.truthy(spot.x + half <= 0 and spot.y + half <= 0, `{name} goes off the edge`)
			end
		end
	end,

	["bigger jump buttons grow the layout, up to a limit"] = function()
		local tablet = TouchLayout.around(TABLET_JUMP)
		TestKit.equal(tablet.Attack.size, math.floor(80 * TouchLayout.MaxScale))
		local huge = TouchLayout.around({ x = -150, y = -200, size = 300 })
		TestKit.equal(huge.Attack.size, tablet.Attack.size, "capped")
	end,
}
