# Roblox rules we design around

Rules change; re-check the Roblox Creator Docs and Community Standards before each milestone.
Last reviewed 2026-10-20.

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

- The target audience is kids and teens, so aim for a **Minimal** or **Mild** content maturity
  label. Complete the Maturity & Compliance Questionnaire before the experience is public.
- Keep violence stylised (no blood, no gore), no romance beyond friendship, no real-world
  religion, gambling imagery or alcohol focus.

## Text, chat and user content

- Any text one player types that others can see (party names, notes, mail) must go through
  `TextService` filtering on the server.
- Do not collect personal information. No in-game forms that ask for email, age, socials or
  location.

## Social links and off-platform

- Use the experience's **Social Links** setting for Discord, YouTube, X and similar. Roblox only
  shows them to eligible users.
- In-game mentions of external sites must check `PolicyInfo.AllowedExternalLinkReferences`.
- Do not reward players for actions off Roblox (following accounts, joining Discord) unless the
  current rules clearly allow it. Promo codes posted on socials are the usual safe pattern.

## Originality

- "Inspired by" is fine; copying is not. No names, characters, UI art, icons, music or models
  from Genshin Impact, Wuthering Waves or other games.
- Every asset in a PR needs a source and license note.
