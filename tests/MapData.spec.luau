--!strict
local MapData = require("../src/shared/Config/MapData")
local TestKit = require("./TestKit")

return {
	["only always-points show before anything is found"] = function()
		local region = MapData.get("coast") :: any
		local points = MapData.visible(region, nil)
		TestKit.equal(#points, 1)
		TestKit.equal(points[1].kind, "camp")
	end,

	["found points join the map"] = function()
		local region = MapData.get("coast") :: any
		local points = MapData.visible(region, { found = { coast_waystone = true } })
		TestKit.equal(#points, 2)
	end,

	["projection maps the corners to 0 and 1 and clamps"] = function()
		local region = MapData.get("coast") :: any
		local u, v = MapData.project(region, region.minX, region.minZ)
		TestKit.equal(u, 0)
		TestKit.equal(v, 0)
		u, v = MapData.project(region, region.maxX + 500, region.maxZ + 500)
		TestKit.equal(u, 1)
		TestKit.equal(v, 1)
	end,
}
