--!strict
--[[
	Hero kits. Every number a designer might tune is here; services never hard-code kit values.

	A kit follows the character framework:
	  * Basic Attack: a 4 or 5 hit chain set by the weapon, a charged attack (hold) and a plunge
	    (attack while gliding or falling).
	  * Technique: the character's skill, on a 6 to 15 second cooldown.
	  * Finale: the ultimate, paid for with 60 to 90 Finale energy.
	  * Relay: fires when the character swaps in after at least 6 seconds on the bench.

	Techniques, Finales and Relays are lists of steps that the server runs in order (see
	src/server/Combat/AbilityRunner.luau). Step kinds:
	  hit     an area hit: a circle, or an arc in front of the caster
	  line    a hit along a straight line ahead of the caster (dashes)
	  dash    the caster dashes forward; later steps start from where the dash ends
	  pull    drags enemies around a point towards it
	  rain    a run of small hits falling at random points in an area
	  zone    a lasting area that hits enemies or heals the party every interval
	  heal    heals the active hero, the incoming hero or the whole party
	  shield  shields the active hero or the whole party
	  effect  puts a timed effect (Slowed, Marked) on enemies in an area
	  infuse  gives a hero's next few basic attacks an element

	Ids are placeholders until the roster is announced; display names come from the private
	content table in Studio (see docs/systems/combat.md#names-and-content).
]]

export type Weapon = "sword" | "greatsword" | "lance" | "bow" | "focus"

export type Hit = {
	multiplier: number, -- share of attack
	range: number, -- studs in front of the hero
	arc: number, -- degrees, full width of the swing
	recovery: number, -- seconds before the next action is accepted
	poise: number, -- poise damage to enemies that can flinch
	heavy: boolean?, -- heavy hits shatter Lock and fill Composure
}

export type Step = {
	kind: "hit" | "line" | "dash" | "pull" | "rain" | "zone" | "heal" | "shield" | "effect" | "infuse",
	delay: number?, -- seconds after the action starts
	forward: number?, -- studs ahead of the step's origin where it is centred
	radius: number?,
	shape: ("circle" | "arc")?,
	arc: number?,
	length: number?, -- line and dash
	width: number?, -- line
	seconds: number?, -- dash, zone, effect
	multiplier: number?,
	poise: number?,
	heavy: boolean?,
	-- "kit" (default) uses the hero's element; "none" is physical.
	element: string?,
	strength: number?, -- pull
	count: number?, -- rain
	interval: number?, -- rain, zone
	impactRadius: number?, -- rain
	target: ("active" | "incoming" | "party")?, -- heal, shield, infuse
	attackShare: number?, -- heal
	hpShare: number?, -- heal, shield
	effect: string?, -- effect: "Slowed" or "Marked"
	hits: number?, -- infuse
	-- zone contents
	tickHit: { multiplier: number, poise: number }?,
	tickHeal: { attackShare: number, hpShare: number }?,
}

export type Kit = {
	id: string,
	displayName: string,
	element: string,
	weapon: Weapon,
	rarity: number,
	role: string,
	color: { number }, -- RGB 0-255
	idle: string?, -- standing idle style (Shared.Anim.Idles); nil is the default breathing idle
	stats: {
		maxHp: number,
		attack: number,
		defense: number,
		critRate: number,
		critDamage: number,
		level: number,
	},
	chain: { Hit },
	-- Whether basic attacks carry the hero's element (Focus users) or are physical.
	chainIsElemental: boolean,
	charged: Hit & { holdSeconds: number },
	plunge: { multiplier: number, radius: number, poise: number },
	technique: {
		cooldown: number,
		recovery: number,
		energyPerTarget: number,
		maxEnergyPerCast: number,
		steps: { Step },
	},
	finale: {
		cooldown: number,
		recovery: number,
		energyCost: number,
		steps: { Step },
	},
	relay: { steps: { Step } },
}

local function hit(multiplier: number, range: number, arc: number, recovery: number, poise: number): Hit
	return { multiplier = multiplier, range = range, arc = arc, recovery = recovery, poise = poise }
end

local function heavy(multiplier: number, range: number, arc: number, recovery: number, poise: number): Hit
	return {
		multiplier = multiplier,
		range = range,
		arc = arc,
		recovery = recovery,
		poise = poise,
		heavy = true,
	}
end

local Heroes: { [string]: Kit } = {
	-- The main character: an Astral sword user. Technique: a dash that drags enemies together
	-- into a small gravity well. Finale: a rain of falling stars.
	hero_main = {
		id = "hero_main",
		displayName = "Wanderer",
		element = "Astral",
		weapon = "sword",
		rarity = 5,
		role = "Main damage",
		color = { 228, 182, 82 },
		stats = { maxHp = 1150, attack = 200, defense = 600, critRate = 0.15, critDamage = 0.6, level = 20 },
		chain = {
			hit(0.45, 7, 110, 0.38, 12),
			hit(0.48, 7, 110, 0.4, 12),
			hit(0.55, 7.5, 140, 0.45, 15),
			hit(0.6, 7.5, 140, 0.5, 18),
			heavy(0.9, 8, 170, 0.85, 35),
		},
		chainIsElemental = false,
		charged = {
			multiplier = 1.4,
			range = 7.5,
			arc = 200,
			recovery = 0.7,
			poise = 40,
			heavy = true,
			holdSeconds = 0.4,
		},
		plunge = { multiplier = 1.6, radius = 6, poise = 50 },
		technique = {
			cooldown = 8,
			recovery = 0.45,
			energyPerTarget = 3,
			maxEnergyPerCast = 9,
			steps = {
				{ kind = "dash", length = 12, seconds = 0.25 },
				{ kind = "line", length = 12, width = 3.5, multiplier = 0.9, poise = 20 },
				{ kind = "pull", radius = 9, strength = 26, delay = 0.25 },
				{ kind = "hit", radius = 5.5, multiplier = 1.1, poise = 30, heavy = true, delay = 0.55 },
			},
		},
		finale = {
			cooldown = 15,
			recovery = 1,
			energyCost = 70,
			steps = {
				{
					kind = "rain",
					forward = 4,
					radius = 10,
					count = 12,
					interval = 0.12,
					impactRadius = 3.5,
					multiplier = 0.45,
					poise = 15,
				},
				{
					kind = "hit",
					forward = 4,
					radius = 10,
					multiplier = 1.8,
					poise = 100,
					heavy = true,
					delay = 1.6,
				},
			},
		},
		relay = {
			steps = { { kind = "hit", forward = 2, radius = 6, multiplier = 0.9, poise = 25 } },
		},
	},

	-- A Tide lance (harpoon) healer. Technique: a water net that marks enemies Wet and heals
	-- the active hero. Finale: a wave that heals the party and leaves a healing pool.
	-- Relay: a splash that heals the incoming hero.
	hero_tide_healer = {
		id = "hero_tide_healer",
		displayName = "Tide Healer",
		element = "Tide",
		weapon = "lance",
		rarity = 4,
		role = "Healer",
		color = { 90, 168, 236 },
		idle = "gentle",
		stats = { maxHp = 1250, attack = 150, defense = 650, critRate = 0.05, critDamage = 0.5, level = 20 },
		chain = {
			hit(0.4, 8.5, 60, 0.4, 8),
			hit(0.42, 8.5, 60, 0.42, 8),
			hit(0.48, 9, 70, 0.45, 10),
			hit(0.5, 9, 70, 0.48, 12),
			heavy(0.8, 9.5, 90, 0.8, 25),
		},
		chainIsElemental = false,
		charged = {
			multiplier = 1.2,
			range = 9.5,
			arc = 40,
			recovery = 0.6,
			poise = 30,
			heavy = true,
			holdSeconds = 0.4,
		},
		plunge = { multiplier = 1.3, radius = 5.5, poise = 35 },
		technique = {
			cooldown = 10,
			recovery = 0.5,
			energyPerTarget = 3,
			maxEnergyPerCast = 9,
			steps = {
				{ kind = "hit", forward = 7, radius = 6, multiplier = 0.9, poise = 15 },
				{ kind = "heal", target = "active", attackShare = 0.6, hpShare = 0.06 },
			},
		},
		finale = {
			cooldown = 18,
			recovery = 1,
			energyCost = 70,
			steps = {
				{
					kind = "hit",
					forward = 3,
					radius = 11,
					multiplier = 1.6,
					poise = 60,
					heavy = true,
					delay = 0.3,
				},
				{ kind = "heal", target = "party", attackShare = 1, hpShare = 0.12, delay = 0.3 },
				{
					kind = "zone",
					radius = 7,
					seconds = 8,
					interval = 1,
					tickHeal = { attackShare = 0.15, hpShare = 0.02 },
					delay = 0.3,
				},
			},
		},
		relay = {
			steps = {
				{ kind = "heal", target = "incoming", attackShare = 0.5, hpShare = 0.05 },
				{ kind = "hit", forward = 2, radius = 5, multiplier = 0.4, poise = 10 },
			},
		},
	},

	-- A Frost Focus debuffer. Technique: a frost lens that slows enemies. Finale: a frozen
	-- constellation that hits again and again. Relay: marks the nearest enemy to take more
	-- critical damage.
	hero_frost_debuffer = {
		id = "hero_frost_debuffer",
		displayName = "Frost Debuffer",
		element = "Frost",
		weapon = "focus",
		rarity = 4,
		role = "Debuffer",
		color = { 127, 208, 240 },
		idle = "folded",
		stats = { maxHp = 1000, attack = 175, defense = 550, critRate = 0.1, critDamage = 0.6, level = 20 },
		chain = {
			hit(0.42, 14, 40, 0.55, 6),
			hit(0.42, 14, 40, 0.55, 6),
			hit(0.5, 14, 45, 0.6, 8),
			heavy(0.8, 15, 50, 0.95, 20),
		},
		chainIsElemental = true,
		charged = {
			multiplier = 1.3,
			range = 15,
			arc = 30,
			recovery = 0.7,
			poise = 20,
			heavy = true,
			holdSeconds = 0.4,
		},
		plunge = { multiplier = 1.1, radius = 5, poise = 25 },
		technique = {
			cooldown = 9,
			recovery = 0.45,
			energyPerTarget = 3,
			maxEnergyPerCast = 9,
			steps = {
				{ kind = "hit", forward = 9, radius = 6, multiplier = 1.2, poise = 20 },
				{ kind = "effect", forward = 9, radius = 6, effect = "Slowed", seconds = 4 },
			},
		},
		finale = {
			cooldown = 15,
			recovery = 0.9,
			energyCost = 60,
			steps = {
				{
					kind = "zone",
					forward = 8,
					radius = 8,
					seconds = 5,
					interval = 0.5,
					tickHit = { multiplier = 0.35, poise = 10 },
				},
			},
		},
		relay = {
			steps = {
				{ kind = "effect", radius = 15, effect = "Marked", seconds = 8 },
				{ kind = "hit", forward = 3, radius = 4, multiplier = 0.5, poise = 10 },
			},
		},
	},

	-- A Flame greatsword (forge hammer) sub-damage dealer. Technique: a hammer swing that
	-- leaves molten glass on the ground. Finale: three slams, the last a big explosion.
	-- Relay: gives the incoming hero fire on their next attacks.
	hero_flame_hammer = {
		id = "hero_flame_hammer",
		displayName = "Flame Hammer",
		element = "Flame",
		weapon = "greatsword",
		rarity = 4,
		role = "Sub-damage",
		color = { 240, 115, 85 },
		idle = "tinkerer",
		stats = { maxHp = 1300, attack = 210, defense = 620, critRate = 0.08, critDamage = 0.5, level = 20 },
		chain = {
			hit(0.75, 8, 150, 0.6, 30),
			hit(0.8, 8, 150, 0.65, 30),
			hit(0.9, 8.5, 170, 0.7, 35),
			heavy(1.4, 9, 200, 1, 60),
		},
		chainIsElemental = false,
		charged = {
			multiplier = 1.6,
			range = 7,
			arc = 360,
			recovery = 0.9,
			poise = 50,
			heavy = true,
			holdSeconds = 0.4,
		},
		plunge = { multiplier = 1.8, radius = 6.5, poise = 60 },
		technique = {
			cooldown = 9,
			recovery = 0.6,
			energyPerTarget = 4,
			maxEnergyPerCast = 12,
			steps = {
				{
					kind = "hit",
					shape = "arc",
					radius = 8,
					arc = 160,
					multiplier = 1.5,
					poise = 50,
					heavy = true,
				},
				{
					kind = "zone",
					forward = 5,
					radius = 5,
					seconds = 6,
					interval = 1,
					tickHit = { multiplier = 0.25, poise = 5 },
				},
			},
		},
		finale = {
			cooldown = 14,
			recovery = 1.1,
			energyCost = 60,
			steps = {
				{ kind = "hit", forward = 4, radius = 6, multiplier = 1, poise = 40 },
				{ kind = "hit", forward = 4, radius = 6, multiplier = 1, poise = 40, delay = 0.45 },
				{
					kind = "hit",
					forward = 4,
					radius = 10,
					multiplier = 2.6,
					poise = 120,
					heavy = true,
					delay = 0.95,
				},
			},
		},
		relay = {
			steps = {
				{ kind = "infuse", target = "incoming", hits = 3 },
				{ kind = "hit", forward = 3, radius = 6, multiplier = 0.7, poise = 30 },
			},
		},
	},
}

return Heroes
