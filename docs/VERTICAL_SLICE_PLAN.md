# ODDWORKS Vertical Slice 0.1 Technical Plan

## Purpose

This document translates the ODDWORKS production contracts into a small, ordered implementation roadmap. It is a plan, not gameplay code.

Vertical Slice 0.1 must prove:

spawn -> claim workshop plot -> collect Scrap -> craft Toastmarshal -> display Toastmarshal -> earn Hype -> upgrade workshop -> reveal Conejurer -> continue

The slice must stay session-only, server-authoritative, multiplayer-compatible, and free of monetization.

## Contract Inputs

This plan is constrained by:

- [Game Direction](GAME_DIRECTION.md)
- [Art Direction](ART_DIRECTION.md)
- [Security Contract](SECURITY_CONTRACT.md)
- [Monetization Contract](MONETIZATION_CONTRACT.md)
- [Codex Workflow](CODEX_WORKFLOW.md)
- [Current Project Audit](CURRENT_PROJECT_AUDIT.md)

The existing `Workspace.OddworksArena` remains a temporary toolchain-validation prototype until a dedicated retirement pass removes it.

## Vertical Slice Definition

Vertical Slice 0.1 is the smallest playable production loop that demonstrates the full ODDWORKS shape:

1. Player spawns in a compact junkyard/workshop test environment.
2. Server assigns or lets the player claim one available workshop plot.
3. Player collects Scrap from server-owned salvage nodes.
4. Player spends Scrap at a crafting station to create Toastmarshal.
5. Server creates a player-owned Toastmarshal record and physical display.
6. Displayed Toastmarshal generates Hype over time.
7. Player spends Hype on one workshop upgrade.
8. Upgrade reveals Conejurer as the next recipe/unlock goal.
9. Player can continue collecting Scrap and crafting within the session.

Vertical slice complete means:

- two players can join a Studio multi-client test and receive separate workshop ownership,
- Scrap collection is server-authoritative,
- Toastmarshal crafting cost and ownership are validated server-side,
- Toastmarshal appears physically in the player's workshop,
- Hype production is server-authoritative,
- one workshop upgrade can be purchased with server-owned Hype,
- Conejurer becomes visible/unlocked after the upgrade condition,
- the HUD reflects server state without becoming authoritative,
- malformed or spammed client requests are rejected without corrupting state,
- the loop works without persistence, monetization, trading, quests, rebirths, daily rewards, or global leaderboards.

## Proposed Roblox Architecture

Keep the current root Rojo project as the only source of truth.

Planned production layout:

```text
ServerScriptService
└── Server
    ├── bootstrap.server.luau or init.server.luau
    ├── Services
    │   ├── PlayerStateService.luau
    │   ├── WorkshopService.luau
    │   ├── SalvageService.luau
    │   ├── CraftingService.luau
    │   ├── HypeService.luau
    │   ├── RateLimitService.luau
    │   └── StateReplicationService.luau
    └── Config
        ├── Recipes.luau
        ├── Economy.luau
        ├── WorkshopUpgrades.luau
        └── Oddlings.luau

ReplicatedStorage
└── Shared
    ├── Constants.luau
    ├── Types.luau
    ├── Net.luau
    └── DisplayMetadata.luau

StarterPlayer
└── StarterPlayerScripts
    └── Client
        ├── init.client.luau
        ├── Controllers
        │   ├── HudController.luau
        │   ├── InteractionController.luau
        │   └── FeedbackController.luau
        └── UI
            └── minimal HUD modules
```

This tree is a target shape, not a requirement to create every file immediately. The current Rojo mappings can support this because `src/server`, `src/shared`, and `src/client` are already mapped into the correct Roblox services.

Reasoning:

- `ServerScriptService.Server` contains authoritative gameplay, economy, ownership, and production logic.
- `ReplicatedStorage.Shared` contains only shared constants, types, remote names, and safe display metadata.
- `StarterPlayerScripts.Client` contains presentation, HUD, input, and local effects.
- Server-only configs stay out of `ReplicatedStorage` when they contain authoritative costs, rewards, rates, or unlock rules.

## Planned Server Modules

### PlayerStateService

Responsibility: create, store, read, and mutate session-only player state through explicit server methods.

Authoritative side: server.

State owned:

- Scrap
- Hype
- WorkshopLevel
- OwnedOddlings
- UnlockedRecipes
- AssignedPlotId

Dependencies:

- server-only balance/config modules
- StateReplicationService for safe state updates

Must not:

- trust client-provided balances
- persist data yet
- expose mutable state tables directly to clients
- perform UI work

### WorkshopService

Responsibility: manage workshop plots, assignment, ownership, display anchors, crafting station context, and one upgrade state.

Authoritative side: server.

State owned:

- plot occupancy
- player-to-plot association
- plot upgrade level
- display slot occupancy

Dependencies:

- PlayerStateService
- WorkshopUpgrades config
- StateReplicationService

Must not:

- allow clients to claim another player's plot
- implement a full base-building system in Vertical Slice 0.1
- persist plot ownership across sessions

### SalvageService

Responsibility: attach server-side collection behavior to salvage nodes and award Scrap after validation.

Authoritative side: server.

State owned:

- salvage node cooldowns
- per-player collection cooldowns where needed

Dependencies:

- PlayerStateService
- RateLimitService
- server-only Economy config

Must not:

- accept client-submitted reward amounts
- allow unlimited collection spam
- create random rewards for the MVP

### CraftingService

Responsibility: validate recipe requests, charge Scrap, create owned Oddlings, and request physical display placement.

Authoritative side: server.

State owned:

- crafting transaction authority
- recipe eligibility decisions

Dependencies:

- PlayerStateService
- WorkshopService
- RateLimitService
- Recipes config
- Oddlings config

Must not:

- trust client-submitted prices, unlocks, rarity, or output
- create paid randomness
- handle persistence

### HypeService

Responsibility: produce Hype from displayed Oddlings at server-defined rates.

Authoritative side: server.

State owned:

- production ticks
- production cooldowns
- unclaimed or direct-awarded session Hype, depending on chosen first implementation

Dependencies:

- PlayerStateService
- WorkshopService
- server-only Economy/Oddlings config
- StateReplicationService

Must not:

- let clients report production amount
- rely on client timers for authority
- add offline earnings in Vertical Slice 0.1

### RateLimitService

Responsibility: provide small server-side rate limits for client-triggerable actions.

Authoritative side: server.

State owned:

- per-player action timestamps or token buckets

Dependencies:

- none beyond server time APIs

Must not:

- replace validation
- trust client cooldowns
- become a generic gameplay action dispatcher

### StateReplicationService

Responsibility: send sanitized state snapshots/deltas to clients for HUD and presentation.

Authoritative side: server.

State owned:

- no authoritative economy state; it reads from PlayerStateService and formats safe payloads

Dependencies:

- PlayerStateService
- Shared Net definitions

Must not:

- accept client-submitted authoritative state
- leak server-only config that clients do not need
- become a persistence layer

## Planned Client Modules

### HudController

Responsibility: render Scrap, Hype, current objective, workshop upgrade state, and simple recipe availability.

Authoritative side: client presentation only.

State owned:

- local copy of sanitized display state
- transient UI state such as visible panels

Dependencies:

- shared display constants
- state replication remote

Must not:

- calculate authoritative balances
- decide crafting success
- decide unlocks

### InteractionController

Responsibility: present prompts, button affordances, and request server actions when needed.

Authoritative side: client presentation only.

State owned:

- local prompt visibility and input state

Dependencies:

- shared remote definitions

Must not:

- bypass server-side ProximityPrompt validation
- send broad generic action payloads
- assume action success before server confirmation, except for cosmetic pending feedback

### FeedbackController

Responsibility: play local effects, sounds, notices, and simple animation feedback after server confirmation or harmless local input.

Authoritative side: client presentation only.

State owned:

- transient local effect state

Dependencies:

- HUD/presentation events

Must not:

- award resources
- spawn authoritative Oddlings
- advance progression

## Session State Model

Minimal server-owned conceptual state:

```text
PlayerState
- Scrap: number
- Hype: number
- WorkshopLevel: number
- AssignedPlotId: string?
- OwnedOddlings: list of OddlingInstance
- UnlockedRecipes: set of recipe ids

OddlingInstance
- InstanceId: string
- DefinitionId: string
- OwnerUserId: number
- DisplaySlotId: string?
- CreatedAtSessionTime: number
```

Authoritative fields:

- `Scrap`: awarded only by server-validated salvage.
- `Hype`: produced/spent only by server systems.
- `WorkshopLevel`: upgraded only after server validates cost and ownership.
- `AssignedPlotId`: assigned only by WorkshopService.
- `OwnedOddlings`: created only by CraftingService after cost/unlock checks.
- `UnlockedRecipes`: set only by server progression rules.

Clients may receive sanitized copies for UI, but the server copy is the only source of truth.

## Configuration Boundaries

### Server Only

Keep these in `ServerScriptService.Server.Config`:

- crafting costs
- salvage rewards
- Hype production rates
- workshop upgrade costs
- unlock requirements
- any weighted/random tables if future non-MVP systems ever need them
- anti-abuse thresholds that should not be tuned by clients

These values directly affect economy or progression and must not be duplicated as client authority.

### Safe To Share With Client

Keep these in `ReplicatedStorage.Shared` when useful:

- stable ids
- display names
- icon names or asset references
- short descriptions
- color/theme metadata
- ordered lists for UI presentation
- remote names/constants
- type aliases with no secret business rules

The client can know that Toastmarshal exists and how to display its name. The client should not need to know every authoritative crafting rule to request a craft.

## Networking Plan

THE CLIENT IS UNTRUSTED. Every client-originated request below is only a request, never proof that the action is valid or already complete.

No production remotes should be created until their implementation pass.

Use as few remotes as practical. Prefer server-side `ProximityPrompt.Triggered` for in-world interactions when Roblox already provides player/context information.

### StateSnapshot

Direction: server -> client.

Purpose: replicate sanitized player/workshop state for HUD and presentation.

Payload:

- Scrap
- Hype
- WorkshopLevel
- AssignedPlotId
- OwnedOddlings display summaries
- UnlockedRecipes display summaries
- current objective hint

Validation: server constructs payload; client treats it as display state.

Authorization/context checks: server sends only the receiving player's relevant private state plus public workshop display summaries.

Rate limit: server-controlled; coalesce frequent updates.

Authoritative state affected: none.

Failure behavior: client keeps last known display state or shows loading/pending state.

### RequestCraftOddling

Direction: client -> server.

Purpose: request crafting a specific recipe at a valid crafting station.

Payload:

- recipe id
- station id or prompt context token if needed

Validation:

- payload type/shape
- recipe id membership
- station id membership
- player has assigned plot
- player is near the station or prompt context is valid
- recipe is unlocked
- player has enough Scrap
- display capacity exists
- rate limit passes

Authorization/context checks:

- station belongs to player's plot or is a valid shared station
- output belongs to requesting player only

Rate limit: per-player craft request cooldown.

Authoritative state affected:

- Scrap
- OwnedOddlings
- display slot occupancy
- Hype production eligibility

Failure behavior: reject without state mutation; optionally send a sanitized failure reason.

Attacker-controlled input:

- recipe id
- station id/context token
- request timing/spam

### RequestUpgradeWorkshop

Direction: client -> server.

Purpose: request the one Vertical Slice 0.1 workshop upgrade.

Payload:

- upgrade id

Validation:

- payload type/shape
- upgrade id membership
- player owns a plot
- upgrade is available from current WorkshopLevel
- player has enough Hype
- rate limit passes

Authorization/context checks:

- target upgrade applies only to the player's assigned workshop

Rate limit: per-player upgrade request cooldown.

Authoritative state affected:

- Hype
- WorkshopLevel
- UnlockedRecipes, including Conejurer reveal if tied to upgrade

Failure behavior: reject without state mutation; optionally send a sanitized failure reason.

Attacker-controlled input:

- upgrade id
- request timing/spam

### RequestStateRefresh

Direction: client -> server.

Purpose: allow a newly initialized client HUD to request the latest sanitized state.

Payload: none, or a protocol version string if needed.

Validation:

- no mutable state in payload
- optional protocol version type check
- rate limit passes

Authorization/context checks:

- server sends only the requesting player's state

Rate limit: low-frequency per-player refresh limit.

Authoritative state affected: none.

Failure behavior: ignore or send a minimal loading-safe response.

Attacker-controlled input:

- request spam
- optional malformed version value

### Interactions That Do Not Need Client Remotes First

These can start as server-side `ProximityPrompt.Triggered` or server-managed events:

- salvage node collection
- plot claim prompt
- crafting station prompt opening server-confirmed UI context
- display slot assignment if automatic
- simple NPC dialogue triggers

Avoid creating a broad `RequestAction(actionName, payload)` remote.

## Client Responsibilities

The client owns:

- HUD rendering
- input and presentation
- local camera behavior
- local visual/audio feedback
- request initiation
- temporary pending indicators

The client must not be authoritative over:

- Scrap
- Hype
- crafting
- unlocks
- rewards
- workshop ownership
- Oddling ownership
- Oddling production
- upgrade eligibility
- purchase completion

Client UI should wait for server state before showing lasting success.

## Workshop Model

Minimum production workshop:

- at least two plots for multiplayer testing
- one owner per plot
- one spawn/claim point or assignment trigger
- one crafting station per plot or one shared station with plot-aware output
- one Oddling display location per plot
- one upgrade state visible in-world

Vertical Slice 0.1 should not become a giant base-building system. The workshop only needs enough structure to prove ownership, physical display, production, and upgrade visibility.

## First Oddling Implementation

Toastmarshal is the first functional production Oddling.

Required design:

- server-authorized creation through CraftingService
- associated with exactly one owning player
- placed into an owned workshop display slot
- has a server-defined Hype production value
- uses a basic original placeholder model initially
- readable silhouette and industrial toybox absurdism direction

Toastmarshal should prove the Oddling pipeline before expanding the catalogue.

Conejurer is the second recipe/unlock target. It should be revealed or unlocked after the first workshop upgrade, but it does not need to be as mechanically deep as Toastmarshal in the earliest pass.

## MVP Economy

Only two currencies exist in Vertical Slice 0.1:

- Scrap
- Hype

Scrap:

- obtained through salvage
- spent on crafting
- server-awarded
- session-only

Hype:

- generated by displayed Oddlings
- spent on workshop progression
- server-produced
- session-only

No additional currencies, premium currencies, paid boosts, randomized purchases, rebirth currency, quest tokens, or daily reward currencies belong in this slice.

## Prototype Retirement Strategy

The current keycard/core prototype should be removed in a dedicated future pass, not during this plan.

Retirement pass goals:

- remove prototype gameplay scripts and temporary HUD behavior
- remove `Workspace.OddworksArena`
- create minimal production bootstrap
- preserve proof-of-concept history through Git
- keep root Rojo mappings intact unless explicitly changed

Retirement should happen before real production gameplay code is introduced so prototype concepts do not leak into ODDWORKS systems.

## Implementation Pass Order

### 0D - Retire Prototype And Add Production Bootstrap

Objective: remove the keycard/core prototype and introduce empty production bootstrap structure.

Expected files/systems:

- `default.project.json`
- `src/server`
- `src/client`
- `src/shared`

New Roblox/Luau concepts introduced:

- production folder/module layout
- clean bootstrap entry points

Security boundary:

- no production networking yet
- do not introduce client authority

Verification needed:

- `git diff --check`
- `rojo build`
- Studio Edit hierarchy inspection
- short Play startup check
- Output inspection

Acceptance criteria:

- prototype removed intentionally
- root Rojo project still builds
- game starts without errors
- no production gameplay added beyond bootstrap

### 1 - Server-Owned Player Session State

Objective: add session-only PlayerStateService with Scrap, Hype, WorkshopLevel, OwnedOddlings, UnlockedRecipes, and AssignedPlotId.

Expected files/systems:

- `src/server/Services/PlayerStateService.luau`
- server bootstrap wiring
- focused server-side tests or debug assertions if available

New Roblox/Luau concepts introduced:

- player lifecycle handling
- immutable/safe state access patterns

Security boundary:

- server owns all state
- client receives no mutation path

Verification needed:

- join/leave Play test
- state initialized and cleaned up
- no client remotes yet
- Output inspection

Acceptance criteria:

- each player gets isolated session state
- leaving players do not leak state

### 2 - Workshop Plot Assignment

Objective: create at least two multiplayer-capable workshop plots and assign one owner per plot.

Expected files/systems:

- `WorkshopService`
- minimal workshop model/folder under Workspace through Rojo or controlled Studio-authored content
- shared plot ids if needed

New Roblox/Luau concepts introduced:

- plot ownership
- display anchors
- basic multiplayer allocation

Security boundary:

- server assigns/validates plot ownership
- clients cannot claim another player's plot

Verification needed:

- single-player assignment
- multi-client assignment
- leave/rejoin session behavior
- Output inspection

Acceptance criteria:

- at least two players get separate plots
- each plot has an owner or is clearly available

### 3 - Secure Salvage Interactions

Objective: add salvage nodes that award Scrap through server validation.

Expected files/systems:

- `SalvageService`
- `RateLimitService`
- server-only Economy config
- salvage node placeholders

New Roblox/Luau concepts introduced:

- server-side ProximityPrompt or touch validation
- node cooldowns

Security boundary:

- attacker-controlled input is prompt triggering/timing
- server validates proximity/context/cooldown
- server decides Scrap amount

Verification needed:

- collect Scrap normally
- spam interaction attempt
- invalid/distant interaction test where practical
- multi-client node behavior

Acceptance criteria:

- Scrap increases only from valid server-side salvage
- cooldown/rate limit prevents obvious spam

### 4 - Sanitized State Replication And HUD

Objective: display Scrap, Hype, plot status, and current objective through sanitized server state.

Expected files/systems:

- `StateReplicationService`
- shared Net definitions
- `HudController`
- minimal HUD UI

New Roblox/Luau concepts introduced:

- server -> client state snapshots
- client presentation controllers

Security boundary:

- client displays state only
- RequestStateRefresh is rate-limited if added

Verification needed:

- HUD initializes reliably
- state changes replicate after salvage
- malformed refresh requests rejected if remote exists
- Output inspection

Acceptance criteria:

- UI reflects server state
- no client-authored currency changes

### 5 - Server-Authoritative Crafting

Objective: craft Toastmarshal from Scrap at a valid crafting station.

Expected files/systems:

- `CraftingService`
- server-only Recipes config
- server-only Oddlings config
- RequestCraftOddling remote if prompt-only flow is insufficient

New Roblox/Luau concepts introduced:

- recipe validation
- transactional resource spending
- output creation

Security boundary:

- attacker-controlled input is recipe id, station/context id, and timing
- server validates recipe, cost, unlock, ownership, context, display capacity, and rate limit

Verification needed:

- valid Toastmarshal craft
- insufficient Scrap rejection
- invalid recipe id rejection
- spam craft rejection
- wrong station/plot rejection where practical

Acceptance criteria:

- Scrap is charged once
- Toastmarshal ownership is server-recorded
- no client-selected reward/output

### 6 - Toastmarshal Display And Spawn

Objective: physically display Toastmarshal in the player's workshop.

Expected files/systems:

- `WorkshopService` display slot support
- Toastmarshal placeholder model
- server placement code
- optional client effects after confirmation

New Roblox/Luau concepts introduced:

- model spawning/placement
- ownership labels or display metadata

Security boundary:

- server chooses model and display position
- client cannot spawn authoritative Oddlings

Verification needed:

- Toastmarshal appears in owner plot
- other player cannot take/overwrite display
- model remains readable at camera distance
- Output inspection

Acceptance criteria:

- physical display proves collection progress
- ownership association is visible or inspectable

### 7 - Server-Authoritative Hype Production

Objective: displayed Toastmarshal generates Hype from server timing/config.

Expected files/systems:

- `HypeService`
- production config
- HUD replication update

New Roblox/Luau concepts introduced:

- server production loop or scheduled ticks
- coalesced state updates

Security boundary:

- client cannot submit production amount or timer
- server validates displayed owned Oddlings before producing

Verification needed:

- Hype increases over time after display
- no Hype from undisplayed/non-owned Oddlings
- leaving player cleanup
- Output inspection

Acceptance criteria:

- Hype production is observable, server-owned, and bounded

### 8 - Workshop Upgrade

Objective: spend Hype on one visible workshop upgrade.

Expected files/systems:

- `WorkshopService`
- `WorkshopUpgrades` config
- RequestUpgradeWorkshop remote if needed
- upgraded visual state

New Roblox/Luau concepts introduced:

- upgrade validation
- visible world-state change

Security boundary:

- attacker-controlled input is upgrade id and timing
- server validates owner, cost, level, prerequisite, and rate limit

Verification needed:

- valid upgrade succeeds
- insufficient Hype rejected
- invalid upgrade rejected
- another player's plot cannot be upgraded

Acceptance criteria:

- Hype is charged once
- workshop visibly upgrades
- state replication updates

### 9 - Conejurer Unlock

Objective: reveal Conejurer as the second recipe/unlock after the upgrade condition.

Expected files/systems:

- Recipes config update
- Oddlings config update
- UI display metadata
- optional placeholder model

New Roblox/Luau concepts introduced:

- unlock presentation
- second recipe path

Security boundary:

- server determines unlock status
- client cannot claim Conejurer unlock

Verification needed:

- Conejurer hidden before upgrade
- Conejurer visible/unlocked after upgrade
- invalid early craft rejected

Acceptance criteria:

- next goal is clear
- unlock remains server-authoritative

### 10 - Multiplayer And Adversarial Hardening

Objective: test the complete slice under multiplayer and hostile-input assumptions.

Expected files/systems:

- targeted test harnesses or temporary debug commands if explicitly approved
- no broad refactors unless bugs require them

New Roblox/Luau concepts introduced:

- multi-client/server Studio testing workflow
- adversarial remote tests

Security boundary:

- all client-originated state-changing paths tested against malformed/spam/ownership attacks

Verification needed:

- two-client Studio test
- plot isolation
- salvage spam
- craft invalid ids
- upgrade invalid ids
- state refresh spam
- Output inspection

Acceptance criteria:

- vertical slice works for at least two players
- malformed requests do not corrupt state
- no unbounded server errors or obvious exploit path remains in the slice

## Testing Progression

Use single-player Studio Play for early module wiring, player state initialization, HUD rendering, and basic happy paths.

Move to Studio multi-client/server testing when any system involves:

- plot ownership
- shared salvage nodes
- other players viewing workshops
- state replication across players
- ownership-sensitive crafting or display placement

Multiplayer testing is required before Vertical Slice 0.1 can be declared complete.

Adversarial testing becomes required as soon as client-originated remotes or client-triggerable state-changing interactions are added.

## Persistence Deferral

DataStoreService is intentionally delayed until the session-only loop works correctly.

Persistence introduces:

- failure handling
- schema and version concerns
- default/migration behavior
- duplicated-session concerns
- save concurrency concerns
- data loss recovery questions
- retry and throttling behavior

Adding persistence too early would obscure whether the core session loop is fun, secure, and understandable. First prove the loop in memory. Then add persistence in a dedicated pass with its own contract and adversarial tests.

## Monetization Boundary

Vertical Slice 0.1 contains no monetization.

Do not design the slice around Robux. Do not add game passes, developer products, subscriptions, premium currencies, paid boosts, paid random rewards, or purchase UI.

Future monetization must wait until the loop is playable and must follow [Monetization Contract](MONETIZATION_CONTRACT.md).

## Art And IP Boundary

Toastmarshal, Conejurer, and future Oddlings must be original ODDWORKS characters.

Placeholder art is acceptable in early technical passes if it follows the industrial toybox absurdism direction: chunky silhouettes, friendly-weird expression, readable shapes, and no copied meme/IP assets.

## Verification Requirements For Future Implementation

Each implementation pass should report:

- contracts read
- files changed
- client/server authority boundaries
- attacker-controlled inputs, if any
- build/static checks performed
- Studio checks performed
- Output/errors inspected
- adversarial tests performed, if security-sensitive
- verification not performed
- suggested focused commit

No pass should claim runtime, Rojo, static, or security verification unless it actually ran that verification.
