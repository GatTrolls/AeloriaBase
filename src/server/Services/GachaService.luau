--!strict
--[[
	GachaService

	Starfall: pulls, Star Pick, token exchange, the Armoury target and pull history. Every roll
	happens here with the pure logic in Shared.Gacha; clients only ask.

	Roblox rules this service follows (details in docs/systems/platform-rules.md):
	  * Odds are published to the client through GetBannerOdds and shown before buying.
	  * Pull history is kept for six months and can be read back by the player.
	  * In regions where paid random items are restricted (PolicyService), players can only pull
	    with currency earned in game: Pure Starglass (bought with Robux) will not exchange.
	  * Nothing here can be traded; results never change hands.

	Pity, the 50/50 guarantee and Star Pick progress are saved per pity group (profile.pity[group]),
	so every Featured banner shares them. First Light's pulls count toward Everlit's pity.
]]

local PolicyService = game:GetService("PolicyService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage.Shared
local Banners = require(Shared.Config.Banners)
local Economy = require(Shared.Config.Economy)
local Gacha = require(Shared.Gacha)
local GameConfig = require(Shared.Config.GameConfig)
local Net = require(Shared.Net)
local RateLimit = require(Shared.RateLimit)
local Rewards = require(Shared.Rewards)

local PlayerDataService = require(script.Parent.PlayerDataService)

local GachaService = {}

local rng = Random.new()
local busy: { [Player]: boolean } = {}
local paidRandomRestricted: { [Player]: boolean } = {}
local limiter = RateLimit.new(4, 8)

local STAR_CURRENCIES = { goldStar = true, silverStar = true }
-- Guild Rank at which Starfall opens when the prologue flag is not set (the design plan's table).
local STARFALL_RANK = 5

local function fail(code: string): { [string]: any }
	return { ok = false, error = code }
end

local function isRestricted(player: Player): boolean
	local cached = paidRandomRestricted[player]
	if cached ~= nil then
		return cached
	end
	local ok, info = pcall(PolicyService.GetPolicyInfoForPlayerAsync, PolicyService, player)
	-- If the policy lookup fails, assume restricted. Blocking a pull is safer than breaking the rules.
	local restricted = not ok or info.ArePaidRandomItemsRestricted == true
	paidRandomRestricted[player] = restricted
	return restricted
end

local function starfallOpen(profile: { [string]: any }): boolean
	return RunService:IsStudio()
		or profile.flags.starfall == true
		or (profile.guild and profile.guild.rank >= STARFALL_RANK)
end

local function activeBanner(id: unknown): Gacha.Banner?
	if type(id) ~= "string" or not table.find(Banners.Active, id) then
		return nil
	end
	return Banners.get(id)
end

local function pityState(profile: { [string]: any }, banner: Gacha.Banner): Gacha.PityState
	local key = Banners.pityKey(banner)
	local state = Gacha.normalizeState(profile.pity[key])
	profile.pity[key] = state
	return state
end

-- The banner as this player rolls it: an Armoury banner is aimed at their chosen target.
local function rollBanner(profile: { [string]: any }, banner: Gacha.Banner): Gacha.Banner
	if not banner.targetPick then
		return banner
	end
	local target = profile.flags.armouryTarget
	if type(target) ~= "string" or not table.find(banner.featured5, target) then
		target = banner.featured5[1]
	end
	return Gacha.withTarget(banner, target) or banner
end

local function recordHistory(profile: { [string]: any }, bannerId: string, results: { Gacha.PullResult })
	local history = profile.pullHistory
	local now = os.time()
	for _, result in results do
		table.insert(history, { at = now, banner = bannerId, itemId = result.itemId, rarity = result.rarity })
	end
	Rewards.trimHistory(history, now, GameConfig.Gacha.HistoryDays, GameConfig.Gacha.HistoryMaxEntries)
end

-- Counts pulls made today and says whether one just crossed a reminder step.
local function countToday(profile: { [string]: any }, count: number): boolean
	local day = math.floor(os.time() / 86400)
	local flags = profile.flags
	if flags.pullDay ~= day then
		flags.pullDay = day
		flags.pullsToday = 0
	end
	local before = flags.pullsToday or 0
	flags.pullsToday = before + count
	local step = Economy.PaidPullReminderEvery
	return math.floor(flags.pullsToday / step) > math.floor(before / step)
end

local function describe(result: Gacha.PullResult, grant: Rewards.Grant): { [string]: any }
	return {
		itemId = result.itemId,
		rarity = result.rarity,
		featured = result.featured,
		kind = grant.kind,
		isNew = grant.isNew,
		moonflakes = grant.moonflakes,
		awakening = grant.awakening,
		polish = grant.polish,
		maxed = grant.maxed,
	}
end

local function begin(player: Player): ({ [string]: any }?, { [string]: any }?)
	if not RateLimit.allow(limiter, player, os.clock()) then
		return nil, fail("rate_limited")
	end
	if busy[player] then
		return nil, fail("busy")
	end
	local profile = PlayerDataService.get(player)
	if not profile then
		return nil, fail("not_loaded")
	end
	if not starfallOpen(profile) then
		return nil, fail("locked")
	end
	return profile, nil
end

local function handlePull(player: Player, bannerId: unknown, count: unknown)
	if type(count) ~= "number" or (count ~= 1 and count ~= GameConfig.Gacha.MaxPullsPerRequest) then
		return fail("bad_count")
	end
	local banner = activeBanner(bannerId)
	if not banner then
		return fail("unknown_banner")
	end
	local profile, problem = begin(player)
	if not profile then
		return problem
	end

	local flags = profile.flags
	if banner.maxPulls then
		local used = flags.firstLightPulls or 0
		if used + count > banner.maxPulls then
			return fail("banner_used_up")
		end
	end

	local currency = banner.currency or "silverStar"
	local cost = Gacha.cost(banner, count)
	if not Rewards.canAfford(profile, currency, cost) then
		return fail("not_enough_currency")
	end

	local state = pityState(profile, banner)
	local results, nextState = Gacha.pullMany(rollBanner(profile, banner), state, count, function()
		return rng:NextNumber()
	end)

	profile.currencies[currency] -= cost
	profile.pity[Banners.pityKey(banner)] = nextState
	local out = table.create(#results)
	for _, result in results do
		table.insert(out, describe(result, Rewards.grantItem(profile, result.itemId)))
	end
	recordHistory(profile, banner.id, results)
	if banner.maxPulls then
		flags.firstLightPulls = (flags.firstLightPulls or 0) + count
	end
	local reminder = countToday(profile, count)

	PlayerDataService.markChanged(player)
	return { ok = true, results = out, pity = nextState, cost = cost, reminder = reminder }
end

local function handleStarPick(player: Player, bannerId: unknown, itemId: unknown)
	local banner = activeBanner(bannerId)
	if not banner or type(itemId) ~= "string" then
		return fail("bad_request")
	end
	local profile, problem = begin(player)
	if not profile then
		return problem
	end
	local state = pityState(profile, banner)
	local result, nextState, reason = Gacha.starPick(banner, state, itemId)
	if not result or not nextState then
		return fail(reason or "not_ready")
	end
	profile.pity[Banners.pityKey(banner)] = nextState
	local grant = Rewards.grantItem(profile, result.itemId)
	recordHistory(profile, banner.id, { result })
	PlayerDataService.markChanged(player)
	return { ok = true, results = { describe(result, grant) }, pity = nextState }
end

local function handleExchange(player: Player, currencyId: unknown, count: unknown, usePure: unknown)
	if type(currencyId) ~= "string" or not STAR_CURRENCIES[currencyId] then
		return fail("bad_request")
	end
	if type(count) ~= "number" or count ~= math.floor(count) or count < 1 or count > 100 then
		return fail("bad_count")
	end
	local profile, problem = begin(player)
	if not profile then
		return problem
	end
	local cost = count * Economy.StarCost
	local source = "starglass"
	if usePure == true then
		busy[player] = true
		local restricted = isRestricted(player)
		busy[player] = nil
		-- Bought currency never turns into random-item tokens for restricted players.
		if restricted then
			return fail("restricted")
		end
		source = "pureStarglass"
	end
	if not Rewards.canAfford(profile, source, cost) then
		return fail("not_enough_currency")
	end
	profile.currencies[source] -= cost
	profile.currencies[currencyId] += count
	PlayerDataService.markChanged(player)
	return { ok = true, currency = currencyId, count = count, cost = cost, source = source }
end

local function handleTarget(player: Player, itemId: unknown)
	if type(itemId) ~= "string" then
		return fail("bad_request")
	end
	local profile, problem = begin(player)
	if not profile then
		return problem
	end
	for _, id in Banners.Active do
		local banner = Banners.get(id)
		if banner and banner.targetPick and table.find(banner.featured5, itemId) then
			profile.flags.armouryTarget = itemId
			PlayerDataService.markChanged(player)
			return { ok = true, target = itemId }
		end
	end
	return fail("not_a_target")
end

local function handleHistory(player: Player, offset: unknown, limit: unknown)
	if not RateLimit.allow(limiter, player, os.clock()) then
		return fail("rate_limited")
	end
	local profile = PlayerDataService.get(player)
	if not profile then
		return fail("not_loaded")
	end
	local from = if type(offset) == "number" then math.max(0, math.floor(offset)) else 0
	local take = if type(limit) == "number" then math.clamp(math.floor(limit), 1, 50) else 20
	local history = profile.pullHistory
	local total = #history
	local entries = {}
	-- Newest first.
	for index = total - from, math.max(1, total - from - take + 1), -1 do
		local entry = history[index]
		if entry then
			table.insert(
				entries,
				{ at = entry.at, banner = entry.banner, itemId = entry.itemId, rarity = entry.rarity }
			)
		end
	end
	return { ok = true, entries = entries, total = total }
end

-- False for players in regions where buying random items with Robux is restricted.
function GachaService.canUsePaidRandomItems(player: Player): boolean
	return not isRestricted(player)
end

function GachaService:Init()
	Net.func(Net.Names.RequestPull).OnServerInvoke = handlePull
	Net.func(Net.Names.StarPick).OnServerInvoke = handleStarPick
	Net.func(Net.Names.ExchangeStars).OnServerInvoke = handleExchange
	Net.func(Net.Names.SetArmouryTarget).OnServerInvoke = handleTarget
	Net.func(Net.Names.GetPullHistory).OnServerInvoke = handleHistory
	Net.func(Net.Names.GetBannerOdds).OnServerInvoke = function(player: Player, bannerId: unknown)
		local banner = activeBanner(bannerId)
		if not banner then
			return nil
		end
		local profile = PlayerDataService.get(player)
		return Gacha.publishedOdds(if profile then rollBanner(profile, banner) else banner)
	end
end

function GachaService:Start()
	game:GetService("Players").PlayerRemoving:Connect(function(player)
		busy[player] = nil
		paidRandomRestricted[player] = nil
		RateLimit.forget(limiter, player)
	end)
end

return GachaService
