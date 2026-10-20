<div align="center">

# Farborn

**An anime open-world action RPG for Roblox, set in the world of Aeloria.**

Created by **Owl On The Moon Studios** · Founder and creator: **Gee Otosaka** ([@GatTrolls](https://github.com/GatTrolls))

[Game](docs/game/README.md) · [Systems](docs/systems/README.md) · [Roadmap](ROADMAP.md) · [Updates](docs/devlog/README.md) · [Credits](CREDITS.md)

</div>

---

> You wake up at a campfire with no memories, take a job for some quick coin, and steal the
> wrong thing: the power of a god whose kingdom fell 500 years ago.

Farborn is an original open-world action RPG in the spirit of Genshin Impact and Wuthering
Waves, made for Roblox and for players aged roughly 10 and up. Explore six nations, build a party
of four heroes, swap between them mid-fight and chain elements into reactions.

**Status:** milestone M1. The combat slice is playable in a grey-box test arena: a party of four,
elemental reactions, movement and the first enemy. *Farborn* is the working title.

## Systems at a glance

Every system is designed and built by Owl On The Moon Studios. Full write-ups are in
[docs/systems](docs/systems/README.md).

| System | What it does | Status |
| --- | --- | --- |
| [Service framework](docs/systems/framework.md) | Two-phase Init/Start loading for server services and client controllers | Built |
| [Networking](docs/systems/networking.md) | One registry for all remotes; server-authoritative by rule | Built |
| [Player data](docs/systems/player-data.md) | Session-locked saves with ProfileStore, reconcile and migrations | Built, tested |
| [Wish system](docs/systems/wish-system.md) | Banners, soft and hard pity, featured 50/50, published odds, regional policy checks | Built, tested |
| [Elemental reactions](docs/systems/elemental-reactions.md) | Statuses that react: nine reactions from Scald to Starburst | Built, tested |
| [Damage model](docs/systems/damage-model.md) | Tunable defence, resistance curves, crits, reaction damage and healing | Built, tested |
| [Combat](docs/systems/combat.md) | Server-confirmed attack chains, Techniques, Finales and Relays built from data; Slips and Lifts | Built, tested |
| [Party and swap](docs/systems/party.md) | Four heroes, instant swaps, Relays, Cover and Pile-On | Built, tested |
| [Movement and camera](docs/systems/movement-and-camera.md) | Sprint, dodge, climb, glide and plunge on server-owned Grip; lock-on camera | Built, tested |
| [Enemy AI](docs/systems/enemy-ai.md) | Telegraphed attacks, attack tokens, flinching grunts, elites with Composure | Built, tested |
| [Platform rules](docs/systems/platform-rules.md) | Regional random-item policy, odds disclosure, text filtering | Applied |
| [Progression, world, quests and more](docs/systems/planned.md) | The rest of the game's systems, specified ahead of build | Designed |

## Tech stack

Luau in strict mode, synced into Roblox Studio with [Rojo](https://rojo.space). Pure game logic
lives in `src/shared` with no Roblox dependencies, so it is unit tested outside Studio with
[Lune](https://lune-org.github.io/docs). Every pull request is formatted (StyLua), linted
(Selene), tested (Lune) and built into a place file by CI.

```
src/
  server/      Server scripts. Services/ holds one module per game system.
  client/      Client scripts. Controllers/ holds one module per client system.
  shared/      Pure logic and config: Gacha, Elements, Damage, Combat/, Net, Config/.
tests/         Lune unit tests for everything in shared.
docs/          Game info, system write-ups and development updates.
site/          The official website (static, hosted free on GitHub Pages).
```

## Who this repository is for

- **Developers** can read how each system works and learn from the code and tests.
- **Contributors** can build Farborn with us; start with [CONTRIBUTING.md](CONTRIBUTING.md).
- **Partners and investors** can see the game, the technology and the [roadmap](ROADMAP.md)
  in one place. Business enquiries: contact Owl On The Moon Studios through
  [@GatTrolls](https://github.com/GatTrolls).

## Using our code

The code is open source under the Apache License 2.0, so you can use it in your own Roblox
games, including commercial ones. Keep the license and [NOTICE](NOTICE) with any copy, and credit
us, for example:

> Systems based on Farborn by Owl On The Moon Studios (github.com/GatTrolls/AeloriaBase)

The game itself (name, story, characters and art) is not open source. See [License](#license).

## Building it yourself

You need [Roblox Studio](https://create.roblox.com/) and [Rokit](https://github.com/rojo-rbx/rokit).

```sh
rokit install          # Rojo, Wally, StyLua, Selene and Lune at pinned versions
wally install          # packages, such as ProfileStore for saves
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
