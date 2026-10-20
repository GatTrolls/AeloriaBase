--!strict
--[[
	Gacha

	Pure banner and pity logic. No Roblox APIs are used here, so the same module runs in
	Studio and in the Lune test suite (tests/Gacha.spec.luau).

	The server owns every roll. Clients only ever see results and the published odds.
]]

export type Rarity = number -- 3, 4 or 5 stars

export type Banner = {
	id: string,
	displayName: string,
	-- Base chance for each rarity before pity, as a fraction (0.006 = 0.6%).
	baseRate5: number,
	baseRate4: number,
	-- Pull number (1-based, counted since the last hit) where the rate starts climbing.
	softPity5: number,
	-- Added to the 5-star rate for every pull past softPity5.
	softPityStep5: number,
	-- Pull number that always gives that rarity.
	hardPity5: number,
	hardPity4: number,
	-- Chance that a 5-star is the featured one. Losing guarantees the next.
	featuredChance5: number,
	featured5: { string },
	featured4: { string },
	pool5: { string },
	pool4: { string },
	pool3: { string },
}

export type PityState = {
	sinceLast5: number,
	sinceLast4: number,
	guaranteedFeatured5: boolean,
}

export type PullResult = {
	itemId: string,
	rarity: Rarity,
	featured: boolean,
	pullNumber: number, -- which pull since the previous hit of this rarity, for logs
}

-- A function returning a number in [0, 1). Random.new():NextNumber() in Roblox,
-- or a seeded generator in tests.
export type Rng = () -> number

local Gacha = {}

function Gacha.newPityState(): PityState
	return {
		sinceLast5 = 0,
		sinceLast4 = 0,
		guaranteedFeatured5 = false,
	}
end

-- The 5-star chance for the next pull, given how many pulls have passed since the last one.
function Gacha.rate5ForPull(banner: Banner, pullNumber: number): number
	if pullNumber >= banner.hardPity5 then
		return 1
	end
	local rate = banner.baseRate5
	if pullNumber >= banner.softPity5 then
		rate += banner.softPityStep5 * (pullNumber - banner.softPity5 + 1)
	end
	return math.min(rate, 1)
end

local function pick(list: { string }, rng: Rng): string
	assert(#list > 0, "Gacha: tried to pick from an empty pool")
	local index = math.floor(rng() * #list) + 1
	return list[math.min(index, #list)]
end

-- Rolls one pull. Returns the result and a new pity state; the input state is not changed.
function Gacha.pull(banner: Banner, state: PityState, rng: Rng): (PullResult, PityState)
	local pull5 = state.sinceLast5 + 1
	local pull4 = state.sinceLast4 + 1
	local roll = rng()

	local nextState: PityState = {
		sinceLast5 = pull5,
		sinceLast4 = pull4,
		guaranteedFeatured5 = state.guaranteedFeatured5,
	}

	if roll < Gacha.rate5ForPull(banner, pull5) then
		local hasFeatured = #banner.featured5 > 0
		local featured = hasFeatured and (state.guaranteedFeatured5 or rng() < banner.featuredChance5)
		local itemId = if featured then pick(banner.featured5, rng) else pick(banner.pool5, rng)
		nextState.sinceLast5 = 0
		nextState.guaranteedFeatured5 = hasFeatured and not featured
		return { itemId = itemId, rarity = 5, featured = featured, pullNumber = pull5 }, nextState
	end

	if pull4 >= banner.hardPity4 or roll < Gacha.rate5ForPull(banner, pull5) + banner.baseRate4 then
		-- Featured 4-stars take half of all 4-star results when the banner has any.
		local featured = #banner.featured4 > 0 and (#banner.pool4 == 0 or rng() < 0.5)
		local itemId = if featured then pick(banner.featured4, rng) else pick(banner.pool4, rng)
		nextState.sinceLast4 = 0
		return { itemId = itemId, rarity = 4, featured = featured, pullNumber = pull4 }, nextState
	end

	return { itemId = pick(banner.pool3, rng), rarity = 3, featured = false, pullNumber = pull4 }, nextState
end

-- Rolls `count` pulls in order, carrying pity between them.
function Gacha.pullMany(
	banner: Banner,
	state: PityState,
	count: number,
	rng: Rng
): ({ PullResult }, PityState)
	local results = table.create(count)
	local current = state
	for _ = 1, count do
		local result
		result, current = Gacha.pull(banner, current, rng)
		table.insert(results, result)
	end
	return results, current
end

-- The odds players must be shown before they spend anything. Roblox requires paid random
-- items to show their odds, so the shop UI should render this table, not hard-coded text.
function Gacha.publishedOdds(banner: Banner): { [string]: number }
	return {
		fiveStarBase = banner.baseRate5,
		fourStarBase = banner.baseRate4,
		threeStarBase = 1 - banner.baseRate5 - banner.baseRate4,
		fiveStarHardPity = banner.hardPity5,
		fourStarHardPity = banner.hardPity4,
		featuredFiveStarChance = banner.featuredChance5,
	}
end

function Gacha.validateBanner(banner: Banner): (boolean, string?)
	if banner.baseRate5 <= 0 or banner.baseRate4 <= 0 or banner.baseRate5 + banner.baseRate4 >= 1 then
		return false, "base rates must be positive and add up to less than 1"
	end
	if banner.softPity5 >= banner.hardPity5 then
		return false, "soft pity must start before hard pity"
	end
	if #banner.pool5 == 0 and #banner.featured5 == 0 then
		return false, "banner has no 5-star items"
	end
	if #banner.pool4 == 0 and #banner.featured4 == 0 then
		return false, "banner has no 4-star items"
	end
	if #banner.pool3 == 0 then
		return false, "banner has no 3-star items"
	end
	return true, nil
end

return Gacha
