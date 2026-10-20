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

## The trust rule

The client asks; the server decides. Every handler checks the type and range of each argument
before doing anything, and anything that affects progress (damage, drops, wishes, quest
completion, cooldowns) is calculated on the server. The client only plays the result.
