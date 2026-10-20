--!strict
--[[
	Economy

	Currency definitions and the numbers that move them, from the design plan's economy and gacha
	sections. Display names are looked up through Shared.Content (keys below), so a fresh checkout
	shows generic words and the real names live in the game's private content.

	Nothing here is tradable: the economy is closed, so every price is ours to set.
]]

export type Currency = {
	id: string,
	-- Content text key for the display name; the generic fallback is the second entry of NAMES.
	textKey: string,
	color: { number },
	-- Shown in compact counters.
	short: string,
}

local Economy = {}

Economy.Currencies = table.freeze({
	glint = { id = "glint", textKey = "currency.glint", color = { 232, 196, 120 }, short = "G" } :: Currency,
	starglass = { id = "starglass", textKey = "currency.starglass", color = { 148, 214, 255 }, short = "SG" } :: Currency,
	pureStarglass = {
		id = "pureStarglass",
		textKey = "currency.pureStarglass",
		color = { 190, 160, 255 },
		short = "PS",
	} :: Currency,
	goldStar = { id = "goldStar", textKey = "currency.goldStar", color = { 255, 205, 80 }, short = "★" } :: Currency,
	silverStar = {
		id = "silverStar",
		textKey = "currency.silverStar",
		color = { 200, 214, 232 },
		short = "★",
	} :: Currency,
	moonflakes = {
		id = "moonflakes",
		textKey = "currency.moonflakes",
		color = { 170, 190, 255 },
		short = "M",
	} :: Currency,
	guildSeals = {
		id = "guildSeals",
		textKey = "currency.guildSeals",
		color = { 120, 220, 170 },
		short = "S",
	} :: Currency,
})

-- Generic names used until the private content supplies the real ones.
Economy.GenericNames = table.freeze({
	["currency.glint"] = "Coins",
	["currency.starglass"] = "Star Gems",
	["currency.pureStarglass"] = "Pure Star Gems",
	["currency.goldStar"] = "Gold Star Token",
	["currency.silverStar"] = "Silver Star Token",
	["currency.moonflakes"] = "Moon Tokens",
	["currency.guildSeals"] = "Guild Seals",
})

-- Order currencies appear in compact bars and the bag.
Economy.Order = table.freeze({
	"glint",
	"starglass",
	"goldStar",
	"silverStar",
	"moonflakes",
	"guildSeals",
	"pureStarglass",
})

-- Earned premium currency per Gold or Silver Star.
Economy.StarCost = 160

-- Dew is the daily reward budget: it refills over time up to a cap, and what would spill over
-- goes into a small reserve so a missed day costs little. It is never sold.
Economy.Dew = table.freeze({
	Max = 200,
	RefillSeconds = 480,
	ReserveMax = 120,
	ClaimCost = table.freeze({ rift = 20, starfallSite = 20, worldBoss = 40, weeklyBoss = 30 }),
})

-- What a pull pays back in Moonflakes (the plan's table).
Economy.Moonflakes = table.freeze({
	weapon3 = 1,
	new4 = 3,
	duplicate4 = 6,
	duplicate4Maxed = 12,
	any5 = 15,
	duplicate5Maxed = 40,
})

-- A duplicate character raises Awakening up to this; a duplicate weapon raises Polish up to this.
Economy.MaxAwakening = 6
Economy.MaxPolish = 5

-- Guild Rank gates, from the plan's unlock table.
Economy.RankUnlocks = table.freeze({
	{ rank = 1, key = "unlock.prologue" },
	{ rank = 5, key = "unlock.starfall" },
	{ rank = 8, key = "unlock.coop" },
	{ rank = 10, key = "unlock.rifts" },
	{ rank = 12, key = "unlock.requests" },
	{ rank = 16, key = "unlock.actTwo" },
	{ rank = 20, key = "unlock.weeklyBoss" },
	{ rank = 22, key = "unlock.spire" },
	{ rank = 25, key = "unlock.camp" },
})

Economy.MaxGuildRank = 60

-- Reminders and limits that keep pulling gentle (the plan's kid-safe rules).
Economy.PaidPullReminderEvery = 10

return Economy
