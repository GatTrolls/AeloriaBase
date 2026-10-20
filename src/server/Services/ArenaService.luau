--!strict
--[[
	ArenaService

	Builds the grey-box combat arena when the place does not already have one, so a fresh place
	is playable straight from the repository. A level designer can replace Workspace.Arena with a
	hand-built version; this service leaves an existing arena alone.

	Layout: open floor, low boundary walls, cover pillars, a cliff to climb with a ramp beside it
	for gliding practice, a spawn pad and enemy spawn markers tagged "EnemySpawn". A marker's
	"Enemy" attribute picks what spawns there (grunts by default); one elite waits by the cliff.
]]

local CollectionService = game:GetService("CollectionService")
local Workspace = game:GetService("Workspace")

local ArenaService = {}

local FLOOR_SIZE = 220
local WALL_HEIGHT = 5

local function part(
	parent: Instance,
	name: string,
	size: Vector3,
	cframe: CFrame,
	props: { [string]: any }?
): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Anchored = true
	p.Size = size
	p.CFrame = cframe
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Material = Enum.Material.SmoothPlastic
	for key, value in props or {} do
		(p :: any)[key] = value
	end
	p.Parent = parent
	return p
end

local function build(): Folder
	local arena = Instance.new("Folder")
	arena.Name = "Arena"

	local grass = Color3.fromRGB(104, 150, 88)
	local stone = Color3.fromRGB(150, 146, 138)
	local rock = Color3.fromRGB(118, 108, 100)

	part(arena, "Floor", Vector3.new(FLOOR_SIZE, 2, FLOOR_SIZE), CFrame.new(0, -0.5, 0), {
		Material = Enum.Material.Grass,
		Color = grass,
	})

	local half = FLOOR_SIZE / 2
	for index, offset in
		{
			Vector3.new(half, 0, 0),
			Vector3.new(-half, 0, 0),
			Vector3.new(0, 0, half),
			Vector3.new(0, 0, -half),
		}
	do
		local alongX = offset.X == 0
		local size = if alongX
			then Vector3.new(FLOOR_SIZE, WALL_HEIGHT, 3)
			else Vector3.new(3, WALL_HEIGHT, FLOOR_SIZE)
		part(arena, `Wall{index}`, size, CFrame.new(offset + Vector3.new(0, WALL_HEIGHT / 2, 0)), {
			Material = Enum.Material.Slate,
			Color = stone,
		})
	end

	-- Cover pillars around the fighting area.
	for index = 1, 6 do
		local angle = math.rad(index * 60 + 30)
		local position = Vector3.new(math.cos(angle) * 42, 7, math.sin(angle) * 42)
		part(arena, `Pillar{index}`, Vector3.new(5, 14, 5), CFrame.new(position), {
			Material = Enum.Material.Slate,
			Color = stone,
		})
	end

	-- The cliff: tall enough that climbing it costs real stamina, flat on top to glide off.
	part(arena, "Cliff", Vector3.new(44, 46, 26), CFrame.new(0, 23, 88), {
		Material = Enum.Material.Rock,
		Color = rock,
	})
	-- A ramp beside the cliff for players who are not climbing. It rises towards +Z and meets
	-- the cliff's top at its front-left corner.
	local rampLength = 70
	local rampAngle = math.atan2(46, rampLength)
	local rampHypotenuse = math.sqrt(46 ^ 2 + rampLength ^ 2)
	part(
		arena,
		"Ramp",
		Vector3.new(10, 2, rampHypotenuse),
		CFrame.new(-27, 23, 75 - rampLength / 2) * CFrame.Angles(-rampAngle, 0, 0),
		{ Material = Enum.Material.Slate, Color = stone }
	)

	local spawn = Instance.new("SpawnLocation")
	spawn.Name = "Spawn"
	spawn.Anchored = true
	spawn.Size = Vector3.new(10, 1, 10)
	-- Faces +Z, so players spawn looking into the arena.
	spawn.CFrame = CFrame.new(0, 0.6, -70) * CFrame.Angles(0, math.pi, 0)
	spawn.Neutral = true
	spawn.Duration = 0
	spawn.Material = Enum.Material.SmoothPlastic
	spawn.Color = Color3.fromRGB(235, 225, 200)
	spawn.Parent = arena

	local spawns = Instance.new("Folder")
	spawns.Name = "EnemySpawns"
	spawns.Parent = arena
	for index = 1, 5 do
		local angle = math.rad(index * 72)
		local marker = part(
			spawns,
			`EnemySpawn{index}`,
			Vector3.new(2, 1, 2),
			CFrame.new(math.cos(angle) * 22, 0.6, 10 + math.sin(angle) * 22),
			{
				Transparency = 1,
				CanCollide = false,
				CanQuery = false,
				CanTouch = false,
			}
		)
		CollectionService:AddTag(marker, "EnemySpawn")
	end
	-- One elite waits further back, in front of the cliff.
	local eliteMarker = part(spawns, "EliteSpawn", Vector3.new(2, 1, 2), CFrame.new(0, 0.6, 52), {
		Transparency = 1,
		CanCollide = false,
		CanQuery = false,
		CanTouch = false,
	})
	eliteMarker:SetAttribute("Enemy", "elite_brute")
	CollectionService:AddTag(eliteMarker, "EnemySpawn")

	arena.Parent = Workspace
	return arena
end

function ArenaService.getArena(): Instance
	return Workspace:FindFirstChild("Arena") or build()
end

function ArenaService:Init()
	ArenaService.getArena()
end

return ArenaService
