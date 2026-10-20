--!strict
-- Banner definitions. Item ids are placeholders until the character roster
-- is announced. Rates here are starting values for playtests, not final.

local Gacha = require(script.Parent.Parent.Gacha)

local STANDARD_RATES = {
	baseRate5 = 0.006,
	baseRate4 = 0.051,
	softPity5 = 74,
	softPityStep5 = 0.06,
	hardPity5 = 90,
	hardPity4 = 10,
	featuredChance5 = 0.5,
}

local function banner(fields: { [string]: any }): Gacha.Banner
	local result = table.clone(STANDARD_RATES) :: any
	for key, value in fields do
		result[key] = value
	end
	local ok, problem = Gacha.validateBanner(result)
	assert(ok, `Banner {result.id}: {problem}`)
	return result
end

local Banners: { [string]: Gacha.Banner } = {
	standard = banner({
		id = "standard",
		displayName = "Standard Banner",
		featured5 = {},
		featured4 = {},
		pool5 = { "hero_placeholder_a", "hero_placeholder_b" },
		pool4 = { "hero_placeholder_c", "hero_placeholder_d", "weapon_placeholder_4" },
		pool3 = { "weapon_placeholder_3a", "weapon_placeholder_3b" },
	}),
}

return Banners
