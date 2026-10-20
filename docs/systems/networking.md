# Networking

**Status:** built · **Code:** `src/shared/Net.luau`

## How it works

All remotes are listed once in `Net.Names`. The server creates them in a `Remotes` folder;
clients wait for them. Nobody types a remote name as a string anywhere else, so a typo is caught
in one place.

```lua
Net.func(Net.Names.RequestPull).OnServerInvoke = handlePull  -- server
local result = Net.func(Net.Names.RequestPull):InvokeServer("standard", 10)  -- client
```

| Remote | Type | Purpose |
| --- | --- | --- |
| `RequestPull` | RemoteFunction | Make 1 or 10 wishes on a banner |
| `GetBannerOdds` | RemoteFunction | Get the published odds for a banner |
| `ProfileChanged` | RemoteEvent | Push a profile snapshot to the client |
| `CombatAction` | RemoteEvent | Ask to attack, charge, plunge, or use a Technique or Finale, with an aim direction |
| `CombatFeedback` | RemoteEvent | Tell every client about confirmed actions, hits, strikes, staggers and swaps |
| `MoveIntent` | RemoteEvent | Ask to sprint, dodge, climb, leap or glide |
| `MoveState` | RemoteEvent | Grip updates, dodges left, refusals and exhaustion for one player |
| `PartySwap` | RemoteEvent | Ask to swap to a party slot |
| `PartyState` | RemoteEvent | Push a party snapshot: HP, shields, energy and cooldowns |

Combat, movement and swap requests are rate limited per player with `Shared.RateLimit` before
any other work is done.

## The trust rule

The client asks; the server decides. Every handler checks the type and range of each argument
before doing anything, and anything that affects progress (damage, drops, wishes, quest
completion, cooldowns) is calculated on the server. The client only plays the result.
