--!strict
-- Enemy definitions. Display names are placeholders until the bestiary is announced.

export type EnemyDef = {
	id: string,
	displayName: string,
	stats: {
		maxHp: number,
		attack: number,
		level: number,
		defenseLevel: number,
		resistance: number,
	},
	-- Poise breaks into a stagger when it reaches zero, then refills.
	poise: number,
	staggerSeconds: number,
	aggroRange: number,
	leashRange: number,
	attackRange: number,
	windupSeconds: number,
	recoverSeconds: number,
	attackCooldown: number,
	strike: { multiplier: number, radius: number, arc: number },
	moveSpeed: number,
	respawnSeconds: number,
	color: { number },
}

local Enemies: { [string]: EnemyDef } = {
	grunt_melee = {
		id = "grunt_melee",
		displayName = "Training Grunt",
		stats = { maxHp = 1300, attack = 95, level = 18, defenseLevel = 18, resistance = 0.1 },
		poise = 80,
		staggerSeconds = 1.1,
		aggroRange = 45,
		leashRange = 80,
		attackRange = 6,
		windupSeconds = 0.85,
		recoverSeconds = 0.9,
		attackCooldown = 2.4,
		strike = { multiplier = 1.0, radius = 8, arc = 130 },
		moveSpeed = 13,
		respawnSeconds = 6,
		color = { 120, 105, 95 },
	},
}

return Enemies
