# Architecture

This page covers how the code is organised. Each system is explained in detail in
[systems/](systems/README.md).

## Where code runs

| Folder | Becomes in Studio | Runs on |
| --- | --- | --- |
| `src/server` | `ServerScriptService.Server` | Server only |
| `src/client` | `StarterPlayer.StarterPlayerScripts.Client` | Each player's device |
| `src/shared` | `ReplicatedStorage.Shared` | Both |
| `Packages` | `ReplicatedStorage.Packages` | Both (Wally packages) |

The mapping lives in `default.project.json`.

## Services and controllers

`src/server/init.server.luau` requires every ModuleScript in `Services/`, calls `Init` on all of
them, then `Start` on all of them. The client does the same with `Controllers/`.

- `Init`: set up state and remotes. Do not yield and do not call other services.
- `Start`: connect events, start loops, call other services.

A service is a plain table. There is no framework, so there is nothing to learn beyond Luau.

## Networking

All remotes are created through `Shared.Net`, with names listed in `Net.Names`. The client asks;
the server validates every argument and decides. Anything that affects progression or currency
(damage dealt, drops, rolls, quest completion) is calculated on the server.

## Player data

`PlayerDataService` opens each player's profile with ProfileStore, which session-locks it so it
can't be duplicated or rolled back across servers. It fills missing keys from
`GameConfig.DefaultProfile`, runs `Data/Migrations` for older saves, and ProfileStore autosaves
and saves on leave and shutdown. Other services only use `PlayerDataService.get` and `waitFor`.

When the profile shape changes, bump `GameConfig.DataVersion` and add a migration step.
Details: [systems/player-data.md](systems/player-data.md).

## Gacha

`Shared.Gacha` is pure Luau: banner rates, soft and hard pity, the featured 50/50 and the
published odds. Because it has no Roblox dependencies it is unit tested with Lune
(`tests/Gacha.spec.luau`). `GachaService` is the only place rolls happen, and it spends only
currency earned in game until the paid-random-item checks in
[systems/platform-rules.md](systems/platform-rules.md) are wired into the shop.

## Combat

Combat follows the same split as everything else. The rules are pure modules in
`src/shared/Combat` (`Ability`, `Defense`, `Party`, `Stamina`, `EnemyBrain`) with Lune tests, and
server services apply them:

| Service | Owns |
| --- | --- |
| `CombatService` | Attack, charged, plunge, Technique and Finale requests; Relays, Covers and Pile-Ons |
| `PartyService` | Each player's party, per-hero HP and energy, swaps, the hero weapon |
| `MovementService` | Grip, sprint speed, dodge charges, height history for plunges, speed sampling |
| `EnemyService` | Spawning and running enemies, telegraphs and strikes |
| `ArenaService` | The grey-box test arena when a place has none |
| `DevService` | Studio-only test commands |

Three server helpers in `src/server/Combat` sit between them: `HitResolver` turns one hit on one
enemy into its outcome, `AbilityRunner` plays the steps of Techniques, Finales and Relays, and
`ActionLog` remembers when each player last attacked and dodged.

On the client, `CameraController`, `MovementController`, `CombatController`,
`PartyController` and `HudController` handle input and presentation, and `Client.Effects`
builds every combat effect from parts and UI. Details: [systems/combat.md](systems/combat.md).

## Planned systems

| System | Side | Notes |
| --- | --- | --- |
| Characters and stats | Shared data | Levels, ascension, talents |
| Inventory and gear | Server | Stored in the profile |
| Quests and dialogue | Both | Data-driven, script ids not text in code |
| World streaming | Engine | StreamingEnabled, region models under Workspace |
| Menus | Client | Built in code, following the combat HUD |
