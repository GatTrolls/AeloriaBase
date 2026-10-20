--!strict
--[[
	Theme

	The look of every screen. The motif is the traveller's kit: notebook paper, ink lines, a brass
	compass and a night sky full of stars. Screens never hard-code a colour, font or size; they ask
	for it here, so the whole interface can be retuned in one file.

	Designed on a 600 px tall canvas; UIController scales it to the real screen.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ElementStyle = require(ReplicatedStorage.Shared.Config.ElementStyle)

local NUNITO = "rbxasset://fonts/families/Nunito.json"

local Theme = {}

-- The canvas height every layout is designed against.
Theme.BaseHeight = 600
Theme.MinScale = 0.72
Theme.MaxScale = 1.75

Theme.Color = {
	-- Night sky behind everything.
	night = Color3.fromRGB(14, 19, 38),
	nightSoft = Color3.fromRGB(24, 33, 62),
	-- Dark panels.
	ink = Color3.fromRGB(27, 34, 58),
	inkSoft = Color3.fromRGB(42, 53, 88),
	inkLine = Color3.fromRGB(78, 94, 140),
	-- Notebook pages (dark glass, like the reference menus).
	paper = Color3.fromRGB(22, 30, 56),
	paperShade = Color3.fromRGB(34, 46, 84),
	paperLine = Color3.fromRGB(86, 104, 154),
	-- Brass: buttons and trim.
	brass = Color3.fromRGB(205, 158, 78),
	brassLight = Color3.fromRGB(240, 205, 128),
	brassDark = Color3.fromRGB(139, 101, 46),
	star = Color3.fromRGB(255, 214, 108),
	-- Accents.
	sea = Color3.fromRGB(64, 184, 200),
	lemon = Color3.fromRGB(244, 211, 94),
	coral = Color3.fromRGB(232, 112, 90),
	leaf = Color3.fromRGB(126, 200, 120),
	violet = Color3.fromRGB(178, 124, 232),
	-- State.
	danger = Color3.fromRGB(230, 84, 80),
	success = Color3.fromRGB(110, 214, 138),
	-- Text.
	textLight = Color3.fromRGB(247, 241, 228),
	textMuted = Color3.fromRGB(168, 178, 206),
	textDark = Color3.fromRGB(236, 241, 252),
	textFaint = Color3.fromRGB(150, 165, 202),
	black = Color3.fromRGB(10, 12, 22),
}

Theme.Font = {
	title = Font.fromEnum(Enum.Font.FredokaOne),
	body = Font.new(NUNITO, Enum.FontWeight.SemiBold),
	bold = Font.new(NUNITO, Enum.FontWeight.Bold),
	heavy = Font.new(NUNITO, Enum.FontWeight.ExtraBold),
	-- Pocket's handwriting.
	hand = Font.fromEnum(Enum.Font.PatrickHand),
}

Theme.TextSize = {
	tiny = 13,
	small = 15,
	body = 18,
	label = 20,
	heading = 26,
	title = 34,
	hero = 54,
}

Theme.Radius = {
	small = 8,
	medium = 14,
	large = 22,
}

Theme.Tween = {
	fast = TweenInfo.new(0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
	normal = TweenInfo.new(0.22, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
	pop = TweenInfo.new(0.32, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
	slow = TweenInfo.new(0.6, Enum.EasingStyle.Quint, Enum.EasingDirection.Out),
}

local RARITY = {
	[1] = Color3.fromRGB(170, 176, 186),
	[2] = Color3.fromRGB(126, 200, 140),
	[3] = Color3.fromRGB(116, 170, 232),
	[4] = Color3.fromRGB(184, 124, 240),
	[5] = Color3.fromRGB(255, 200, 80),
}

function Theme.rarity(stars: number): Color3
	return RARITY[math.clamp(stars, 1, 5)]
end

-- The colour of an element ("Flame", "Tide", ...), falling back to a neutral white.
function Theme.element(name: string?): Color3
	local values = name and ElementStyle.Elements[name]
	if values then
		return Color3.fromRGB(values[1], values[2], values[3])
	end
	return Theme.Color.textLight
end

-- Colour-blind friendly alternates for rarity, picked by the setting of the same name. The
-- shapes (star counts) always carry the meaning too, so colour is never the only cue.
local RARITY_SAFE = {
	[3] = Color3.fromRGB(86, 180, 233),
	[4] = Color3.fromRGB(204, 121, 167),
	[5] = Color3.fromRGB(240, 228, 66),
}

function Theme.rarityFor(stars: number, colorblind: string?): Color3
	if colorblind and colorblind ~= "off" and RARITY_SAFE[stars] then
		return RARITY_SAFE[stars]
	end
	return Theme.rarity(stars)
end

-- Formats a count with thousands separators: 1250000 -> "1,250,000".
function Theme.count(value: number): string
	local text = tostring(math.floor(value))
	local reversed = string.gsub(string.reverse(text), "(%d%d%d)", "%1,")
	local formatted = string.reverse(reversed)
	return (string.gsub(formatted, "^,", ""))
end

return Theme
