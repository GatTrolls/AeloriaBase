<div align="center">

# Farborn

**An anime open-world action RPG for Roblox, set in the world of Aeloria.**

Created by **Owl On The Moon Studios** · Founder and creator: **Gee Otosaka** ([@GatTrolls](https://github.com/GatTrolls))

[Game](docs/game/README.md) · [Systems](docs/systems/README.md) · [Roadmap](ROADMAP.md) · [Dev log](docs/devlog/README.md) · [Credits](CREDITS.md)

</div>

---

> You wake up at a campfire with no memories, take a job for some quick coin, and steal the
> wrong thing: the power of a god whose kingdom fell 500 years ago.

Farborn is an original open-world action RPG in the spirit of Genshin Impact and Wuthering
Waves, made for Roblox and for players aged roughly 10 and up. Explore six nations, build a party
of four heroes, swap between them mid-fight and chain elements into reactions.

**Status:** pre-production (milestone M0). The core engine systems below are built and tested;
nothing is playable yet. *Farborn* is the working title.

## Systems at a glance

Every system is designed and built by Owl On The Moon Studios. Full write-ups are in
[docs/systems](docs/systems/README.md).

| System | What it does | Status |
| --- | --- | --- |
| [Service framework](docs/systems/framework.md) | Two-phase Init/Start loading for server services and client controllers | Built |
| [Networking](docs/systems/networking.md) | One registry for all remotes; server-authoritative by rule | Built |
| [Player data](docs/systems/player-data.md) | Profiles with retries, reconcile, autosave and safe shutdown | Built (starter) |
| [Wish system](docs/systems/wish-system.md) | Banners, soft and hard pity, featured 50/50, published odds, regional policy checks | Built, tested |
| [Elemental reactions](docs/systems/elemental-reactions.md) | Aura gauges with decay, 9 reactions, internal cooldowns | Built, tested |
| [Damage model](docs/systems/damage-model.md) | Level-scaled defense, resistance curves, crits, amplify and transform damage | Built, tested |
| [Combat, party, movement, AI and more](docs/systems/planned.md) | The rest of the game's systems, specified ahead of build | Designed |

## Tech stack

Luau in strict mode, synced into Roblox Studio with [Rojo](https://rojo.space). Pure game logic
lives in `src/shared` with no Roblox dependencies, so it is unit tested outside Studio with
[Lune](https://lune-org.github.io/docs). Every pull request is formatted (StyLua), linted
(Selene), tested (Lune) and built into a place file by CI.

```
src/
  server/      Server scripts. Services/ holds one module per game system.
  client/      Client scripts. Controllers/ holds one module per client system.
  shared/      Pure logic and config: Gacha, Elements, Damage, Net, Config/.
tests/         Lune unit tests for everything in shared.
docs/          Game info, system write-ups, roadmap, operations and the dev log.
site/          The official website (static, hosted free on GitHub Pages).
```

## Building it yourself

You need [Roblox Studio](https://create.roblox.com/) and [Rokit](https://github.com/rojo-rbx/rokit).

```sh
rokit install          # Rojo, Wally, StyLua, Selene and Lune at pinned versions
rojo plugin install    # adds the Rojo plugin to Studio
rojo serve             # then click Connect in the Rojo plugin
lune run tests/run     # runs the unit tests
```

Setup details: [docs/workflow.md](docs/workflow.md). Contribution rules: [CONTRIBUTING.md](CONTRIBUTING.md).

## License

- **Code** is licensed under the [Apache License 2.0](LICENSE). See [NOTICE](NOTICE).
- **Game content** (the name Farborn, story, world, characters, names, artwork, models,
  animations, music and sound) is © 2026 Owl On The Moon Studios, all rights reserved, and is
  not covered by the Apache License, even when it is stored in this repository.

Farborn is an independent game. It is not affiliated with HoYoverse, Kuro Games or Roblox
Corporation.
