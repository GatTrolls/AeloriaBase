# Workflow

## One-time setup

1. Install Roblox Studio and sign in.
2. Install [Rokit](https://github.com/rojo-rbx/rokit), then in this folder run `rokit install`.
3. Run `rojo plugin install` to add the Rojo plugin to Studio.
4. Optional: VS Code with the recommended extensions in `.vscode/extensions.json`
   (Luau LSP, StyLua, Selene, Rojo).
5. Run `wally install` whenever `wally.toml` changes.

## Daily loop

1. `git pull` and branch from `main`.
2. `rojo serve`, open the dev place in Studio, click Connect in the Rojo plugin.
3. Edit code in `src/`; Studio updates live. Build maps, models and terrain in Studio.
4. Before pushing: `stylua src tests`, `selene src`, `lune run tests/run`.
5. Open a pull request and fill in the template.

## What lives where

| Thing | Source of truth |
| --- | --- |
| Scripts and config | This repo (`src/`) |
| Terrain, maps, big models | The Studio place file, saved to Roblox; export key models to `assets/` as `.rbxm` when they change |
| Meshes, textures, audio | Uploaded to Roblox under the group; keep source files (`.blend`, `.psd`) in cloud storage, not git |
| Story, design, art direction | The design documents listed in `docs/design/README.md` |

## Working with Claude in Studio

Claude can run Luau, edit scripts, read the game tree and playtest through the Roblox Studio
connection. Scripts edited only inside Studio are overwritten by the next Rojo sync, so any
script change must also land in `src/`. Use Studio-side edits for building and inspecting, and
the repo for code.

## Places

| Place | Purpose |
| --- | --- |
| Dev | Day-to-day work, anyone on the team |
| Test | Private playtests, published from `main` |
| Live | The public experience, published from a release tag |

All three belong to the Roblox group, not a personal account, so access can be shared and the
game does not depend on one person's login.

## Releases

Tag `main` as `v0.x.y` when publishing to Test or Live, and write a dev log post for each
public update.
