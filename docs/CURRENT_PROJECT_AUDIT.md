# CURRENT_PROJECT_AUDIT

## Canonicalization Resolution

Follow-up cleanup established the repository root as the sole canonical Rojo project. The duplicate `my-new-game/**` project tree was removed after confirming it was not a nested Git repository and its checked source files were byte-for-byte duplicates of root `src/**`. The stale generated `build.rbxlx` artifact was removed from source control and ignored with a narrow `/build.rbxlx` rule.

## 1. Repository State

Repository root: `/Users/bhann/Documents/Roblox Project`.

The repository contains two Rojo-style project trees:

- Root project: `default.project.json` plus `src/**`.
- Nested project: `my-new-game/default.project.json` plus `my-new-game/src/**`.

`my-new-game` is inside the same Git repository as the root project. It is not a separate repository.

Git history shows both project files and both source trees were added together in the first commit, `1cad8d5 Set up Roblox project`. The repository does not include a note explaining why both were created. Based on the identical scaffold shape, this appears to be a duplicated Rojo project scaffold rather than two intentionally different games.

Current repository state is not clean. At audit time, these files were modified relative to `HEAD`:

- `default.project.json`
- `my-new-game/default.project.json`
- `my-new-game/src/server/init.server.luau`
- `my-new-game/src/shared/GameConfig.luau`
- `src/server/init.server.luau`
- `src/shared/GameConfig.luau`

No source or project files were modified during this audit pass. This audit created only `docs/CURRENT_PROJECT_AUDIT.md`.

## 2. Git State

Current branch: `main`.

Upstream branch: `origin/main`.

Configured remote:

- `origin https://github.com/Spook65/Oddworks.git` for fetch.
- `origin https://github.com/Spook65/Oddworks.git` for push.

Current `HEAD`: `970f497 Fixed server script crashing`, matching `origin/main`.

Configured Git author in this repository:

- Name: `Spook65`
- Email: `brandon.hann65@gmail.com`

Nested `.git` directories: only `./.git` exists. No nested `.git` directory was found under `my-new-game`.

Tracked generated/build artifact: `build.rbxlx` is tracked. It is a small text-format Roblox place file and appears stale because it still contains the original hello-world scripts. The `.gitignore` files ignore `/Roblox Project.rbxlx`, `/my-new-game.rbxlx`, lock files, and `sourcemap.json`, but they do not ignore `build.rbxlx`.

## 3. Root Rojo Project

File: `default.project.json`.

Project name: `Roblox Project`.

Controlled services:

- `ReplicatedStorage`
- `ServerScriptService`
- `StarterPlayer`
- `Workspace`
- `Lighting`
- `SoundService`

Filesystem mappings, relative to the repository root:

- `ReplicatedStorage.Shared -> src/shared`
- `ServerScriptService.Server -> src/server`
- `StarterPlayer.StarterPlayerScripts.Client -> src/client`

Workspace contents represented by Rojo:

- `Baseplate`
- `OddworksArena`

`Workspace.OddworksArena` is represented in the root project. It is a `Folder` with persistent edit-mode children for the prototype arena.

## 4. my-new-game Rojo Project

File: `my-new-game/default.project.json`.

Project name: `my-new-game`.

Controlled services:

- `ReplicatedStorage`
- `ServerScriptService`
- `StarterPlayer`
- `Workspace`
- `Lighting`
- `SoundService`

Filesystem mappings, relative to `my-new-game/`:

- `ReplicatedStorage.Shared -> my-new-game/src/shared`
- `ServerScriptService.Server -> my-new-game/src/server`
- `StarterPlayer.StarterPlayerScripts.Client -> my-new-game/src/client`

Workspace contents represented by Rojo:

- `Baseplate`
- `OddworksArena`

`Workspace.OddworksArena` is represented in this project too.

The two Rojo project files are not byte-for-byte identical because their top-level `name` values differ. Apart from the top-level name, their JSON contents are identical at audit time.

Because the path strings are the same but resolved from different project directories, the two project files map to different absolute source trees even though those source trees currently contain identical files.

## 5. Duplicate Source Comparison

Compared source pairs:

- `src/server/init.server.luau` and `my-new-game/src/server/init.server.luau`: byte-for-byte identical.
- `src/client/init.client.luau` and `my-new-game/src/client/init.client.luau`: byte-for-byte identical.
- `src/shared/GameConfig.luau` and `my-new-game/src/shared/GameConfig.luau`: byte-for-byte identical.
- `src/shared/Hello.luau` and `my-new-game/src/shared/Hello.luau`: byte-for-byte identical.

At audit time, the duplicated source trees are byte-for-byte duplicates for the checked files. They do not currently represent separate game implementations.

## 6. Current Roblox Studio Hierarchy

Roblox Studio integration reported one connected Studio instance:

- Studio id: `e9557e8a-5591-4785-8c39-6a20771bfe82`
- Name: `Place1`

Studio was inspected in Edit mode and Play mode.

Edit-mode hierarchy includes:

- `Workspace.OddworksArena`
- `ReplicatedStorage.Shared.Hello`
- `ReplicatedStorage.Shared.GameConfig`
- `ServerScriptService.Server`
- `StarterPlayer.StarterPlayerScripts.Client`

`Workspace.OddworksArena` currently contains persistent objects including:

- Floors: `Start Floor`, `Training Floor`, `Vault Floor`
- Walls and frames for start, training, access door, and vault areas
- Doors: `Access Door`, `Vault Door`
- Interaction/gameplay markers: `Keycard`, `Patrol Bot`, `Checkpoint`, `Finish Pad`, `PlayerSpawn`
- `EnergyCores` folder with `Energy Core A` through `Energy Core F`
- `Guide` model with primitive body parts

After a short Play test was stopped, `Workspace.OddworksArena` still existed in Edit mode, confirming the arena is now persistent rather than Play-only.

## 7. Current Prototype Architecture

The current prototype is a keycard/core arena. It is not the intended production ODDWORKS game.

Persistent Edit-mode ownership:

- `default.project.json` and `my-new-game/default.project.json` define `Workspace.OddworksArena`.
- Arena geometry, doors, keycard, cores, guide body parts, patrol bot, checkpoint, finish pad, and spawn are now Rojo-managed persistent objects.

Runtime-only objects:

- `ReplicatedStorage.OddworksRemotes`
- `StateUpdate`, `Notice`, and `StateRequest` RemoteEvents
- `ProximityPrompt` objects on doors, keycard, and guide
- `PointLight` objects on cores and patrol bot
- Guide `Humanoid` and `Nameplate`
- touch transmitters created by touched connections
- per-player `leaderstats`
- per-player HUD under `PlayerGui`

Server script responsibilities:

- Ensures the arena exists and fills missing pieces when running.
- Attaches door, keycard, core, guide, patrol, checkpoint, and finish behavior.
- Owns player progression state in memory.
- Owns leaderstats for `Cores` and `Wins`.
- Sends UI state and notices to clients.
- Handles the `StateRequest` handshake so the HUD initializes reliably.

Client script responsibilities:

- Builds `OddworksHud`.
- Displays objective, core count, keycard status, and notice messages.
- Requests initial state by firing `StateRequest`.
- Does not directly mutate gameplay progression.

## 8. Studio/Codex Integration Capabilities

Verified during this audit:

- List connected Roblox Studio instances.
- Read current Studio mode and available DataModels.
- Inspect Edit and Play DataModel hierarchy.
- Inspect instance properties.
- Read Studio Output/errors.
- Start a Play test.
- Stop a Play test.

Exposed by available tools, but not used for production edits during this audit:

- Execute Luau in Studio.
- Search or read script contents from Studio.
- Create or modify Studio scripts.
- Navigate the local test character.
- Insert Roblox assets by asset id.
- Upload images.
- Generate procedural primitive-part models.
- Fetch Roblox documentation through the Roblox docs helper.

Rojo relationship:

- The user's screenshot showed the Rojo panel connected to a project named `Roblox Project` at `localhost:34872`.
- The root project's top-level name is `Roblox Project`; the nested project's top-level name is `my-new-game`.
- Therefore the active Rojo source appears to be the root project, not `my-new-game`.
- The exact Rojo server process working directory could not be verified from the available shell because process listing failed in the sandbox.
- Current Studio Output also contained a Rojo WebSocket disconnect warning after inspection. If future changes stop syncing, reconnect or restart Rojo.

## 9. Security Observations

The current prototype mostly keeps progression server-owned:

- Core collection is handled by server-side `Touched` connections.
- Keycard pickup is handled by a server-side `ProximityPrompt`.
- Doors validate server-side in-memory player state before opening.
- The client HUD only renders state and fires an initial `StateRequest`.

Prototype security concerns to preserve for the later security contract:

- `StateRequest` is not rate-limited. It appears read-only, but spam could still cause avoidable server work.
- Door, keycard, guide, and checkpoint interactions are prototype-level and do not yet use a shared validation/rate-limit layer.
- All progression is in-memory only and resets when players leave or the server restarts.
- No server-side persistence, inventory authority model, economy validation, or trade/monetization validation exists.
- No DataStoreService usage exists, which is appropriate for the current prototype but not enough for production.

No monetization system exists. Future ODDWORKS work should preserve the stated constraints: original characters, no copyrighted meme/IP dependency, and no paid random item/gacha MVP.

## 10. Secrets/Credential Check

Filename-only secret scans were run against repository files using patterns for tokens, passwords, API keys, cookies, Roblox authentication material, and private keys.

No suspicious tracked files were found by those scans.

No secret values were printed during the audit.

Limitations:

- Browser sessions, local Roblox Studio account state, system keychains, and untracked files outside the repository were not inspected.
- The scan is pattern-based and cannot prove that no secret exists under an unusual name or encoding.

## 11. Verification Performed

Repository/Git verification:

- `git rev-parse --show-toplevel`
- `git branch --show-current`
- `git rev-parse --abbrev-ref --symbolic-full-name @{u}`
- `git remote -v`
- `git status --short --branch`
- `git -C my-new-game rev-parse --show-toplevel`
- nested `.git` directory search
- `git ls-files`
- tracked artifact search
- duplicate file comparisons with `cmp`, `diff`, and `shasum`
- `git log --oneline --name-status`
- filename-only secret scans

Rojo verification:

- `rojo build -o /tmp/oddworks-root-test.rbxlx` passed.
- `rojo build -o /tmp/oddworks-my-new-game-test.rbxlx` passed.
- `git diff --check` passed.

Studio verification:

- Confirmed Studio instance `Place1`.
- Confirmed Edit mode hierarchy includes persistent `Workspace.OddworksArena`.
- Ran a short Play test.
- Confirmed no console output during the Play test.
- Confirmed runtime remotes exist in Play mode.
- Confirmed HUD objective text initializes to `Objective: Find the keycard`.
- Confirmed runtime prompts/lights/touch objects attach in Play mode.
- Stopped Play mode.
- Confirmed `Workspace.OddworksArena` remains in Edit mode after stopping.

Tool availability verification:

- `rojo` exists at `/Users/bhann/.aftman/bin/rojo`.
- `luau`, `luau-lsp`, and `selene` were not found on PATH.

## 12. Verification Not Performed

No migration, deletion, or source reconciliation was performed.

No Roblox production gameplay for ODDWORKS was implemented.

No DataStore, monetization, economy, crafting, collection, display, upgrade, or character systems were added.

No commit or push was performed.

No full gameplay walkthrough was performed. The Play test verified startup, HUD initialization, remotes, prompts, and runtime attachments only.

No standalone Luau static analysis was performed because `luau`, `luau-lsp`, and `selene` were not available on PATH.

The exact Rojo server process working directory was not verified because process listing was unavailable in the sandbox.

## 13. Recommended Canonical Project

Recommended canonical project: the repository root project.

Reasons:

- It is the Git repository root.
- Git remote, branch, and project-level files live at the root.
- The Rojo panel shown by the user was connected to a project named `Roblox Project`, which matches root `default.project.json`.
- `my-new-game` is not a separate Git repository.
- The source trees are currently duplicates, so keeping both active increases future drift risk.

Do not delete or merge `my-new-game` during this audit. The recommendation is for a later migration/foundation pass.

## 14. Recommended Prototype Preservation Strategy

Before migration, preserve the current prototype as a recoverable reference.

Recommended preservation approach:

- Commit this audit first if it is accurate.
- Commit or otherwise snapshot the current prototype state before deleting, moving, or consolidating files.
- Treat `Workspace.OddworksArena` as a disposable proof-of-integration prototype, not the production ODDWORKS foundation.
- Keep notes on the successful integration behaviors: Rojo sync, persistent Workspace objects, server-owned interactions, HUD state handshake, Studio inspection, and Play test workflow.
- Remove or untrack stale generated artifacts such as `build.rbxlx` only in a later explicit cleanup pass.

The intended production loop to preserve for planning is: collect -> craft -> display -> earn -> upgrade -> flex, using original absurd collectible characters.

## 15. Exact Recommended Next Pass

Smallest safe next migration/foundation pass:

1. Commit `docs/CURRENT_PROJECT_AUDIT.md` with message `docs: audit existing Roblox prototype and project structure`.
2. Confirm with the user that the repository root should become canonical.
3. Create a backup commit or tag for the current prototype state.
4. Update documentation to mark `my-new-game` as duplicate or archive it, without deleting it until explicitly approved.
5. Decide whether `build.rbxlx` should be removed from tracking and ignored going forward.
6. Rename the root Rojo project from `Roblox Project` to `ODDWORKS` if desired.
7. Establish a clean production foundation with one canonical source tree, one Rojo project file, and a short project spec.
8. Create a first ODDWORKS architecture plan for collect -> craft -> display -> earn -> upgrade -> flex, without implementing gameplay until the foundation is clean.

Suggested commit for this audit only:

`docs: audit existing Roblox prototype and project structure`
