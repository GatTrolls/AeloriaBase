--!strict
-- Presentation for elements and reactions: colours and on-screen labels. Kept apart from
-- ElementConfig so the rules engine never depends on how things look. RGB 0-255.

local ElementStyle = {
	Physical = { 235, 235, 235 },

	Elements = {
		Wind = { 120, 230, 190 },
		Earth = { 230, 180, 80 },
		Fire = { 255, 120, 70 },
		Water = { 70, 160, 255 },
		Ice = { 150, 230, 255 },
		Lightning = { 185, 120, 255 },
		Light = { 255, 240, 160 },
	} :: { [string]: { number } },

	Reactions = {
		Steam = { label = "Steam", color = { 200, 220, 255 } },
		Melt = { label = "Melt", color = { 255, 190, 110 } },
		Overload = { label = "Overload", color = { 255, 110, 160 } },
		Conduct = { label = "Conduct", color = { 170, 140, 255 } },
		Freeze = { label = "Freeze", color = { 170, 240, 255 } },
		Brittle = { label = "Brittle", color = { 210, 200, 255 } },
		Sweep = { label = "Sweep", color = { 120, 230, 190 } },
		Shield = { label = "Shield", color = { 230, 180, 80 } },
		Radiance = { label = "Radiance", color = { 255, 240, 160 } },
	} :: { [string]: { label: string, color: { number } } },
}

return ElementStyle
