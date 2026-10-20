# Planned systems

**Status:** designed · Each section is the spec the code will follow. Milestones refer to
[ROADMAP.md](../../ROADMAP.md).

Combat, party and swap, movement and enemy AI are built: see [Combat](combat.md),
[Party and swap](party.md), [Movement and camera](movement-and-camera.md) and
[Enemy AI](enemy-ai.md).

## Character progression (M2)

Hero levels with ascension caps, three talents per hero, duplicate unlocks, a weapon slot and
gear sets. All curves are config tables, so balancing never needs code changes.

## World and exploration (M3)

- Roblox StreamingEnabled with each region as its own model, so phones only load what is near.
- Waypoints, chests, collectibles, puzzles, guardians hidden in the wild, and a world level that
  scales enemies as the player grows.
- One distinct rule per nation (for example, a day-night cycle that changes what is open).

## Quests and dialogue (M2)

Quests are data: steps, conditions and rewards in config, with dialogue by line id so text can
be translated. The server tracks progress; the client shows the tracker and cutscenes.

## Co-op (M3)

Up to four players in one world. The host's world state is used; each player keeps their own
progress and loot. Combat and reactions work the same with mixed parties.

## UI (M1 onward)

One controller per screen, with shared components (buttons, tooltips, item cards) and
layouts that work on phone, PC and console.

## Anti-exploit (all milestones)

- Every remote validates argument types and ranges.
- Rate limits per player on every request.
- The server owns all outcomes: currency, drops, wishes, damage, cooldowns and quest progress.
- Suspicious values are logged for review instead of silently ignored.
