--!strict
--[[
	Icons

	Every icon comes from one atlas image: an 8 x 8 grid of 128 px cells drawn in the notebook's
	sticker style (thick ink outline, flat colour, one highlight). One upload, one draw call
	family, and icons recolour with ImageColor3 when needed.

	Until the atlas asset id is set (Icons.atlas.image) or when an icon is unknown, apply() leaves
	the label alone and glyph() gives a text fallback, so screens work in a fresh checkout.

	Slots are fixed: never reorder, only append, or old atlases stop matching.
]]

local Icons = {}

Icons.atlas = {
	-- The uploaded atlas. Empty would mean "no atlas yet" and screens fall back to text glyphs.
	image = "rbxassetid://73945479259818",
	cell = 128,
	columns = 8,
	size = 1024,
}

-- Cell index (0-based, row by row) of each icon in the atlas.
local NAMES = {
	-- row 0: currencies
	"glint",
	"starglass",
	"pureStarglass",
	"goldStar",
	"silverStar",
	"moonflakes",
	"guildSeals",
	"dew",
	-- row 1: navigation
	"story",
	"party",
	"bag",
	"starfall",
	"map",
	"settings",
	"close",
	"back",
	-- row 2: elements
	"Flame",
	"Tide",
	"Terra",
	"Gale",
	"Frost",
	"Volt",
	"Astral",
	"Physical",
	-- row 3: weapons
	"sword",
	"greatsword",
	"lance",
	"bow",
	"focus",
	"dagger",
	"hammer",
	"anchor",
	-- row 4: stats
	"hp",
	"atk",
	"def",
	"critRate",
	"critDamage",
	"energy",
	"synergy",
	"heal",
	-- row 5: interface
	"star",
	"starEmpty",
	"lock",
	"check",
	"plus",
	"minus",
	"arrow",
	"info",
	-- row 6: world
	"questMark",
	"questDone",
	"waystone",
	"starwell",
	"chest",
	"compass",
	"pin",
	"camp",
	-- row 7: misc and Trinket slots
	"exclamation",
	"notebook",
	"pocket",
	"kite",
	"sparkle",
	"badge",
	"bracelet",
	"ring",
}

-- Icons drawn in their own colours (currencies, elements, a few status marks). Every other icon is
-- near-white so screens can tint it with the colour they want.
local COLORED: { [string]: boolean } = {}
for _, name in
	{
		"glint",
		"starglass",
		"pureStarglass",
		"goldStar",
		"silverStar",
		"moonflakes",
		"guildSeals",
		"dew",
		"Flame",
		"Tide",
		"Terra",
		"Gale",
		"Frost",
		"Volt",
		"Astral",
		"Physical",
		"hp",
		"critDamage",
		"energy",
		"heal",
		"questMark",
		"questDone",
		"chest",
		"exclamation",
		"sparkle",
	}
do
	COLORED[name] = true
end

local index: { [string]: number } = {}
for position, name in NAMES do
	index[name] = position - 1
end

-- Text fallbacks that exist in the default fonts.
local GLYPHS: { [string]: string } = {
	glint = "●",
	starglass = "◆",
	pureStarglass = "◆",
	goldStar = "★",
	silverStar = "★",
	moonflakes = "●",
	guildSeals = "◆",
	dew = "●",
	story = "♪",
	party = "♥",
	bag = "⌂",
	starfall = "★",
	map = "▲",
	settings = "⚙",
	close = "×",
	back = "◀",
	star = "★",
	starEmpty = "☆",
	check = "✓",
	plus = "+",
	minus = "-",
	arrow = "▶",
	info = "i",
	lock = "■",
	exclamation = "!",
	questMark = "?",
	questDone = "✓",
	heal = "♥",
	hp = "♥",
	atk = "◆",
	def = "●",
	energy = "▲",
}

function Icons.isColored(name: string): boolean
	return COLORED[name] == true
end

function Icons.has(name: string): boolean
	return Icons.atlas.image ~= "" and index[name] ~= nil
end

-- Points an ImageLabel at an icon. Returns false (and leaves the label unchanged) when there is
-- no atlas or no such icon.
function Icons.apply(label: ImageLabel, name: string): boolean
	local cell = index[name]
	if Icons.atlas.image == "" or cell == nil then
		return false
	end
	local atlas = Icons.atlas
	label.Image = atlas.image
	label.ImageRectSize = Vector2.new(atlas.cell, atlas.cell)
	label.ImageRectOffset =
		Vector2.new((cell % atlas.columns) * atlas.cell, math.floor(cell / atlas.columns) * atlas.cell)
	return true
end

function Icons.glyph(name: string): string
	return GLYPHS[name] or "●"
end

return Icons
