# Platform rules

**Status:** applies to every system · How Farborn's code follows Roblox's rules for random items,
content and player safety. Last reviewed 2026-10-20.

## Gacha and paid random items

- **Show the odds before purchase.** Any random item that can be bought with Robux, directly or
  through a currency bought with Robux, must show its odds first. The shop renders
  `Gacha.publishedOdds`, including pity rules, never hand-typed numbers.
- **Respect regional restrictions.** `PolicyService:GetPolicyInfoForPlayerAsync` returns
  `ArePaidRandomItemsRestricted`. When it is true, the player may not use Robux-bought currency
  on wishes. `GachaService.canUsePaidRandomItems` wraps this, and it fails closed if the lookup
  errors.
- **Keep earned and bought currency apart in data.** The profile stores `wishCurrency` (earned)
  and `premium` (bought) separately so the restriction can actually be enforced.
- Show a visible pity counter and wish history. It is good practice and builds trust with
  players and parents.

## Age rating

- The target audience is kids and teens, so content is built for a **Minimal** or **Mild**
  Roblox maturity label.
- Keep violence stylised (no blood, no gore), no romance beyond friendship, no real-world
  religion, gambling imagery or alcohol focus.

## Text, chat and user content

- Any text one player types that others can see (party names, notes, mail) must go through
  `TextService` filtering on the server.
- Do not collect personal information. No in-game forms that ask for email, age, socials or
  location.

## Originality

- "Inspired by" is fine; copying is not. No names, characters, UI art, icons, music or models
  from Genshin Impact, Wuthering Waves or other games.
- Every asset in a PR needs a source and license note.
