--!strict
--[[
	Enemy definitions. Display names are placeholders until the bestiary is announced.

	Tiers follow the combat plan:
	  grunt    flinches from every hit, fights in packs, falls in 2 to 4 seconds
	  elite    a Composure bar and one or two signature mechanics, 15 to 30 seconds

	Every attack is telegraphed. Its glint says how to answer it: white is a normal attack,
	gold can be Lifted (parried), red can only be dodged. Area attacks also draw their shape
	on the ground first.
]]

export type Telegraph = "normal" | "gold" | "red"

export type AttackDef = {
	id: string,
	telegraph: Telegraph,
	windupSeconds: number,
	recoverSeconds: number,
	-- Seconds before this attack can be chosen again.
	cooldown: number,
	shape: "arc" | "circle",
	radius: number,
	arc: number?, -- degrees, for "arc"
	-- Choose this attack when the target is within this range.
	maxRange: number,
	multiplier: number,
	weight: number,
}

export type EnemyDef = {
	id: string,
	displayName: string,
	tier: "grunt" | "elite",
	stats: {
		maxHp: number,
		attack: number,
		level: number,
		defense: number,
		-- Resistance to every element unless listed in elementResistance.
		resistance: number,
		elementResistance: { [string]: number }?,
	},
	-- Poise breaks into a flinch when it reaches zero, then refills. Elites ignore poise.
	poise: number,
	staggerSeconds: number,
	-- Only elites and bosses have Composure.
	composure: number?,
	-- Played straight after a Rattled window ends, if set.
	afterRattled: string?,
	aggroRange: number,
	leashRange: number,
	-- Seconds between any two attacks.
	attackCooldown: number,
	attacks: { AttackDef },
	moveSpeed: number,
	-- Small enemies can be pulled and knocked back.
	size: "small" | "large",
	respawnSeconds: number,
	color: { number },
}

local Enemies: { [string]: EnemyDef } = {
	grunt_melee = {
		id = "grunt_melee",
		displayName = "Training Grunt",
		tier = "grunt",
		stats = { maxHp = 420, attack = 95, level = 18, defense = 400, resistance = 0.1 },
		poise = 10,
		staggerSeconds = 0.4,
		aggroRange = 45,
		leashRange = 80,
		attackCooldown = 2.4,
		attacks = {
			{
				id = "swipe",
				telegraph = "normal",
				windupSeconds = 0.85,
				recoverSeconds = 0.9,
				cooldown = 0,
				shape = "arc",
				radius = 8,
				arc = 130,
				maxRange = 6,
				multiplier = 1,
				weight = 1,
			},
		},
		moveSpeed = 13,
		size = "small",
		respawnSeconds = 6,
		color = { 120, 105, 95 },
	},

	elite_brute = {
		id = "elite_brute",
		displayName = "Training Brute",
		tier = "elite",
		stats = { maxHp = 6000, attack = 120, level = 20, defense = 500, resistance = 0.1 },
		poise = math.huge,
		staggerSeconds = 0,
		composure = 260,
		afterRattled = "slam",
		aggroRange = 50,
		leashRange = 90,
		attackCooldown = 1.4,
		attacks = {
			{
				id = "swipe",
				telegraph = "normal",
				windupSeconds = 0.7,
				recoverSeconds = 0.8,
				cooldown = 0,
				shape = "arc",
				radius = 9,
				arc = 120,
				maxRange = 7,
				multiplier = 0.8,
				weight = 3,
			},
			{
				id = "overhead",
				telegraph = "gold",
				windupSeconds = 1,
				recoverSeconds = 1.1,
				cooldown = 6,
				shape = "arc",
				radius = 9,
				arc = 60,
				maxRange = 7,
				multiplier = 1.6,
				weight = 2,
			},
			{
				id = "slam",
				telegraph = "red",
				windupSeconds = 1.3,
				recoverSeconds = 1.2,
				cooldown = 8,
				shape = "circle",
				radius = 12,
				maxRange = 10,
				multiplier = 1.3,
				weight = 2,
			},
		},
		moveSpeed = 11,
		size = "large",
		respawnSeconds = 10,
		color = { 92, 84, 110 },
	},
}

return Enemies
