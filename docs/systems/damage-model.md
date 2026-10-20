# Damage model

**Status:** built and tested · **Code:** `src/shared/Damage.luau` · **Tests:** `tests/Damage.spec.luau`

## Formula

```
damage = attack × move multiplier × (1 + damage bonuses) × crit
         × defence factor × resistance factor × reaction multiplier × (1 + damage taken)
```

| Part | Rule |
| --- | --- |
| Crit | Roll against crit rate; a crit multiplies by 1 + crit damage |
| Defence factor | 1 − DEF ÷ (DEF + 600 + 10 × attacker level) |
| Defence cuts | Brittle removes 25% of the target's DEF; cuts are capped at 90% |
| Resistance | Every enemy resists every element by 10% unless its definition says otherwise. Below 0: 1 − res ÷ 2 · 0 to 75%: 1 − res · above 75%: 1 ÷ (4 × res + 1), so nothing is ever fully immune |
| Resistance cuts | Sweep lowers resistance to the swept element by 20% |
| Reaction | Scald × 1.5, Thaw × 1.75 |
| Damage taken | Rattled enemies take 30% more |
| Floor | Every hit deals at least 1 |

**Reaction damage** (Flashpoint, Conduct, Burning, Sweep, Starburst and a Lock shatter) is its
own number: (20 + 12 × attacker level) × reaction scale × resistance × damage taken. It ignores
defence and crits, so every hero can make reactions worthwhile, not only the ones with the best
gear.

**Healing** is attack × a share + the target's max HP × a share, so it stays useful as everyone
levels up.

## Why this design

- **Simple to tune.** The defence factor has one constant, and a stronger attacker always gets
  more through the same enemy.
- **No immunity.** The resistance curve keeps every element useful against every enemy.
- **Server-side and pure.** The server runs these formulas when it confirms a hit, and they are
  unit tested with fixed random numbers.
