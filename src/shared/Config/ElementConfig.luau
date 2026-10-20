--!strict
-- Element and reaction data. Ids are engine-level and generic; display names, colours and
-- lore come from the story bible later and live in a separate presentation table.

export type ReactionKind = "amplify" | "transform" | "status" | "shield"

export type ReactionDef = {
	id: string,
	kind: ReactionKind,
	-- amplify: multiplies the triggering hit. transform: bonus damage scale.
	-- status and shield: unused (1).
	multiplier: number,
	-- How many aura units each trigger unit removes.
	consume: number,
	-- status reactions: seconds per trigger unit the status lasts.
	statusSecondsPerUnit: number?,
	-- Sweep-style reactions copy the aura element to nearby targets.
	spreads: boolean?,
}

local ElementConfig = {
	Elements = table.freeze({ "Wind", "Earth", "Fire", "Water", "Ice", "Lightning", "Light" }),

	-- Elements that react but never stay on a target as an aura.
	NonAttaching = table.freeze({ Wind = true, Earth = true, Light = true }),

	-- An aura of N units lasts AuraBaseSeconds + AuraSecondsPerUnit * N, decaying linearly.
	AuraBaseSeconds = 6,
	AuraSecondsPerUnit = 3,
	-- Share of the applied units that becomes aura when nothing reacts.
	AuraTax = 0.8,

	-- Internal cooldown: a source applies its element on the first hit, then every
	-- IcdHits-th hit, and again whenever IcdSeconds have passed.
	IcdHits = 3,
	IcdSeconds = 2.5,

	-- Keyed "Trigger>Aura". Order matters: Water on Fire is not the same as Fire on Water.
	Reactions = {} :: { [string]: ReactionDef },
}

local function add(trigger: string, aura: string, def: ReactionDef)
	ElementConfig.Reactions[`{trigger}>{aura}`] = table.freeze(def)
end

-- Amplifying: the strong direction doubles the hit and eats more aura.
add("Water", "Fire", { id = "Steam", kind = "amplify", multiplier = 2.0, consume = 2 })
add("Fire", "Water", { id = "Steam", kind = "amplify", multiplier = 1.5, consume = 0.5 })
add("Fire", "Ice", { id = "Melt", kind = "amplify", multiplier = 2.0, consume = 2 })
add("Ice", "Fire", { id = "Melt", kind = "amplify", multiplier = 1.5, consume = 0.5 })

-- Transformative: separate bonus damage that scales with the attacker's level.
for _, pair in { { "Fire", "Lightning" }, { "Lightning", "Fire" } } do
	add(pair[1], pair[2], { id = "Overload", kind = "transform", multiplier = 2.0, consume = 1 })
end
for _, pair in { { "Lightning", "Water" }, { "Water", "Lightning" } } do
	add(pair[1], pair[2], { id = "Conduct", kind = "transform", multiplier = 1.2, consume = 1 })
end

-- Status: change what the target can do instead of dealing extra damage.
for _, pair in { { "Ice", "Water" }, { "Water", "Ice" } } do
	add(
		pair[1],
		pair[2],
		{ id = "Freeze", kind = "status", multiplier = 1, consume = 1, statusSecondsPerUnit = 2 }
	)
end
for _, pair in { { "Lightning", "Ice" }, { "Ice", "Lightning" } } do
	add(
		pair[1],
		pair[2],
		{ id = "Brittle", kind = "status", multiplier = 1, consume = 1, statusSecondsPerUnit = 4 }
	)
end

-- Wind and Earth never stick; they react with whatever aura is there.
for _, aura in { "Fire", "Water", "Lightning", "Ice" } do
	-- Sweep copies the aura to nearby enemies.
	add("Wind", aura, { id = "Sweep", kind = "transform", multiplier = 0.6, consume = 0.5, spreads = true })
	-- Shield gives the attacker a shield of the aura's element.
	add("Earth", aura, { id = "Shield", kind = "shield", multiplier = 1, consume = 0.5 })
	-- Light reacts with everything. It belongs to the main character alone at launch.
	add("Light", aura, { id = "Radiance", kind = "transform", multiplier = 2.5, consume = 1 })
end

table.freeze(ElementConfig.Reactions)

return table.freeze(ElementConfig)
