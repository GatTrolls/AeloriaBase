--!strict
-- Elements, the statuses they leave and the reactions between them. Shared by the rules engine
-- (Shared.Elements), the server and the tests. Colours and on-screen labels live in ElementStyle.

export type ReactionKind =
	"amplify" -- multiplies the hit that triggered it
	| "explode" -- area damage around the target, knocks small enemies back
	| "chain" -- damage that jumps between Wet enemies near the target over a few seconds
	| "lock" -- freezes the target; the next heavy hit shatters it for bonus damage
	| "weaken" -- lowers the target's defence for a while
	| "spread" -- copies the status to nearby enemies, pulls small ones in, cuts resistance
	| "geode" -- leaves a crystal that shields whoever walks into it
	| "starburst" -- a starlight blast of both elements that clears the status

export type ReactionDef = {
	id: string,
	kind: ReactionKind,
	multiplier: number?, -- amplify
	scale: number?, -- reaction damage scale (see Damage.reactionDamage)
	radius: number?,
	seconds: number?, -- how long a lasting effect stays
	ticks: number?, -- chain: number of damage pulses
	defenseCut: number?, -- weaken
	resistanceCut: number?, -- spread
	shatterScale: number?, -- lock: bonus damage scale when shattered
	cooldownSeconds: number?, -- starburst: once per enemy every this many seconds
	energy: number?, -- starburst: Finale energy for the caster
}

export type StatusDef = {
	id: string,
	seconds: number,
}

local ElementConfig = {
	Elements = table.freeze({ "Flame", "Tide", "Frost", "Volt", "Gale", "Terra", "Astral" }),

	-- Four elements leave a status on an enemy. The other three never stay; they react with
	-- whatever status is already there.
	Statuses = table.freeze({
		Flame = table.freeze({ id = "Burning", seconds = 8 }),
		Tide = table.freeze({ id = "Wet", seconds = 10 }),
		Frost = table.freeze({ id = "Chilled", seconds = 8 }),
		Volt = table.freeze({ id = "Charged", seconds = 8 }),
	}) :: { [string]: StatusDef },

	-- Basic attacks apply their element at most once every this many seconds per enemy.
	-- Techniques, Finales and Relays always apply.
	BasicApplySeconds = 2.5,

	-- Burning deals small damage once a second for as long as it lasts.
	BurningTickSeconds = 1,
	BurningScale = 0.08,
	-- Chilled enemies move this much slower.
	ChilledSlow = 0.15,

	-- Reactions between two statuses, keyed by the two element names in alphabetical order.
	Reactions = {} :: { [string]: ReactionDef },
	-- Reactions for the elements that never stay, whatever status they meet.
	TriggerReactions = {} :: { [string]: ReactionDef },
}

local function pair(a: string, b: string, def: ReactionDef)
	local key = if a < b then `{a}+{b}` else `{b}+{a}`
	ElementConfig.Reactions[key] = table.freeze(def)
end

pair("Flame", "Tide", { id = "Scald", kind = "amplify", multiplier = 1.5 })
pair("Flame", "Frost", { id = "Thaw", kind = "amplify", multiplier = 1.75 })
pair("Flame", "Volt", { id = "Flashpoint", kind = "explode", scale = 1.6, radius = 7 })
pair("Tide", "Volt", { id = "Conduct", kind = "chain", scale = 0.35, radius = 9, ticks = 4, seconds = 4 })
pair("Frost", "Tide", { id = "Lock", kind = "lock", seconds = 3, shatterScale = 1.5 })
pair("Frost", "Volt", { id = "Brittle", kind = "weaken", defenseCut = 0.25, seconds = 8 })

ElementConfig.TriggerReactions.Gale = table.freeze({
	id = "Sweep",
	kind = "spread",
	scale = 0.5,
	radius = 8,
	resistanceCut = 0.2,
	seconds = 8,
} :: ReactionDef)
ElementConfig.TriggerReactions.Terra = table.freeze({
	id = "Geode",
	kind = "geode",
	seconds = 10,
} :: ReactionDef)
ElementConfig.TriggerReactions.Astral = table.freeze({
	id = "Starburst",
	kind = "starburst",
	scale = 2,
	radius = 4,
	cooldownSeconds = 2,
	energy = 4,
} :: ReactionDef)

table.freeze(ElementConfig.Reactions)
table.freeze(ElementConfig.TriggerReactions)

-- The reaction between an incoming element and the status already on the target, if any.
function ElementConfig.reactionFor(element: string, status: string): ReactionDef?
	if element == status then
		return nil
	end
	local trigger = ElementConfig.TriggerReactions[element]
	if trigger then
		return trigger
	end
	local key = if element < status then `{element}+{status}` else `{status}+{element}`
	return ElementConfig.Reactions[key]
end

return table.freeze(ElementConfig)
