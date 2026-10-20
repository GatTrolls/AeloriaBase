# Roadmap

Farborn is built by a very small team with no budget, so the plan is milestone-based, not
date-based. Each milestone ends with something people can play or look at. Live tracking
happens on the GitHub Project board (see docs/operations/presence-plan.md).

## M0 · Foundation (now)

- [x] Rojo project, toolchain, CI, issue and PR templates
- [x] Player data service (starter) and gacha core with unit tests
- [x] Elemental reaction engine and damage model with unit tests
- [x] Systems and game documentation, credits
- [ ] Art style guide v1 (cel shading on Roblox, outline method, palette per region)
- [ ] Story bible v3 locked for the 1.0 scope (kid/teen audience)
- [ ] Game design document v1: combat, party, elements, progression, economy
- [ ] Roblox group created to own the experience; private test place published

## M1 · Combat vertical slice

Goal: one minute of combat that feels good, in a grey-box arena.

- [ ] Third-person camera, sprint, dodge, climb and glide
- [ ] One playable hero with basic attack chain, skill and burst
- [ ] Party of up to four with instant swap
- [ ] Two elements and one reaction
- [ ] One enemy type with telegraphed attacks, plus hit-stop and damage numbers
- [ ] Server-validated hits and cooldowns

## M2 · Core loop

- [ ] Switch player data to ProfileStore (session locking) and add migrations
- [ ] Character levels, weapons, artifacts/gear, ascension materials
- [ ] Gacha UI with published odds, pity counter and history
- [ ] Policy checks for paid random items wired to the shop
- [ ] Inventory, quest tracker and the first main-story quest in grey-box

## M3 · First region

- [ ] Starter region blocked out with StreamingEnabled
- [ ] Waypoints, collectibles, chests, puzzles, one dungeon, one world boss
- [ ] Four playable heroes, three enemy families
- [ ] Mobile controls and performance budget met on a mid-range phone

## M4 · Closed alpha

- [ ] Friends-and-community testers via a private test place
- [ ] Bug reporting from in game to GitHub issues
- [ ] Analytics dashboards (Roblox Creator Analytics) for retention and funnel
- [ ] Maturity and compliance questionnaire completed

## M5 · Open beta and 1.0

- [ ] Public launch of the starter region and prologue
- [ ] Monetization live (passes, monthly card, cosmetics) within Roblox rules
- [ ] Live-ops calendar: banners, events and version updates every 6 weeks
