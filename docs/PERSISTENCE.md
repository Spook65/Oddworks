# ODDWORKS Persistence Foundation

## Authority Boundary

`PersistenceService` is the only ODDWORKS service that talks to ProfileStore. It loads and sanitizes durable data, initializes `PlayerStateService`, and keeps `Profile.Data` synchronized from defensive PlayerState snapshots. Gameplay services continue using PlayerState APIs and never access ProfileStore directly.

PlayerState existence is the gameplay-ready boundary. Before a profile session is acquired, no PlayerState exists, so crafting, Hype production, display reconciliation, plot assignment, and state replication fail closed or wait for the initial state notification.

## Dependency

ODDWORKS uses the official `lm-loleris/profilestore@1.0.3` Wally package from [MadStudioRoblox/ProfileStore](https://github.com/MadStudioRoblox/ProfileStore). The library is licensed under Apache-2.0 and its source is not modified.

## Save Schema v1

```text
SchemaVersion = 1
Scrap = 0
Hype = 0
WorkshopLevel = 1
OwnedOddlings = {
    Toastmarshal = 0,
    Conejurer = 0,
}
```

The canonical save-payload builder copies only these fields from an authoritative PlayerState snapshot. Loaded numbers must be finite, non-negative, safe integers. Workshop levels must exist in `WorkshopLevels`; Oddling counts are accepted only for configured species. Unknown fields and species never become gameplay authority.

## Intentionally Unsaved

`AssignedPlotId` is session-only because `WorkshopService` assigns a fresh available plot in each server. `UnlockedRecipes` is derived from `WorkshopLevel` by `ProgressionService` and is not stored in schema v1. If recipes later gain independent unlock paths, that decision must be revisited through a schema change.

Physical models, display allocation, HUD state, animation state, runtime containers, Hype timers, and offline timestamps are also excluded. `OddlingDisplayService` reconstructs physical displays from ownership, current workshop capacity, templates, and the newly assigned plot.

## Load Lifecycle

1. ProfileStore acquires a session using a server-generated `Player_<UserId>` key.
2. The request cancels if the player leaves while loading; session stealing is never requested.
3. Stored data is reconciled, migrated, validated, and copied into canonical schema v1.
4. `PlayerStateService.InitializePlayer()` creates private authoritative state.
5. The initial state notification drives progression, plot assignment, display reconstruction, and sanitized HUD replication.

If acquisition fails, the player is removed with a retry message instead of receiving temporary defaults. If `OnSessionEnd` reports that the server lost ownership, PlayerState is removed and the connected player is removed so unsavable gameplay cannot continue.

## Save And Shutdown Lifecycle

Each PlayerState notification refreshes only the in-memory `Profile.Data` payload. ProfileStore controls autosave timing; ODDWORKS does not issue a DataStore write on every Hype tick.

On player departure, the latest snapshot is copied and `Profile:EndSession()` performs the final save/release. ProfileStore owns its documented shutdown handling. ODDWORKS uses `Profile.OnLastSave` to refresh the payload synchronously before ProfileStore's final shutdown save and does not add a competing `BindToClose` routine.

## Environment Isolation

Store names and environment selection are centralized in `src/server/Config/PersistenceConfig.luau`.

- Studio: `ODDWORKS_STUDIO_MOCK_PlayerData_v1` through `ProfileStore.Mock`. Studio never touches Roblox DataStores, even when API Services are enabled.
- Internal test: `ODDWORKS_TEST_PlayerData_v1`, only when `game.GameId == 10766404161` for **ODDWORKS - INTERNAL TEST**.
- Future production: `ODDWORKS_PlayerData_v1` is reserved but has no selectable runtime path in Pass 11.

Real restart/rejoin persistence testing must occur in the separately published internal-test experience, not Studio. Studio Mock data disappears when its server shuts down.

## Schema Versioning

`migrateSaveData()` is the single normalization entry point. Pass 11 supports schema v1 and safely defaults malformed v1 fields. Saves with a newer schema version are rejected instead of overwritten. A later v2 pass should add an explicit v1-to-v2 transformation here.

## No Offline Production

Saved Hype is restored exactly. No elapsed-time or offline-production reward is calculated. HypeService starts fresh runtime timers after physical displays reconstruct in the new server.

## Developer Harness

No destructive save commands are registered. Existing Studio commands may arrange Mock scenarios through production PlayerState APIs, and `ow-state` can inspect the resulting authoritative state. Dev grants remain setup tools, not proof that saving, production, or economy mechanics worked.
