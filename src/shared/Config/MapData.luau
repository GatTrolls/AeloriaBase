--!strict
--[[
	MapData

	What the Map page draws: regions with a world-space rectangle and the points of interest in
	them (Waystones, Starwells, the camp). Positions are studs in the place. A point stays hidden
	until the profile flags say it was found (`flags.found.<id>`), except `always` points, so
	exploring is what fills the map in.
]]

export type Point = {
	id: string,
	kind: "waystone" | "starwell" | "camp" | "landmark",
	x: number,
	z: number,
	always: boolean?,
}

export type Region = {
	id: string,
	-- World rectangle the map shows: min and max corners (x, z).
	minX: number,
	minZ: number,
	maxX: number,
	maxZ: number,
	points: { Point },
}

local MapData = {}

MapData.Regions = table.freeze({
	{
		id = "coast",
		minX = 2700,
		minZ = -400,
		maxX = 3500,
		maxZ = 400,
		points = {
			{ id = "coast_camp", kind = "camp", x = 3000, z = 0, always = true },
			{ id = "coast_waystone", kind = "waystone", x = 3120, z = -120 },
			{ id = "coast_lookout", kind = "landmark", x = 3300, z = 180 },
			{ id = "coast_starwell", kind = "starwell", x = 2900, z = 220 },
		},
	},
} :: { Region })

function MapData.get(id: string): Region?
	for _, region in MapData.Regions do
		if region.id == id then
			return region
		end
	end
	return nil
end

-- Which points the player can see on the map.
function MapData.visible(region: Region, flags: { [string]: any }?): { Point }
	local found = flags and flags.found
	local out = {}
	for _, point in region.points do
		if point.always or (type(found) == "table" and found[point.id] == true) then
			table.insert(out, point)
		end
	end
	return out
end

-- Normalised 0..1 position of a world point inside a region (z grows downward on the map).
function MapData.project(region: Region, x: number, z: number): (number, number)
	local u = (x - region.minX) / (region.maxX - region.minX)
	local v = (z - region.minZ) / (region.maxZ - region.minZ)
	return math.clamp(u, 0, 1), math.clamp(v, 0, 1)
end

return MapData
