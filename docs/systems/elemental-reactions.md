# Elemental reactions

**Status:** built and tested · **Code:** `src/shared/Elements.luau`, `src/shared/Config/ElementConfig.luau`,
`src/server/Combat/HitResolver.luau` · **Tests:** `tests/Elements.spec.luau`

## Statuses

Seven elements. Four of them leave a status on an enemy; the other three never stay, but react
with whatever status is already there.

| Element | Status it leaves | Lasts | Effect of the status |
| --- | --- | --- | --- |
| Flame | Burning | 8 s | Small damage every second |
| Tide | Wet | 10 s | None on its own |
| Frost | Chilled | 8 s | Moves 15% slower |
| Volt | Charged | 8 s | None on its own |
| Gale | none | | Reacts with any status |
| Terra | none | | Reacts with any status |
| Astral | none | | Reacts with any status; the main character's element at launch |

- An enemy holds one status at a time. The same element again refreshes it.
- A second element on a status triggers a reaction and uses the status up.
- Basic attacks apply their element at most once every 2.5 seconds per enemy, while Techniques,
  Finales and Relays always apply. Fast weapons can't spam reactions, and Techniques matter.

## Reactions

| Reaction | Elements | What it does |
| --- | --- | --- |
| Scald | Flame + Tide | The triggering hit deals 1.5× damage, whichever element lands second |
| Thaw | Flame + Frost | The triggering hit deals 1.75× damage, whichever element lands second |
| Flashpoint | Flame + Volt | An explosion that hits everything nearby and knocks small enemies back |
| Conduct | Tide + Volt | Lightning jumps between Wet enemies near the target every second for 4 seconds |
| Lock | Tide + Frost | Freezes the enemy for up to 3 seconds; the next heavy hit shatters the ice for bonus damage. Elites and bosses can't be frozen and take Composure damage instead |
| Brittle | Volt + Frost | 25% less defence for 8 seconds |
| Sweep | Gale + any status | Spreads the status to nearby enemies, pulls small ones in and lowers their resistance to it by 20% for 8 seconds |
| Geode | Terra + any status | Leaves a crystal; walking into it gives a shield that is strongest against that element |
| Starburst | Astral + any status | A starlight blast of both elements that clears the status and gives the main character Finale energy. Once per enemy every 2 seconds |

Reaction damage (Flashpoint, Conduct, Burning, Sweep, Starburst and a Lock shatter) scales with
the attacker's level and ignores defence and crits, so every hero can use reactions (see
[Damage model](damage-model.md)). Every reaction also fills an elite's Composure bar.

## Reading them in a fight

- Each element has a colour and its own icon (a flame, a drop, a snowflake, a zigzag, a swirl, a
  diamond and a four-point star), shown next to an enemy's health bar while it carries a status.
- Each reaction flashes its name in one big word: "SCALD!", "LOCK!".

## Example

```lua
local target = Elements.newTarget()
Elements.apply(target, "Tide", now)                 -- the enemy is Wet
local result = Elements.apply(target, "Flame", now) -- Scald
-- result.hitMultiplier == 1.5, and the Wet status is used up
```

Target state is updated in place on purpose: combat calls this many times a second, and a new
table per hit would add garbage-collection pressure for no benefit.
