# ODDWORKS Studio Developer Harness

The ODDWORKS developer harness uses the official `evaera/Cmdr` package for fast local scenario setup. It is development tooling, not a production admin or cheat system.

## Install Dependencies

The repository pins Wally through Aftman and Cmdr through `wally.lock`.

On macOS, from the repository root:

```sh
aftman install
wally install
```

Wally 0.3.2 reads the committed `wally.lock` during `wally install`; that release does not provide a separate `--locked` flag. `ServerPackages/` is generated from the lockfile and intentionally ignored by Git. Run the install command after a fresh clone and before `rojo build` or Rojo sync.

## Open The Console

1. Start the canonical root Rojo project and connect Roblox Studio.
2. Start a Studio Play or multi-client test.
3. Press `F2` to toggle Cmdr.
4. On a MacBook configured to use F-keys for brightness and media controls, press `fn + F2`.

The activation key is available only in Studio. A server-side `BeforeRun` hook is the actual authorization boundary; hiding the client UI is not treated as security.

## Commands

Use `.` where a required player argument should mean the invoking player.

```text
ow-state [player]
ow-give-scrap <player> <positive integer>
ow-give-hype <player> <positive integer>
ow-give-oddling <player> <speciesId> <positive integer>
ow-advance-workshop [player]
ow-displays [player]
ow-reconcile [player]
```

Examples:

```text
ow-state
ow-give-scrap . 5
ow-give-hype . 10
ow-give-oddling . Toastmarshal 4
ow-advance-workshop
ow-displays
ow-reconcile
```

Only these ODDWORKS commands are registered. Cmdr's bundled admin, debug, utility, and eval-style command suites are not registered.

## Setup Is Not Acceptance Evidence

Developer commands are valid for arranging a test scenario. A bypass never proves the production mechanic it skipped.

For example, `ow-give-hype . 10` can prepare a workshop-upgrade test, but it does not prove that `HypeService` generated 10 Hype. Likewise, `ow-advance-workshop` explicitly bypasses Hype cost and proximity, so it does not verify `WorkshopUpgradeService`.

Use the ordinary player-facing path when recording acceptance evidence for salvage, crafting, Hype generation, upgrades, or progression.

## Roblox Developer Console

Cmdr complements Roblox's `F9` Developer Console; it does not replace it. Continue using `F9` for client/server logs, errors, memory diagnostics, and networking diagnostics.
