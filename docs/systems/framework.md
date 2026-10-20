# Service framework

**Status:** built · **Code:** `src/server/init.server.luau`, `src/client/init.client.luau`

A lightweight, framework-free way to load every game system in a fixed order.

## How it works

1. The entry script requires every ModuleScript in `Services/` (server) or `Controllers/`
   (client).
2. It calls `Init` on all of them. Init sets up state and remotes. It must not yield or call
   other services, so load order never matters.
3. It calls `Start` on all of them, each in its own thread. Start connects events, starts loops
   and may call other services.

```lua
local MyService = {}

function MyService:Init()
	-- create remotes, read config
end

function MyService:Start()
	-- connect events, use other services
end

return MyService
```

## Why this design

- **No framework to learn.** A service is a plain table; there is no dependency injection or
  magic globals.
- **No load-order bugs.** Two phases mean any service can depend on any other in Start.
- **Fault isolation.** Each Start runs in its own thread, so one failing system does not stop
  the rest from starting.
