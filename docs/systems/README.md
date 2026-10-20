# Systems

The technical design of Farborn, by Owl On The Moon Studios. Each page explains what a system
does, how it works and where its code lives. "Built" means the code is in this repository and
covered by tests; "Designed" means the design is set and the code is next on the roadmap.

| System | Code | Tests | Status |
| --- | --- | --- | --- |
| [Service framework](framework.md) | `src/server/init.server.luau`, `src/client/init.client.luau` | Studio | Built |
| [Networking](networking.md) | `src/shared/Net.luau` | Studio | Built |
| [Player data](player-data.md) | `src/server/Services/PlayerDataService.luau` | Studio | Built (starter) |
| [Wish system](wish-system.md) | `src/shared/Gacha.luau`, `src/server/Services/GachaService.luau` | `tests/Gacha.spec.luau` | Built |
| [Elemental reactions](elemental-reactions.md) | `src/shared/Elements.luau`, `src/shared/Config/ElementConfig.luau`, `src/server/Combat/HitResolver.luau` | `tests/Elements.spec.luau` | Built |
| [Damage model](damage-model.md) | `src/shared/Damage.luau` | `tests/Damage.spec.luau` | Built |
| [Combat](combat.md) | `src/server/Services/CombatService.luau`, `src/server/Combat/`, `src/shared/Combat/Ability.luau`, `src/shared/Combat/Defense.luau`, `src/client/Controllers/CombatController.luau` | `tests/Ability.spec.luau`, `tests/Defense.spec.luau` | Built |
| [Party and swap](party.md) | `src/shared/Combat/Party.luau`, `src/server/Services/PartyService.luau` | `tests/Party.spec.luau` | Built |
| [Movement and camera](movement-and-camera.md) | `src/shared/Combat/Stamina.luau`, `src/shared/Combat/Defense.luau`, `src/server/Services/MovementService.luau`, `src/client/Controllers/CameraController.luau` | `tests/Stamina.spec.luau`, `tests/Defense.spec.luau` | Built |
| [Enemy AI](enemy-ai.md) | `src/shared/Combat/EnemyBrain.luau`, `src/server/Services/EnemyService.luau` | `tests/EnemyBrain.spec.luau` | Built |
| [Platform rules](platform-rules.md) | `GachaService`, `PlayerDataService` | | Applied |
| [Planned systems](planned.md) | Progression, world, quests, co-op, menus, anti-exploit | | Designed |

## How the pieces fit

```mermaid
flowchart LR
    subgraph Client
        C[Controllers] -->|requests| R
        FX[Animation, VFX, UI]
    end
    R[(Remotes via Net)] --> S
    subgraph Server
        S[Services] --> G[Gacha]
        S --> E[Elements]
        S --> D[Damage]
        S --> C2[Ability, Party, Stamina, EnemyBrain]
        S --> P[(Player data)]
    end
    S -->|results| R --> FX
```

The client asks and plays the feedback; the server checks every request and decides the outcome.
Everything in the middle column (Gacha, Elements, Damage and the combat modules) is pure Luau with no Roblox APIs, which
is what lets it run in the unit tests.
