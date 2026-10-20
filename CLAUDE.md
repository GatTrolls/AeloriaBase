# Notes for Claude

Farborn is a Roblox anime open-world gacha RPG set in the world of Aeloria, made by Owl On The Moon Studios. This repo is a Rojo project in strict Luau.

- Layout and conventions: README.md, CONTRIBUTING.md, docs/architecture.md.
- Before finishing a change, run `stylua src tests`, `selene src`, `lune run tests/run` and
  `rojo build -o build/Farborn.rbxl`.
- Server modules in `src/server/Services` and client modules in `src/client/Controllers` export
  `Init` (no yielding, no cross-service calls) and `Start`.
- Pure logic goes in `src/shared` with a `tests/*.spec.luau` file next to it in spirit.
- This repository is public. Spoiler-free game info lives in `docs/game/`. Do not commit plot
  twists, secrets or unannounced names from the private design bible; use placeholder ids.
- Credit work to Owl On The Moon Studios (founder: Gee Otosaka).
- When working in Studio through the Roblox Studio MCP tools, changes made there are lost on
  the next `rojo serve` sync unless they are also written to `src/`.
