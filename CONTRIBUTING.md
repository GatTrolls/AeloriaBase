# Contributing to Aeloria

## Workflow

1. Pick or open an issue. Use the templates; they ask for what a reviewer needs.
2. Branch from `main`: `feature/<short-name>`, `fix/<short-name>` or `content/<short-name>`.
3. Keep pull requests small and about one thing. Fill in the PR template.
4. CI must be green before merging: StyLua, Selene, Lune tests and a Rojo build.
5. Squash-merge into `main`. `main` must always build and open in Studio.

## Code rules

- Luau with `--!strict` at the top of every file.
- One system per Service (server) or Controller (client). Shared logic that does not touch
  Roblox APIs goes in `src/shared` so it can be unit tested with Lune.
- The server decides. Never trust numbers sent by a client: damage, currency, rolls, cooldowns.
- Tunable numbers live in `src/shared/Config`, not inline.
- Run `stylua src tests` before committing.

## Content rules

- No story, character or name spoilers in this public repo until they are announced. Keep
  them in the private design documents and refer to them by placeholder id (`hero_placeholder_a`).
- Only commit assets you made or have the right to use. Note the source and license of any
  third-party asset in the PR.
- Aeloria is made for a broad audience including younger players. Keep content in line with
  Roblox's Community Standards and the target age rating in docs/operations/compliance.md.

## Commit messages

Imperative and specific: `Add stamina drain to sprint`, not `stuff` or `fixes`.
