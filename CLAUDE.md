# Notes for Claude

Aeloria is a Roblox anime open-world gacha RPG. This repo is a Rojo project in strict Luau.

- Layout and conventions: README.md, CONTRIBUTING.md, docs/architecture.md.
- Before finishing a change, run `stylua src tests`, `selene src`, `lune run tests/run` and
  `rojo build -o build/Aeloria.rbxl`.
- Server modules in `src/server/Services` and client modules in `src/client/Controllers` export
  `Init` (no yielding, no cross-service calls) and `Start`.
- Pure logic goes in `src/shared` with a `tests/*.spec.luau` file next to it in spirit.
- This repository is public. Do not commit story, character or naming material from the
  private design bible; use placeholder ids.
- When working in Studio through the Roblox Studio MCP tools, changes made there are lost on
  the next `rojo serve` sync unless they are also written to `src/`.
