--!strict
--[[
	GachaService

	Handles wish requests. All rolls happen here, using the pure logic in Shared.Gacha.

	Roblox rules this service follows (details in docs/systems/platform-rules.md):
	  * Odds are published to the client through GetBannerOdds and must be shown before buying.
	  * In regions where paid random items are restricted (PolicyService), players can only
	    wish with currency earned in game, never with currency bought for Robux.
]]

local PolicyService = game:GetService("PolicyService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Banners = require(ReplicatedStorage.Shared.Config.Banners)
local Gacha = require(ReplicatedStorage.Shared.Gacha)
local GameConfig = require(ReplicatedStorage.Shared.Config.GameConfig)
local Net = require(ReplicatedStorage.Shared.Net)
local PlayerDataService = require(script.Parent.PlayerDataService)

local GachaService = {}

local rng = Random.new()
local busy: { [Player]: boolean } = {}
local paidRandomRestricted: { [Player]: boolean } = {}

local function isRestricted(player: Player): boolean
	local cached = paidRandomRestricted[player]
	if cached ~= nil then
		return cached
	end
	local ok, info = pcall(PolicyService.GetPolicyInfoForPlayerAsync, PolicyService, player)
	-- If the policy lookup fails, assume restricted. Blocking a wish is safer than breaking the rules.
	local restricted = not ok or info.ArePaidRandomItemsRestricted == true
	paidRandomRestricted[player] = restricted
	return restricted
end

local function handlePull(player: Player, bannerId: unknown, count: unknown)
	if type(bannerId) ~= "string" or type(count) ~= "number" then
		return { ok = false, error = "bad_request" }
	end
	local banner = Banners[bannerId]
	if not banner then
		return { ok = false, error = "unknown_banner" }
	end
	if count ~= 1 and count ~= GameConfig.Gacha.MaxPullsPerRequest then
		return { ok = false, error = "bad_count" }
	end
	if busy[player] then
		return { ok = false, error = "busy" }
	end

	local profile = PlayerDataService.get(player)
	if not profile then
		return { ok = false, error = "not_loaded" }
	end

	busy[player] = true
	local cost = GameConfig.Gacha.PullCost * count
	local currencies = profile.currencies
	-- Only earned currency is spent here. When a premium-to-wish-currency exchange is added,
	-- it must call GachaService.canUsePaidRandomItems(player) and refuse when it is false.
	if currencies.wishCurrency < cost then
		busy[player] = nil
		return { ok = false, error = "not_enough_currency" }
	end

	local state = profile.pity[banner.id] or Gacha.newPityState()
	local results, nextState = Gacha.pullMany(banner, state, count, function()
		return rng:NextNumber()
	end)

	currencies.wishCurrency -= cost
	profile.pity[banner.id] = nextState
	for _, result in results do
		table.insert(profile.inventory, { itemId = result.itemId, rarity = result.rarity })
	end

	busy[player] = nil
	return { ok = true, results = results, pity = nextState }
end

-- False for players in regions where buying random items with Robux is restricted.
function GachaService.canUsePaidRandomItems(player: Player): boolean
	return not isRestricted(player)
end

function GachaService:Init()
	Net.func(Net.Names.RequestPull).OnServerInvoke = handlePull
	Net.func(Net.Names.GetBannerOdds).OnServerInvoke = function(_player, bannerId)
		local banner = type(bannerId) == "string" and Banners[bannerId]
		return if banner then Gacha.publishedOdds(banner) else nil
	end
end

function GachaService:Start()
	game:GetService("Players").PlayerRemoving:Connect(function(player)
		busy[player] = nil
		paidRandomRestricted[player] = nil
	end)
end

return GachaService
