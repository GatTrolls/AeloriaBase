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

`PlayerDataService` loads a profile on join, fills missing keys from
`GameConfig.DefaultProfile`, autosaves and saves on leave and shutdown. It is a starter version
without session locking. Before the closed alpha it must move to ProfileStore so data cannot be
duplicated or rolled back across servers. Keep using `PlayerDataService.get` and `waitFor`, so
the swap does not touch other services.

When the profile shape changes, bump `GameConfig.DataVersion` and add a migration step.

## Gacha

`Shared.Gacha` is pure Luau: banner rates, soft and hard pity, the featured 50/50 and the
published odds. Because it has no Roblox dependencies it is unit tested with Lune
(`tests/Gacha.spec.luau`). `GachaService` is the only place rolls happen, and it spends only
currency earned in game until the paid-random-item checks in
[operations/compliance.md](operations/compliance.md) are wired into the shop.

## Planned systems

| System | Side | Notes |
| --- | --- | --- |
| Combat | Server authoritative hits, client prediction for feel | Hitboxes via spatial queries, hit-stop and VFX on client |
| Party and swap | Both | Up to 4 heroes, swap cooldown in config |
| Elements and reactions | Shared data, server resolves | Reaction table as config |
| Characters and stats | Shared data | Levels, ascension, talents |
| Inventory and gear | Server | Stored in the profile |
| Quests and dialogue | Both | Data-driven, script ids not text in code |
| World streaming | Engine | StreamingEnabled, region models under Workspace |
| UI | Client | Built in code or with a UI library chosen in M1 |
