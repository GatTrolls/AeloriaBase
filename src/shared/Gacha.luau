--!strict
--[[
	Gacha

	Pure banner and pity logic. No Roblox APIs are used here, so the same module runs in
	Studio and in the Lune test suite (tests/Gacha.spec.luau).

	The server owns every roll. Clients only ever see results and the published odds, and use this
	module to show the player's own pity (the chance on the next pull, the guarantee, Star Pick).

	What a banner can do (the design plan's Starfall rules):
	  * a rising 5-star chance after soft pity and a guaranteed one at hard pity;
	  * a guaranteed 4-star every few pulls;
	  * a 50/50 on the featured item, with the next 5-star guaranteed featured after a loss;
	  * Star Pick: after enough pulls without the featured 5-star, choose it instead (or, on the
	    Everlit banner, choose any standard 5-star character once);
	  * pity shared across banners with the same pityGroup (every Featured banner, say);
	  * a new-player guarantee: the first 5-star arrives by pull 50, and it is a character;
	  * target picking (the Armoury banner): the player names one featured weapon and it gets
	    its own chance, with a guarantee after a miss.
]]

export type Rarity = number -- 3, 4 or 5 stars

export type Banner = {
	id: string,
	displayName: string,
	-- A shorter name for narrow screens.
	tabName: string?,
	-- "featured" | "armoury" | "everlit" | "firstLight": how the screen treats it.
	kind: string?,
	-- Which token a pull costs: "goldStar" or "silverStar".
	currency: string?,
	-- Banners with the same group share pity, the 50/50 guarantee and Star Pick progress.
	pityGroup: string?,
	-- Base chance for each rarity before pity, as a fraction (0.008 = 0.8%).
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
	-- Share of 4-stars that are featured (default 0.5).
	featured4Chance: number?,
	featured5: { string },
	featured4: { string },
	pool5: { string },
	pool4: { string },
	pool3: { string },
	-- Relative weights for picking within a pool (default 1 each).
	weights: { [string]: number }?,
	-- Star Pick unlocks after this many pulls without the featured 5-star (or, with starPickOnce,
	-- this many pulls in total, once).
	starPickAt: number?,
	starPickOnce: boolean?,
	-- What a once-only Star Pick can choose from.
	starPickPool: { string }?,
	-- A banner that ends after this many pulls (the beginner banner).
	maxPulls: number?,
	-- A cheaper price for a ten-pull, in tokens (the beginner banner).
	tenPullCost: number?,
	-- A player who has never had a 5-star in this pity group gets one by this pull, from this pool.
	newPlayerGuarantee: { pulls: number, pool: { string } }?,
	-- Armoury banners: the player picks which featured item is their target, and each 5-star has
	-- this chance to be it.
	targetPick: boolean?,
	targetChance5: number?,
}

export type PityState = {
	sinceLast5: number,
	sinceLast4: number,
	guaranteedFeatured5: boolean,
	-- Pulls since the last featured 5-star (what Star Pick counts).
	sinceFeatured5: number,
	-- Every pull ever made in this group.
	pullsMade: number,
	starPickUsed: boolean,
}

export type PullResult = {
	itemId: string,
	rarity: Rarity,
	featured: boolean,
	pullNumber: number, -- which pull since the previous hit of this rarity, for logs
}

export type Odds = {
	itemId: string,
	rarity: Rarity,
	featured: boolean,
	-- Chance on a single pull before pity, as a fraction.
	chance: number,
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
		sinceFeatured5 = 0,
		pullsMade = 0,
		starPickUsed = false,
	}
end

-- Fills in fields an older saved state doesn't have yet.
function Gacha.normalizeState(state: any): PityState
	local fresh = Gacha.newPityState()
	if type(state) ~= "table" then
		return fresh
	end
	for key, default in fresh :: any do
		if type(state[key]) ~= type(default) then
			state[key] = default
		end
	end
	return state :: PityState
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

-- True (and the pool to draw from) when the new-player guarantee decides the next pull.
function Gacha.newPlayerGuarantee(banner: Banner, state: PityState): { string }?
	local guarantee = banner.newPlayerGuarantee
	-- sinceLast5 only equals pullsMade while the group has never produced a 5-star.
	if guarantee and state.sinceLast5 == state.pullsMade and state.pullsMade + 1 >= guarantee.pulls then
		return guarantee.pool
	end
	return nil
end

-- The 5-star chance on the very next pull, pity and guarantees included.
function Gacha.nextRate5(banner: Banner, state: PityState): number
	if Gacha.newPlayerGuarantee(banner, state) then
		return 1
	end
	return Gacha.rate5ForPull(banner, state.sinceLast5 + 1)
end

local function pick(list: { string }, rng: Rng, weights: { [string]: number }?): string
	assert(#list > 0, "Gacha: tried to pick from an empty pool")
	if weights then
		local total = 0
		for _, id in list do
			total += weights[id] or 1
		end
		local roll = rng() * total
		for _, id in list do
			roll -= weights[id] or 1
			if roll < 0 then
				return id
			end
		end
		return list[#list]
	end
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
		sinceFeatured5 = (state.sinceFeatured5 or 0) + 1,
		pullsMade = (state.pullsMade or 0) + 1,
		starPickUsed = state.starPickUsed == true,
	}

	local forcedPool = Gacha.newPlayerGuarantee(banner, state)
	local rate5 = if forcedPool then 1 else Gacha.rate5ForPull(banner, pull5)

	if roll < rate5 then
		if forcedPool then
			local itemId = pick(forcedPool, rng, banner.weights)
			nextState.sinceLast5 = 0
			nextState.sinceLast4 = 0
			return { itemId = itemId, rarity = 5, featured = false, pullNumber = pull5 }, nextState
		end
		local hasFeatured = #banner.featured5 > 0
		local featured = hasFeatured and (state.guaranteedFeatured5 or rng() < banner.featuredChance5)
		local itemId = if featured
			then pick(banner.featured5, rng, banner.weights)
			else pick(banner.pool5, rng, banner.weights)
		nextState.sinceLast5 = 0
		-- A 5-star counts as the guaranteed 4-star-or-better too.
		nextState.sinceLast4 = 0
		nextState.guaranteedFeatured5 = hasFeatured and not featured
		if featured then
			nextState.sinceFeatured5 = 0
		end
		return { itemId = itemId, rarity = 5, featured = featured, pullNumber = pull5 }, nextState
	end

	if pull4 >= banner.hardPity4 or roll < rate5 + banner.baseRate4 then
		-- Featured 4-stars take their share of all 4-star results when the banner has any.
		local share = banner.featured4Chance or 0.5
		local featured = #banner.featured4 > 0 and (#banner.pool4 == 0 or rng() < share)
		local itemId = if featured then pick(banner.featured4, rng, nil) else pick(banner.pool4, rng, nil)
		nextState.sinceLast4 = 0
		return { itemId = itemId, rarity = 4, featured = featured, pullNumber = pull4 }, nextState
	end

	return { itemId = pick(banner.pool3, rng, nil), rarity = 3, featured = false, pullNumber = pull4 },
		nextState
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

-- Pulls left until the 5-star is certain.
function Gacha.pullsToGuarantee(banner: Banner, state: PityState): number
	local left = math.max(0, banner.hardPity5 - state.sinceLast5)
	local guarantee = banner.newPlayerGuarantee
	if guarantee and state.sinceLast5 == state.pullsMade then
		left = math.min(left, math.max(1, guarantee.pulls - state.pullsMade))
	end
	return left
end

-- What a pull of `count` costs in tokens.
function Gacha.cost(banner: Banner, count: number): number
	if count == 10 and banner.tenPullCost then
		return banner.tenPullCost
	end
	return count
end

-- Whether Star Pick can be used now.
function Gacha.starPickReady(banner: Banner, state: PityState): boolean
	local at = banner.starPickAt
	if not at then
		return false
	end
	if banner.starPickOnce then
		return state.pullsMade >= at and not state.starPickUsed
	end
	return state.sinceFeatured5 >= at
end

-- Pulls left before Star Pick unlocks (0 when ready), or nil when the banner has none.
function Gacha.starPickIn(banner: Banner, state: PityState): number?
	local at = banner.starPickAt
	if not at then
		return nil
	end
	if banner.starPickOnce then
		return if state.starPickUsed then nil else math.max(0, at - state.pullsMade)
	end
	return math.max(0, at - state.sinceFeatured5)
end

-- The items Star Pick can choose from.
function Gacha.starPickChoices(banner: Banner): { string }
	if banner.starPickOnce then
		return banner.starPickPool or banner.pool5
	end
	return banner.featured5
end

-- Uses Star Pick: returns the chosen 5-star as a result and the new state, or nil and a reason.
function Gacha.starPick(banner: Banner, state: PityState, itemId: string): (PullResult?, PityState?, string?)
	if not Gacha.starPickReady(banner, state) then
		return nil, nil, "not_ready"
	end
	if not table.find(Gacha.starPickChoices(banner), itemId) then
		return nil, nil, "not_a_choice"
	end
	local nextState = table.clone(state)
	nextState.sinceFeatured5 = 0
	nextState.guaranteedFeatured5 = false
	if banner.starPickOnce then
		nextState.starPickUsed = true
	end
	local featured = table.find(banner.featured5, itemId) ~= nil
	return { itemId = itemId, rarity = 5, featured = featured, pullNumber = 0 }, nextState, nil
end

-- A copy of an Armoury banner aimed at one featured weapon: that weapon becomes "the featured
-- item" with its own chance, and the other featured weapon moves to the ordinary 5-star pool at
-- its own share, so every item's chance matches the published table whichever target is chosen.
function Gacha.withTarget(banner: Banner, targetId: string): Banner?
	if not banner.targetPick or not table.find(banner.featured5, targetId) then
		return nil
	end
	local chance = banner.targetChance5 or 0.375
	local aimed = table.clone(banner)
	aimed.featured5 = { targetId }
	aimed.featuredChance5 = chance
	local pool5 = {}
	local weights: { [string]: number } = {}
	local others = 0
	for _, id in banner.featured5 do
		if id ~= targetId then
			table.insert(pool5, id)
			weights[id] = chance
			others += 1
		end
	end
	local rest = math.max(0, 1 - chance * (others + 1))
	for _, id in banner.pool5 do
		table.insert(pool5, id)
		weights[id] = rest / math.max(1, #banner.pool5)
	end
	aimed.pool5 = pool5
	aimed.weights = weights
	return aimed
end

-- Average 5-star chance per pull over the long run, with pity: 1 / (average pulls per 5-star).
function Gacha.overallRate5(banner: Banner): number
	local survive = 1
	local expected = 0
	for pull = 1, banner.hardPity5 do
		local rate = Gacha.rate5ForPull(banner, pull)
		expected += pull * survive * rate
		survive *= 1 - rate
		if survive <= 0 then
			break
		end
	end
	return if expected > 0 then 1 / expected else banner.baseRate5
end

-- The chance of every possible result on one pull, before pity. They add up to exactly 1.
-- Pity raises the 5-star share overall; the banner screen shows both this table and the pity rules.
function Gacha.itemOdds(banner: Banner): { Odds }
	local out: { Odds } = {}
	local hasFeatured5 = #banner.featured5 > 0
	local featuredShare5 = if hasFeatured5 then banner.featuredChance5 else 0
	local used = 0
	local weights = banner.weights

	local function add(
		items: { string },
		rarity: number,
		featured: boolean,
		total: number,
		itemWeights: { [string]: number }?
	)
		if #items == 0 then
			return
		end
		local sum = 0
		for _, itemId in items do
			sum += if itemWeights then (itemWeights[itemId] or 1) else 1
		end
		for _, itemId in items do
			local share = (if itemWeights then (itemWeights[itemId] or 1) else 1) / sum
			local each = total * share
			table.insert(out, { itemId = itemId, rarity = rarity, featured = featured, chance = each })
			used += each
		end
	end

	add(banner.featured5, 5, true, banner.baseRate5 * featuredShare5, weights)
	add(banner.pool5, 5, false, banner.baseRate5 * (1 - featuredShare5), weights)
	local share4 = if #banner.featured4 > 0 then (banner.featured4Chance or 0.5) else 0
	if #banner.pool4 == 0 then
		share4 = if #banner.featured4 > 0 then 1 else 0
	end
	add(banner.featured4, 4, true, banner.baseRate4 * share4, nil)
	add(banner.pool4, 4, false, banner.baseRate4 * (1 - share4), nil)
	-- 3-stars take whatever is left, so the table always adds up to 100%.
	add(banner.pool3, 3, false, 1 - used, nil)
	return out
end

-- The odds players must be shown before they spend anything. Roblox requires paid random
-- items to show their odds, so the shop UI should render this, not hard-coded text.
function Gacha.publishedOdds(banner: Banner): { [string]: any }
	return {
		fiveStarBase = banner.baseRate5,
		fourStarBase = banner.baseRate4,
		threeStarBase = 1 - banner.baseRate5 - banner.baseRate4,
		fiveStarHardPity = banner.hardPity5,
		fiveStarSoftPity = banner.softPity5,
		fiveStarOverall = Gacha.overallRate5(banner),
		fourStarHardPity = banner.hardPity4,
		featuredFiveStarChance = banner.featuredChance5,
		featuredFourStarChance = banner.featured4Chance or 0.5,
		starPickAt = banner.starPickAt,
		items = Gacha.itemOdds(banner),
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
	if banner.targetPick and (#banner.featured5 < 2 or banner.targetChance5 == nil) then
		return false, "a target-pick banner needs two featured 5-stars and a target chance"
	end
	if banner.starPickOnce and banner.starPickAt and #Gacha.starPickChoices(banner) == 0 then
		return false, "Star Pick has nothing to choose from"
	end
	return true, nil
end

return Gacha
