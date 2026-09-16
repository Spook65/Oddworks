# ODDWORKS Modular Oddling Contract

## Status

This document defines the future modular-construction boundary for ODDWORKS Direction v2. It does not claim that frames, components, inventories, sockets, or Custom Construct persistence are implemented.

The current Toastmarshal pipeline and count-based Oddling ownership remain valid technical foundations. Modular construction will be introduced through a small experiment rather than a replacement of every existing system.

## Two Creature Categories

### Signature Oddlings

Signature Oddlings are authored ODDWORKS characters. Toastmarshal and a future production Conejurer are examples.

They have:

- bespoke ODDWORKS identity
- authored silhouette and personality
- bespoke animation where appropriate
- a finite Oddling Index entry
- an authored recipe, Blueprint, Core, or discovery path

Signature Oddlings may use bespoke rigs and do not need to fit the modular frame grammar when that would weaken their identity.

### Custom Constructs

Custom Constructs are assembled by players from compatible modules.

They have:

- player-selected parts
- a controlled frame and socket grammar
- deterministic compatibility rules
- a future player-chosen name where safe and filtered
- a place in **My Builds**, not a new canonical species entry for every combination

Custom Constructs do not replace Signature Oddlings. One supports player expression; the other carries authored identity and discovery.

## Construction Philosophy

ODDWORKS uses LEGO-like modular construction, not clay-like freeform sculpting.

Players choose meaningful compatible pieces. They do not manipulate arbitrary vertices, run scripts, create unrestricted sockets, or place parts at unconstrained transforms.

This constraint protects:

- readable silhouettes
- animation and rig compatibility
- reliable replication
- predictable collision and footprint
- server validation
- performance
- moderation and persistence scope

## Initial Frame

The first prototype frame is **SmallBiped_v1**.

SmallBiped_v1 includes its chassis and core geometry as part of the frame. The only player-selectable module roles are:

- HeadModule
- ArmModule
- LegsModule

The corresponding prototype socket vocabulary is:

- HeadSocket
- ArmSocket
- LegsSocket

A Core is not a player-selectable geometry module for SmallBiped_v1. Cores remain a valid future resource concept for Signature Oddlings, advanced frames, major passives, and authored discoveries.

The names do not finalize exact transforms. Vertical Slice 0.2A must define canonical origin, scale, axes, pivots, attachment transforms, mirroring rules, rig behavior, bounds, and grounding.

Future frames may add or change slots through explicit versioned contracts. An individual module must not silently redefine the frame.

### Arm and Legs Semantics to Freeze in 0.2A

Before Blender modular assets are authored, Vertical Slice 0.2A must decide:

- whether ArmModule represents one visible player-selected arm paired with a built-in frame arm, or one complete paired-arm assembly
- whether LegsModule represents the complete paired lower-body and mobility assembly

Individual left/right arm or leg customization is out of scope for the first prototype. Asset production must not guess these semantics independently.

## Compatibility Contract

A future component configuration should identify at least:

- stable component ID
- compatible frame class
- compatible socket or role
- rarity
- deterministic configured effect
- runtime template identity
- authored attachment orientation and transform

The server decides compatibility. A client may request a selection, but it may not claim that a component fits a socket or supply the authoritative attachment transform.

## Component Domains

Component effects should follow understandable domains:

- Arm / Tool: extraction
- Legs / Mobility: movement, stamina, or traversal
- Head / Sensor: detection or information
- Core: major identity or passive behavior
- Face / Showpiece: Hype and social presentation
- Back / Utility: carrying, protection, or utility

Not every frame must expose every domain in the first prototype. Domains create a coherent design vocabulary for later expansion.

## Deterministic Rarity Effects

For the first prototype:

**part type + rarity -> deterministic configured effect**

Example:

- ServoArm_Common -> +5% Extraction
- ServoArm_Rare -> +12% Extraction
- ServoArm_Legendary -> +22% Extraction

These values illustrate the contract and are not final balance commitments.

The first prototype must not add random per-instance rolls. In a future system, numeric values may vary procedurally inside bounded domains if the added persistence and UX complexity is justified. Special behaviors should remain authored and understandable.

### Prototype Rarity Art Rule

One ComponentId uses one prototype art model regardless of rarity. ServoArm_Common, ServoArm_Rare, and ServoArm_Legendary all use the same ServoArm prototype geometry.

Rarity changes authoritative configuration such as effect magnitude and client-safe UI presentation. Small material or VFX distinctions may be considered later, but Vertical Slice 0.2 does not require separate Common, Rare, and Legendary Blender models.

Approximately six module models can therefore represent the planned two component choices for each of the three selectable roles across multiple rarity configurations.

## Frame and Size Contract

Conceptual size classes are:

- Small
- Medium
- Large
- Colossal / Showcase

Frame class determines size and footprint. Rarity does not determine physical size.

Large and Colossal Constructs need more than vertical grounding. Future implementation may require display-area checks, overlap validation, collision bounds, workshop clearance, and special showcase locations. Standard plots should not support unlimited dimensions.

## Art and Blender Contract

Modular assets must comply with the active art direction and the approved frame reference for:

- scale
- socket identity
- axis and orientation
- attachment transform
- pivot
- rig compatibility
- silhouette
- materials and fastener language
- collision and bounds

The Blender or Art agent must not invent these standards independently for each module. If a module reveals a flaw in the contract, the contract should be reviewed before more assets are authored.

Signature art remains free to use bespoke rigs where appropriate, while still following placement and runtime safety rules.

## Assembly Authority

This section defines future trust boundaries, not an implemented remote contract.

The client may request:

- a frame selection from allowed options
- component selections from the player's visible inventory
- an allowed preview rotation or presentation choice
- confirmation of an assembly request

The server must determine:

- component ownership
- whether each component is banked and available
- frame and socket compatibility
- allowed transforms
- consumption or reservation rules
- Construct creation success
- any identity required by the current state model
- configured stats
- persistent payload

The client must never submit a complete authoritative component or Construct record. Preview models and UI values are presentation only.

For Vertical Slice 0.2, the single session-only PrototypeConstruct does not require a persistent unique GUID. A narrow session record is sufficient. Persistent unique Construct IDs become necessary only when multiple individual Constructs coexist, Constructs survive across sessions, player-authored identity must persist, or trading or individual histories are introduced.

## Prototype Component Availability

Prototype components represent physical owned parts. A component installed in the one PrototypeConstruct must not simultaneously remain freely available in BankedComponents.

Vertical Slice 0.2A must formalize a simple lifecycle:

**BANKED -> RESERVED / INSTALLED -> RETURNED ON REBUILD OR DISASSEMBLY**

Assembly should not permanently destroy prototype components. Exact atomic reservation, replacement, rollback, and return behavior belongs to 0.2A.

## Collection Information Architecture

Future collection presentation should distinguish:

### Oddling Index

Finite authored Signature discoveries.

### Part Catalog

Discovered component types and their understandable roles.

### My Builds

Individual player-created Custom Constructs.

These categories prevent combinatorial Custom Constructs from pretending to be canonical species and keep authored discovery meaningful.

## Workshop and Hype

Displayed Signature Oddlings and Custom Constructs may generate workshop Hype according to server configuration.

Hype represents reputation and attention. It may support workshop expansion, display capacity, assembler capability, salvage access, and event access. It should not become a second generic version of Scrap.

Physical display remains derived from authoritative ownership and workshop capacity. A missing model or presentation failure must not delete authoritative ownership.

Custom Construct Hype is not required for Vertical Slice 0.2. The first modular proof ends at a visible personalized Construct. Hype integration is a future follow-up only if active salvage, banking, and assembly prove fun; HypeService should not be modified merely to satisfy this long-term direction.

## Future Field Role

Field deployment is future work, not part of the first modular prototype.

A possible long-term split is:

- **Display** -> generates Hype
- **Deploy** -> assists a salvage expedition

Component domains are being designed with this possibility in mind, but no companion AI, field simulation, or deployment state should be implemented yet.

## Persistence Direction

The verified schema-v1 persistence remains unchanged during the first modular experiment.

Current schema-v1 truth persists Scrap, Hype, WorkshopLevel, and count-based OwnedOddlings. AssignedPlotId, UnlockedRecipes, physical models, displays, animations, timers, and UI are session-only or derived and are not saved. Existing reconciliation restores the appropriate derived state after load.

During Vertical Slice 0.2, **banked** means protected temporary component inventory for the current server session. It does not mean ProfileStore-persistent. The experimental states are:

- **UNBANKED:** vulnerable temporary salvage-run components
- **BANKED:** protected temporary component inventory for the current server session
- **RESERVED / INSTALLED:** owned components assigned to the session-only PrototypeConstruct and unavailable for simultaneous assembly use

If the experiment proves fun, persistence may evolve toward:

- count-based component inventory while parts are identical
- unique Construct records
- unique component instances only if per-item random rolls eventually justify them

Static component metadata and deterministic stats belong in authoritative server configuration. They should be derived by ID rather than duplicated into every player save.

Any save-schema change requires a dedicated migration, validation, rollback, and test plan. It must not be smuggled into the first assembly experiment.

## First Modular Prototype

The intended experiment contains approximately:

- the current junkyard test environment
- one active salvage encounter
- one SmallBiped_v1 frame with built-in chassis/core
- Head, Arm, and Legs construction choices
- about two component choices per slot
- Common, Rare, and Legendary configured rarity
- deterministic rarity stats
- a temporary small component inventory
- one session-only PrototypeConstruct
- Toastmarshal as the first Signature discovery or immediate follow-on experiment

The experiment asks:

**Is actively recovering parts and building a creature substantially more fun than collecting Scrap and pressing a fixed craft button?**

It is not a commitment to a full production inventory, unlimited combinatorics, or mass modular-art creation.

The six-or-so prototype module models are shared across rarity metadata. The prototype does not require rarity-specific geometry, persistent Construct IDs, Custom Construct Hype generation, or individual left/right limb selection.

## Explicitly Deferred

The first modular prototype excludes:

- random rolled component stats
- affixes
- mutations
- trading
- PvP stealing
- destructive prestige
- freeform body sculpting
- unrestricted sockets
- player-authored workshop placement
- a full field-companion system
- large frame and zone catalogs
- dozens of components
- persistence migration
- monetization
- offline production
- user-generated scripts
- runtime AI content generation
