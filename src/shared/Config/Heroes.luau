--!strict
-- Hero kits for the combat slice. Ids match the placeholder ids in Banners until the roster is
-- announced. Every number a designer might tune is here; services never hard-code kit values.

export type Hit = {
	multiplier: number, -- share of attack
	range: number, -- studs in front of the hero
	arc: number, -- degrees, full width of the swing
	recovery: number, -- seconds before the next action is accepted
	poise: number, -- poise damage dealt to enemies
	units: number?, -- element units applied, when the hit carries the hero's element
	heavy: boolean?,
}

export type Area = {
	multiplier: number,
	radius: number,
	-- How far in front of the hero the area is centred (0 = on the hero).
	forward: number,
	units: number,
	poise: number,
	recovery: number,
}

export type Kit = {
	id: string,
	displayName: string,
	element: string,
	weapon: "sword" | "catalyst" | "polearm" | "claymore",
	color: { number }, -- RGB 0-255
	stats: {
		maxHp: number,
		attack: number,
		defenseLevel: number,
		critRate: number,
		critDamage: number,
		level: number,
	},
	-- Normal attack chain, played in order.
	chain: { Hit },
	-- Whether normal attacks carry the hero's element (catalyst users) or are physical.
	chainIsElemental: boolean,
	skill: Area & { cooldown: number, energyPerTarget: number, maxEnergyPerCast: number },
	burst: Area & { cooldown: number, energyCost: number },
}

local function hit(multiplier: number, range: number, arc: number, recovery: number, poise: number): Hit
	return { multiplier = multiplier, range = range, arc = arc, recovery = recovery, poise = poise, units = 1 }
end

local Heroes: { [string]: Kit } = {
	hero_placeholder_a = {
		id = "hero_placeholder_a",
		displayName = "Hero A",
		element = "Fire",
		weapon = "sword",
		color = { 255, 120, 70 },
		stats = {
			maxHp = 1250,
			attack = 190,
			defenseLevel = 20,
			critRate = 0.15,
			critDamage = 0.6,
			level = 20,
		},
		chain = {
			hit(0.48, 7, 110, 0.32, 12),
			hit(0.5, 7, 110, 0.34, 12),
			hit(0.62, 7.5, 140, 0.42, 16),
			{ multiplier = 0.95, range = 8, arc = 160, recovery = 0.7, poise = 35, units = 1, heavy = true },
		},
		chainIsElemental = false,
		skill = {
			multiplier = 1.9,
			radius = 8,
			forward = 4,
			units = 2,
			poise = 45,
			recovery = 0.45,
			cooldown = 6,
			energyPerTarget = 4,
			maxEnergyPerCast = 12,
		},
		burst = {
			multiplier = 4.2,
			radius = 13,
			forward = 2,
			units = 4,
			poise = 120,
			recovery = 0.9,
			cooldown = 14,
			energyCost = 60,
		},
	},

	hero_placeholder_b = {
		id = "hero_placeholder_b",
		displayName = "Hero B",
		element = "Water",
		weapon = "catalyst",
		color = { 70, 160, 255 },
		stats = {
			maxHp = 1100,
			attack = 175,
			defenseLevel = 20,
			critRate = 0.1,
			critDamage = 0.5,
			level = 20,
		},
		chain = {
			hit(0.42, 14, 40, 0.36, 6),
			hit(0.42, 14, 40, 0.36, 6),
			hit(0.55, 14, 50, 0.42, 8),
			{ multiplier = 0.85, range = 15, arc = 60, recovery = 0.65, poise = 20, units = 1, heavy = true },
		},
		chainIsElemental = true,
		skill = {
			multiplier = 1.4,
			radius = 10,
			forward = 6,
			units = 2,
			poise = 25,
			recovery = 0.5,
			cooldown = 8,
			energyPerTarget = 3,
			maxEnergyPerCast = 10,
		},
		burst = {
			multiplier = 3.2,
			radius = 16,
			forward = 0,
			units = 2,
			poise = 60,
			recovery = 1,
			cooldown = 16,
			energyCost = 70,
		},
	},

	hero_placeholder_c = {
		id = "hero_placeholder_c",
		displayName = "Hero C",
		element = "Lightning",
		weapon = "polearm",
		color = { 185, 120, 255 },
		stats = {
			maxHp = 1050,
			attack = 160,
			defenseLevel = 18,
			critRate = 0.2,
			critDamage = 0.5,
			level = 20,
		},
		chain = {
			hit(0.4, 9, 50, 0.28, 8),
			hit(0.42, 9, 50, 0.28, 8),
			hit(0.5, 9, 60, 0.32, 10),
			{ multiplier = 0.8, range = 10, arc = 70, recovery = 0.6, poise = 25, units = 1, heavy = true },
		},
		chainIsElemental = false,
		skill = {
			multiplier = 1.5,
			radius = 7,
			forward = 7,
			units = 1,
			poise = 30,
			recovery = 0.4,
			cooldown = 5,
			energyPerTarget = 3,
			maxEnergyPerCast = 9,
		},
		burst = {
			multiplier = 3.6,
			radius = 12,
			forward = 6,
			units = 2,
			poise = 80,
			recovery = 0.85,
			cooldown = 12,
			energyCost = 50,
		},
	},

	hero_placeholder_d = {
		id = "hero_placeholder_d",
		displayName = "Hero D",
		element = "Ice",
		weapon = "claymore",
		color = { 150, 230, 255 },
		stats = {
			maxHp = 1400,
			attack = 200,
			defenseLevel = 22,
			critRate = 0.08,
			critDamage = 0.5,
			level = 20,
		},
		chain = {
			hit(0.7, 8, 150, 0.55, 30),
			hit(0.75, 8, 150, 0.6, 30),
			hit(0.85, 8.5, 170, 0.65, 35),
			{ multiplier = 1.3, range = 9, arc = 200, recovery = 0.95, poise = 60, units = 1, heavy = true },
		},
		chainIsElemental = false,
		skill = {
			multiplier = 2.1,
			radius = 9,
			forward = 3,
			units = 2,
			poise = 70,
			recovery = 0.6,
			cooldown = 9,
			energyPerTarget = 4,
			maxEnergyPerCast = 12,
		},
		burst = {
			multiplier = 4.5,
			radius = 12,
			forward = 3,
			units = 4,
			poise = 140,
			recovery = 1.1,
			cooldown = 15,
			energyCost = 60,
		},
	},
}

return Heroes
