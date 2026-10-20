# Damage model

**Status:** built and tested · **Code:** `src/shared/Damage.luau` · **Tests:** `tests/Damage.spec.luau`

## Formula

```
outgoing = (attack × skillMultiplier + flatBonus) × (1 + bonusPercent) × crit
damage   = outgoing × defense × resistance × reactionMultiplier
```

| Part | Rule |
| --- | --- |
| Crit | Roll against crit rate; a crit multiplies by 1 + crit damage |
| Defense | (attackerLevel + 100) ÷ ((attackerLevel + 100) + (targetLevel + 100) × (1 − reduction)); equal levels halve damage |
| Defense reduction | From effects like Brittle, capped at 90% |
| Resistance | Below 0: 1 − res ÷ 2 · 0 to 75%: 1 − res · above 75%: 1 ÷ (4 × res + 1), so nothing is ever fully immune |
| Reaction | Amplify reactions multiply the hit (× 1.5 or × 2.0) |
| Floor | Every hit deals at least 1 |

**Transform reactions** deal separate damage: (20 + 12 × attackerLevel) × reaction scale ×
resistance. It ignores defense and crit, so every hero can make reactions worthwhile, not only
the ones with the best gear.

## Why this design

- **Level matters, but not too much.** The +100 constant keeps early fights from swinging wildly
  between levels.
- **No immunity.** The resistance curve keeps every element useful against every enemy.
- **Server-side and pure.** The server runs these formulas when it confirms a hit, and they are
  unit tested with fixed random numbers.
