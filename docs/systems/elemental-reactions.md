# Elemental reactions

**Status:** built and tested · **Code:** `src/shared/Elements.luau`, `src/shared/Config/ElementConfig.luau`
· **Tests:** `tests/Elements.spec.luau`

## The model

- **Elements:** Wind, Earth, Fire, Water, Ice, Lightning and Light. These are engine ids; the
  in-game names and colours are set by the art and story teams.
- **Units:** every elemental hit carries 1 (light), 2 (medium) or 4 (heavy) units.
- **Auras:** a hit with no reaction leaves an aura on the target worth 80% of its units. An aura
  of N units lasts 6 + 3N seconds and drains evenly over that time.
- **Reactions:** a different element meeting an aura looks up `"Trigger>Aura"` in the table.
  The aura loses `units × consume`, and the trigger does not stick.
- **Non-sticking elements:** Wind, Earth and Light never leave an aura. They only react with
  what is already there.
- **Internal cooldown:** a source applies its element on hit 1, 4, 7 and so on, and again after
  2.5 seconds, so fast multi-hit attacks cannot spam reactions.

## Reactions

| Reaction | Elements | Kind | Effect |
| --- | --- | --- | --- |
| Steam | Water on Fire / Fire on Water | Amplify | Hit × 2.0 / × 1.5 |
| Melt | Fire on Ice / Ice on Fire | Amplify | Hit × 2.0 / × 1.5 |
| Overload | Fire + Lightning | Transform | Bonus burst damage, knockback |
| Conduct | Water + Lightning | Transform | Bonus damage that can chain |
| Freeze | Water + Ice | Status | Target frozen for 2 s per unit |
| Brittle | Lightning + Ice | Status | Defense down for 4 s per unit |
| Sweep | Wind on Fire, Water, Lightning or Ice | Transform | Spreads that element to nearby enemies |
| Shield | Earth on Fire, Water, Lightning or Ice | Shield | Gives the attacker a shield of that element |
| Radiance | Light on any aura | Transform | Heavy bonus damage; the main character's element at launch |

Amplify reactions multiply the hit that triggered them. Transform reactions deal their own
damage, which scales with the attacker's level and ignores defense (see
[Damage model](damage-model.md)).

## Example

```lua
local target = Elements.newTarget()
Elements.apply(target, "Fire", 2, now)               -- target is burning
local result = Elements.apply(target, "Water", 1, now) -- Steam
-- result.hitMultiplier == 2
```

Target state is updated in place on purpose: combat calls this many times a second, and a new
table per hit would add garbage-collection pressure for no benefit.
