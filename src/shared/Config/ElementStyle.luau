--!strict
-- Presentation for elements and reactions: colours, icon shapes and on-screen labels. Kept apart
-- from ElementConfig so the rules engine never depends on how things look. RGB 0-255.
--
-- Every element has a colour and its own shape, so statuses still read in colour-blind modes.
-- Every reaction flashes its name in one big word.

local ElementStyle = {
	Physical = { 240, 240, 240 },

	Elements = {
		Flame = { 240, 115, 85 },
		Tide = { 90, 168, 236 },
		Frost = { 127, 208, 240 },
		Volt = { 167, 132, 238 },
		Gale = { 69, 203, 169 },
		Terra = { 221, 178, 80 },
		Astral = { 228, 182, 82 },
	} :: { [string]: { number } },

	-- One shape per element: a flame, a drop, a snowflake, a zigzag, a swirl, a diamond and a
	-- four-point star.
	Icons = {
		Flame = "🔥",
		Tide = "💧",
		Frost = "❄",
		Volt = "⚡",
		Gale = "🌀",
		Terra = "◆",
		Astral = "✦",
	} :: { [string]: string },

	Reactions = {
		Scald = { label = "SCALD!", color = { 255, 170, 120 } },
		Thaw = { label = "THAW!", color = { 255, 190, 110 } },
		Flashpoint = { label = "FLASHPOINT!", color = { 255, 110, 160 } },
		Conduct = { label = "CONDUCT!", color = { 170, 140, 255 } },
		Lock = { label = "LOCK!", color = { 170, 240, 255 } },
		Brittle = { label = "BRITTLE!", color = { 210, 200, 255 } },
		Sweep = { label = "SWEEP!", color = { 120, 230, 190 } },
		Geode = { label = "GEODE!", color = { 230, 190, 90 } },
		Starburst = { label = "STARBURST!", color = { 255, 225, 130 } },
	} :: { [string]: { label: string, color: { number } } },
}

return ElementStyle
