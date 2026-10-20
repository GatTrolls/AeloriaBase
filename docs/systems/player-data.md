# Player data

**Status:** built (starter) · **Code:** `src/server/Services/PlayerDataService.luau`

## How it works

```mermaid
sequenceDiagram
    participant P as Player
    participant S as PlayerDataService
    participant D as DataStore
    P->>S: joins
    S->>D: GetAsync (up to 5 tries, backing off)
    D-->>S: saved profile or nothing
    S->>S: fill in any new default fields
    Note over S: autosave every 120 s
    P->>S: leaves
    S->>D: UpdateAsync
    Note over S,D: on server shutdown, every profile is saved before close
```

- **Reconcile:** new fields added to `GameConfig.DefaultProfile` appear in old saves
  automatically.
- **Retries:** every DataStore call retries with exponential backoff; if loading still fails,
  the player is asked to rejoin instead of being given an empty save that could overwrite theirs.
- **Versioned:** `GameConfig.DataVersion` is stored with every profile for future migrations.
- **Separate currencies:** earned and bought currency are kept apart so the wish system can
  follow regional rules.

## Next step

Before the closed alpha, storage moves to ProfileStore for session locking, so a player who
hops servers quickly can never duplicate or roll back items. `get` and `waitFor` keep the same
API, so no other system changes.
