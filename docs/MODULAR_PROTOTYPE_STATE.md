# ODDWORKS Modular Prototype State Contract

## Status

This document freezes the temporary authority, inventory, banking, assembly, networking, failure, and migration contracts for Vertical Slice 0.2.

It defines future implementation only. It does not add state, services, RemoteEvents, developer commands, or persistence fields.

## Ownership Boundary

The planned server-only owner is **ModularPrototypeStateService**.

Its only authoritative responsibility is one temporary Vertical Slice 0.2 state record per ready player containing:

- UnbankedComponents
- BankedComponents
- PrototypeConstruct

ModularPrototypeStateService must:

- initialize only after PlayerStateService confirms the player's verified production PlayerState exists
- remain server-only with no client mutation API
- remain separate from ProfileStore schema v1 and never write to ProfileStore directly
- expose narrow validated methods and copied snapshots
- clean up when the player leaves or loses the profile session
- never expose mutable inventory tables to clients or unrelated services
- be removed or reconsidered if Vertical Slice 0.2 fails its human fun gate

PlayerStateService remains the production authoritative gameplay-state owner. Experimental modular fields must not be added to PlayerStateService during Vertical Slice 0.2.

Salvage, banking, assembly, display, and future developer tools must use narrow ModularPrototypeStateService APIs rather than maintaining competing copies or mutating its private tables directly.

## Rarity Type

The only valid prototype rarity values are:

```luau
export type ComponentRarity = "Common" | "Rare" | "Legendary"
```

Rarity is separate from ComponentId. It is validated against this enum and never parsed from a client-authored combined string.

## Count-Based Component Inventory

Identical components with the same ComponentId and Rarity are interchangeable. The prototype therefore uses nested count maps:

```luau
export type ComponentCounts = {
    [string]: {
        [ComponentRarity]: number,
    },
}
```

Conceptual example:

```luau
BankedComponents = {
    ServoArm = {
        Common = 0,
        Rare = 2,
        Legendary = 0,
    },
    ClownMask = {
        Common = 1,
        Rare = 0,
        Legendary = 0,
    },
}
```

This nested structure was chosen instead of combined ComponentId-and-Rarity string keys because the two fields have different validation and configuration responsibilities. It also avoids unique item records when identical items have no per-instance differences.

Implementations may omit zero-count rarity or component entries internally, but copied snapshots should normalize absent counts to zero where presentation needs it.

All counts are server-owned non-negative finite integers. No mutation may produce a negative count.

The prototype maximum is 999 for any one ComponentId and Rarity bucket. A reward, bank, rebuild, or developer setup mutation that would exceed this bound must fail with zero mutation. This cap is a technical safety bound, not a target inventory size.

## Component Selection

A Construct selection identifies both axes explicitly:

```luau
export type ComponentSelection = {
    ComponentId: string,
    Rarity: ComponentRarity,
}
```

A selection contains no stats, ArtModel, socket CFrame, quantity, Instance, or client-provided compatibility claim. The server derives those values from configuration.

## PrototypeConstruct Record

The smallest authoritative session record is:

```luau
export type PrototypeConstruct = {
    FrameId: "SmallBiped_v1",
    Head: ComponentSelection,
    Arm: ComponentSelection,
    Legs: ComponentSelection,
}
```

The complete player modular state is conceptually:

```luau
export type ModularPrototypeState = {
    UnbankedComponents: ComponentCounts,
    BankedComponents: ComponentCounts,
    PrototypeConstruct: PrototypeConstruct?,
}
```

The Construct has no player-authored name, level, mutation, random roll, trading metadata, persistent ID, or Instance references.

Only one complete PrototypeConstruct may exist per player in Vertical Slice 0.2. Partial Construct records are invalid; before the first complete assembly, PrototypeConstruct is nil.

## Session-State Meaning

### UNBANKED

UnbankedComponents is the current server-owned salvage-run haul. It is vulnerable according to the encounter failure contract and disappears when the server session ends.

### BANKED

BankedComponents is protected workshop inventory for the current server session. Ordinary salvage failure cannot remove it. Banked does not mean ProfileStore-persistent.

### RESERVED / INSTALLED

Components selected in PrototypeConstruct are installed. Their counts are removed from BankedComponents and represented by the Construct selections.

An installed component cannot simultaneously remain available for another assembly request.

## Conservation Invariant

For every ComponentId and Rarity pair, session ownership is conserved across:

```text
Unbanked count + Banked count + Installed count
```

Installed count is derived from the three PrototypeConstruct selections and is either zero or one per matching role in this one-Construct prototype.

Banking moves counts from Unbanked to Banked. Assembly moves counts from Banked to Installed. Rebuild or disassembly returns replaced selections to Banked. No successful transition creates or destroys counts except a server-authoritative salvage reward or an explicitly documented salvage-failure loss.

## Banking Transaction

The prototype Bank operation moves the player's entire current UnbankedComponents haul into BankedComponents.

The server must:

1. Verify initialized modular state.
2. Verify the player is in the authoritative safe banking context.
3. Reject extra payload values.
4. Copy and validate the current UnbankedComponents counts.
5. Calculate the resulting BankedComponents counts with checked integer addition.
6. Commit both maps as one service-owned transition.
7. Set UnbankedComponents to an empty map only after the destination calculation succeeds.
8. emit one internal state-change notification after commit.

If validation or calculation fails, neither map changes. A repeated Bank request after success finds an empty haul and awards nothing.

Banking does not call ProfileStore and does not alter schema v1.

## Assembly Consumption Decision

Vertical Slice 0.2 chooses temporary equipping, not permanent consumption.

This best tests the invention fantasy because players can experiment with combinations without repeatedly salvaging replacement pieces after every rebuild. It also avoids a crafting-consumption economy before assembly itself is proven fun.

The lifecycle is:

```text
BANKED -> RESERVED / INSTALLED -> RETURNED ON REBUILD OR DISASSEMBLY
```

Installed components remain owned by the player but are unavailable in BankedComponents until replaced or disassembled.

## First Assembly Transaction

For a player with no PrototypeConstruct, the server must:

1. Validate the requested frame and all three selections.
2. Verify each selected ComponentId exists and supports its requested Rarity.
3. Verify Head, Arm, and Legs slot compatibility with SmallBiped_v1.
4. Verify the server-owned BankedComponents counts contain one of each selection.
5. Verify required runtime templates are available before committing invisible state.
6. Calculate a copied BankedComponents result with one of each selection removed.
7. Commit the copied bank and complete PrototypeConstruct together.
8. emit one internal state-change notification.
9. Let the derived display reconciler construct or rebuild the physical Model.

If any validation or calculation fails, no bank count or Construct state changes.

## Rebuild Transaction

For a player who already has a PrototypeConstruct, rebuilding is one atomic replacement transaction.

The server must:

1. Build a temporary available pool from BankedComponents plus the three currently installed selections.
2. Validate the new complete selection against configuration and that temporary pool.
3. Subtract the new Head, Arm, and Legs selections from the pool.
4. Use the remainder as the new BankedComponents map.
5. Replace PrototypeConstruct with the new complete record in the same commit.
6. emit one internal state-change notification.

This virtual-return calculation lets a player keep an unchanged installed module without needing a second copy. It also prevents replaced components from being lost or briefly duplicated.

## Disassembly Transaction

A future narrow disassembly operation may:

1. Add all three installed selections back into a copied BankedComponents map.
2. Set PrototypeConstruct to nil in the same commit.
3. trigger derived display cleanup through normal reconciliation.

Disassembly is not required for the first end-to-end UI if rebuild is sufficient, but the return semantics are frozen. It must never destroy the selected components.

## Salvage Reward Authority

The client may indicate an interaction attempt or allowed extraction input. It never provides the resulting component record.

The server determines:

- encounter identity and lifecycle
- eligibility, distance, and context
- completion and performance classification
- authoritative reward table
- ComponentId
- Rarity
- quantity
- checked UnbankedComponents mutation

The server reward tuple is conceptually:

```luau
{
    ComponentId = "ServoArm",
    Rarity = "Rare",
    Quantity = 1,
}
```

That tuple is created inside trusted server code. It is never accepted as a client payload.

## First Encounter Failure Rule

The first Common encounter is forgiving:

- failure cancels its pending, not-yet-awarded reward
- the encounter can be retried
- already acquired UnbankedComponents are not removed by this first encounter
- BankedComponents, PrototypeConstruct, and schema-v1 data are never affected

Harder future encounters may reduce or clear the current UnbankedComponents haul after an explicit design and UX review. Ordinary prototype failure must never delete ProfileStore data.

## Assembly Authority

The client may request:

- FrameId
- one Head ComponentId and Rarity
- one Arm ComponentId and Rarity
- one Legs ComponentId and Rarity

The requested Rarity is only a selector for an already banked ComponentId and Rarity bucket. It is not a client-authored reward rarity or stat claim. The server verifies that the configured rarity exists and that the corresponding bank count is available.

The server independently resolves and validates:

- the only configured frame
- all component definitions
- all rarity values
- slot compatibility
- frame compatibility
- banked quantities
- runtime ArtModels
- configured effects
- the resulting authoritative PrototypeConstruct

No client payload may include stats, ArtModel names, socket transforms, ModuleRoot names, quantities to consume, reward records, Instances, or persistent IDs.

## Derived Runtime Model

PrototypeConstruct is the source of truth. The physical Roblox Model is reconstructable derived representation.

The display reconciler should:

1. Read a copied PrototypeConstruct snapshot.
2. Resolve SmallBiped_v1_Frame from server-owned assets.
3. Resolve each ComponentId to its server-owned ArtModel; Rarity does not change geometry.
4. clone and join the modules according to SMALL_BIPED_V1.md.
5. place the assembled Model at the authoritative workshop display location.
6. start the shared idle if configured.

Deleting the runtime Model must not alter component counts or PrototypeConstruct. Reconciliation should recreate it. State must never store Instance references.

## Signature Detection Insertion Point

Future Signature recognition occurs only after the server validates banked ownership and compatibility:

```text
validated banked selections
-> server assembly validation
-> optional server signature matcher
-> Signature Oddling result OR Custom Construct result
```

Vertical Slice 0.2 does not implement Toastmarshal conversion or consume components through a Signature matcher. Without a configured matcher, a valid request produces the one Custom PrototypeConstruct.

## Planned Network Requests

No RemoteEvent is created in 0.2A. Future implementation may add only these narrow intents when their server consumers exist.

### SalvageInteractRequest

Direction: client to server.

Payload:

```luau
encounterId: string
```

Exact argument count: one. Maximum ID length: 32 bytes. The server resolves the encounter, player identity, position, lifecycle, progress, performance, reward, rarity, and quantity. If ProximityPrompt.Triggered fully serves the chosen interaction, this remote should not be created.

Initial throttle ceiling: four processed attempts per player per second, with encounter state allowed to be stricter.

### BankRequest

Direction: client to server.

Payload: no arguments.

The server uses the Roblox-supplied Player, assigned workshop, authoritative bank context, and current UnbankedComponents. The client does not submit a haul.

Initial throttle ceiling: one processed attempt per player per second.

### AssembleConstructRequest

Direction: client to server.

Payload: one table with exactly these keys:

```luau
{
    FrameId = "SmallBiped_v1",
    Head = { ComponentId = "ClownMask", Rarity = "Common" },
    Arm = { ComponentId = "ServoArm", Rarity = "Rare" },
    Legs = { ComponentId = "SpringLegs", Rarity = "Common" },
}
```

Each selection table has exactly ComponentId and Rarity. ComponentId is a string no longer than 32 bytes. Rarity is a configured enum string no longer than 16 bytes. Extra keys or arguments are rejected.

Initial throttle ceiling: one processed attempt per player per second.

## Request Validation Order

Every future modular request should validate, in order:

1. Exact argument count and shape.
2. Primitive types and string lengths.
3. Player still belongs to this server and has ready PlayerState.
4. Modular session state exists.
5. Per-action server throttle.
6. Configured identifier and enum membership.
7. Authoritative encounter, workshop, proximity, or ownership context.
8. State prerequisites and quantities.
9. Runtime asset availability where invisible ownership would otherwise result.
10. Transaction calculation on copies.
11. One authoritative commit and one internal notification.

After final validation, transaction calculation and commit must not yield. If lifecycle or asset checks require yielding, perform them before the final state recheck, then re-resolve the player's ready state before committing. This prevents leave-time or concurrent-request interleaving from creating partial transitions.

Ordinary invalid requests return a bounded result code or no mutation. They do not kick a player unless a separate reviewed abuse policy requires it.

Suggested bounded result codes include:

- SUCCESS
- INVALID_REQUEST
- NOT_READY
- OUT_OF_RANGE
- RATE_LIMITED
- INVALID_COMPONENT
- INCOMPATIBLE_COMPONENT
- INSUFFICIENT_COMPONENTS
- NOTHING_TO_BANK
- ASSET_UNAVAILABLE

## Unbanked Presentation Snapshot

The client needs a sanitized display copy sufficient to communicate that loot is currently at risk.

The eventual snapshot may include safe counts or a total unbanked quantity, but the exact presentation is deferred. A HUD marker, carried container, backpack visualization, or another clear mechanism may consume it.

Client UI never determines UnbankedComponents. Altering or hiding the display does not bank, lose, or create components.

## Studio Developer Harness Plan

Future Studio-only testing may justify two commands:

- ow-modular-state [player]: read-only formatted Unbanked, Banked, installed selections, and conservation totals
- ow-give-component [player] <unbanked|banked> <ComponentId> <Rarity> <positive count>: arrange a test scenario through a narrow service API

The mutating command should retain the current server-side Studio-only authorization, use configured IDs and rarity enums, cap count at 100 per invocation, and log that it is a development setup bypass.

Do not add raw table replacement, arbitrary Construct injection, persistence writes, or destructive wipe commands. These commands are not implemented in 0.2A and cannot prove production salvage or banking works.

## Persistence Migration Gate

Do not add modular fields to ProfileStore schema v1.

A schema-v2 proposal is justified only after human testing confirms that this complete loop is meaningfully more engaging than fixed crafting:

```text
active salvage
-> visible unbanked haul
-> safe banking
-> server-validated assembly
-> visible personalized Construct
```

The technical gate also requires:

- no known duplication or component-loss defect
- deterministic reconstruction of the derived Model
- two-player isolation
- safe leave, cleanup, and rejoin behavior for existing schema-v1 data
- a settled decision on whether production needs multiple Constructs
- a migration, validation, rollback, and test-namespace plan

Only then should schema v2 consider count-based Components and unique Construct records. Unique component GUIDs remain unjustified until per-instance rolls, histories, or trading create a real identity requirement.

## Explicit Non-Goals

Vertical Slice 0.2 does not require:

- an ECS framework
- arbitrary component graphs
- a generic inventory framework
- a random affix engine
- a trading framework
- a generalized equipment framework
- a full placement grid
- field-companion AI
- procedural mesh generation
- a custom physics system
- production persistence migration
- unique component instances or GUIDs
- multiple Custom Constructs per player
- player-authored names
- Custom Construct Hype generation
- Signature conversion
- random rolls, mutations, or affixes
- unrestricted sockets or transforms
