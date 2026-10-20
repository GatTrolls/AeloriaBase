# Aeloria

An anime open-world action RPG for Roblox, in the spirit of Genshin Impact and Wuthering Waves:
explore a hand-built world, collect a cast of heroes, swap between them mid-fight and chain
elemental reactions.

> **Status:** pre-production. The code here is the foundation (toolchain, project layout, save
> system and gacha core). Nothing is playable yet. See the [roadmap](ROADMAP.md).

"Aeloria" is the working title of the world. The story, cast and names are still being written
and are kept out of this public repository until they are ready to share.

## Quick start

You need [Roblox Studio](https://create.roblox.com/) and [Rokit](https://github.com/rojo-rbx/rokit).

```sh
rokit install          # installs Rojo, Wally, StyLua, Selene and Lune at the pinned versions
wally install          # installs Luau packages (none yet)
rojo serve             # then click "Connect" in the Rojo plugin inside Studio
```

Install the Rojo Studio plugin with `rojo plugin install`. Full setup, including VS Code and the
Claude Studio connection, is in [docs/workflow.md](docs/workflow.md).

| Command | What it does |
| --- | --- |
| `rojo serve` | Live-syncs `src/` into an open Studio place |
| `rojo build -o build/Aeloria.rbxl` | Builds a place file from the repo |
| `lune run tests/run` | Runs the pure-Luau unit tests |
| `stylua src tests` | Formats code |
| `selene src` | Lints code |

## Repository layout

```
src/
  server/      Server scripts. Services/ holds one module per game system.
  client/      Client scripts. Controllers/ holds one module per client system.
  shared/      Code and config both sides can read (Gacha, Net, Config/).
tests/         Lune unit tests for pure modules.
docs/          Architecture, workflow, design index, operations and the dev log.
site/          The official website (static, free GitHub Pages hosting).
.github/       Issue and pull request templates, CI.
```

## Contributing

Read [CONTRIBUTING.md](CONTRIBUTING.md). Every change goes through a pull request, and CI must
pass (format, lint, tests, Rojo build).

## License

- **Code** in this repository is licensed under the [Apache License 2.0](LICENSE).
- **Game content** (story, characters, names, artwork, models, animations, music and sound) is
  © the Aeloria team, all rights reserved, and is not covered by the Apache License, even when
  it is stored in this repository.

Aeloria is not affiliated with HoYoverse, Kuro Games or Roblox Corporation.
