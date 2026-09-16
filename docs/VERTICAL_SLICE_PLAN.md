# ODDWORKS Vertical Slice Roadmap

## Status

Vertical Slice 0.1 is the verified technical foundation for ODDWORKS. It proved that the project can support server-authoritative progression, persistence, multiplayer workshops, physical collection display, production, and secure client presentation.

Direction v2 changes the next product question. The next experiment is **Vertical Slice 0.2 - Salvage + Modular Invention Proof**.

This roadmap does not authorize a giant production rewrite. It preserves working architecture while testing the smallest new loop that could justify deeper investment.

## Contract Inputs

Future passes must read the relevant parts of:

- [Game Direction](GAME_DIRECTION.md)
- [Art Direction](ART_DIRECTION.md)
- [Salvage Design Contract](SALVAGE_DESIGN_CONTRACT.md)
- [Modular Oddling Contract](MODULAR_ODDLING_CONTRACT.md)
- [Security Contract](SECURITY_CONTRACT.md)
- [World Placement](WORLD_PLACEMENT.md)
- [Persistence](PERSISTENCE.md)
- [Codex Workflow](CODEX_WORKFLOW.md)
- [Monetization Contract](MONETIZATION_CONTRACT.md)

## Vertical Slice 0.1: Verified Technical Foundation

The implemented foundation includes:

- PlayerStateService for private server-owned gameplay state
- PersistenceService and ProfileStore-backed schema-v1 session handling
- WorkshopService for isolated multiplayer plot assignment
- SalvageService as a secure prompt-to-reward interaction proof
- CraftingService and server-owned recipes
- ProgressionService and workshop-level recipe reconciliation
- OddlingDisplayService for derived physical representation
- HypeService for production from valid displayed Oddlings
- WorkshopUpgradeService and display-capacity progression
- StateReplicationService and sanitized client HUD state
- a Studio-only developer harness with server-side authorization
- the source-controlled Toastmarshal runtime and art pipeline
- a second-species gameplay proof using Conejurer prototype content

This work remains useful. It established authority, lifecycle, reconciliation, persistence, display, and multiplayer patterns that Direction v2 needs.

## What 0.1 Did Not Prove

The fixed loop of collecting Scrap and pressing a recipe button did not prove the new core fantasy:

**Find weird parts -> get them home -> build weird creatures.**

It also did not prove:

- active extraction
- unbanked-haul risk
- banking as a meaningful transition
- component inventory
- frame and socket compatibility
- player-authored modular assembly
- Custom Construct identity

The current salvage interaction remains a security proof and common-currency mechanic, not the final active salvage design.

## Vertical Slice 0.2: Salvage + Modular Invention Proof

### Hypothesis

Actively recovering parts and assembling a visible creature is substantially more fun and distinctive than collecting Scrap and pressing a fixed craft button.

### Target Flow

The first implementation goal is:

**active salvage -> temporary component reward -> safe banking -> simple assembly -> visible modular Construct**

This should connect naturally to the larger Direction v2 loop:

**Find -> Extract -> Escape / Bank -> Assemble -> Flex**

### Prototype Boundary

Vertical Slice 0.2 should contain approximately:

- the current junkyard test environment
- one forgiving active salvage encounter
- one SmallBiped_v1 frame with built-in chassis/core
- Head, Arm, and Legs construction choices
- about two component choices per slot
- Common, Rare, and Legendary configured rarity
- deterministic rarity stats
- a temporary small component inventory
- one session-only PrototypeConstruct
- Toastmarshal as the first Signature discovery or immediate follow-on experiment

The prototype should be large enough to test the hypothesis and small enough to discard or reshape without a migration crisis.

## Authority Boundary for 0.2

The server must own:

- encounter state and eligibility
- extraction success
- reward identity and rarity
- unbanked and banked status
- component ownership
- frame and socket compatibility
- assembly success
- the session-only PrototypeConstruct record and configured stats
- any eventual save payload

The client may present encounters, request allowed actions, preview compatible selections, and render the resulting state. It must never submit a complete authoritative component or Construct record.

Exact networking should be designed in the implementation pass that first needs it. Do not add a generic action router.

## Prototype State and Persistence

Verified schema-v1 persistence remains unchanged during the first 0.2 experiment.

Modular prototype state is session-only:

- **UNBANKED:** vulnerable temporary salvage-run components
- **BANKED:** protected temporary component inventory for the current server session
- **RESERVED / INSTALLED:** components assigned to the one PrototypeConstruct and unavailable for simultaneous use

Banking does not write components to ProfileStore. Production persistence schema v1 remains unchanged until the modular loop passes its human fun and technical gates and receives a dedicated migration pass.

The player must clearly understand when loot is unbanked through a future derived HUD, carried-object, backpack, or similarly clear presentation. Server-owned UnbankedComponents state remains authoritative; 0.2A does not need to select the final presentation mechanism.

The session-only PrototypeConstruct does not require a persistent unique GUID. Persistent unique IDs are deferred until individual Constructs must coexist, survive sessions, retain player-authored identity, or support histories or trading.

Do not save:

- runtime models
- preview state
- socket Instances
- arbitrary transforms
- client-authored records

If the prototype proves fun, a dedicated persistence pass may consider count-based identical component inventory and unique Construct records. Unique component instances should be introduced only if per-item variance later justifies their cost.

## Existing-System Reuse

The next experiment should reuse rather than replace:

- PlayerStateService for authoritative in-session ownership boundaries
- PersistenceService for existing schema-v1 data only
- WorkshopService for safe plots and multiplayer isolation
- OddlingDisplayService patterns for derived physical representations
- HypeService concepts for production from valid displays
- ProgressionService for deterministic reconstruction
- StateReplicationService for sanitized client presentation
- the developer harness for arranging Studio test scenarios
- Toastmarshal as a Signature-art and runtime-pipeline proof

These services may evolve through narrow APIs. They should not be rewritten merely because the product loop changed.

Custom Construct Hype is not part of Vertical Slice 0.2 acceptance. Do not modify HypeService for the first modular proof; Hype integration is a later follow-up if the salvage-and-assembly loop proves fun.

## Suggested Narrow Pass Order

### 0.2A - Frame, Component, and State Contract

Define the SmallBiped_v1 reference, component IDs, HeadSocket/ArmSocket/LegsSocket compatibility, deterministic rarity effects, temporary state shape, and server/client boundaries. Freeze whether ArmModule is one selected arm plus a built-in arm or a paired assembly, and whether LegsModule is the complete paired lower body, before Blender work begins. Individual left/right customization is out of scope.

Define the atomic BANKED -> RESERVED / INSTALLED -> RETURNED ON REBUILD OR DISASSEMBLY lifecycle. Prototype assembly must not permanently destroy components, and installed components must not remain simultaneously available in BankedComponents.

Acceptance: one precise data and asset contract exists without speculative systems.

### 0.2B - One Active Salvage Encounter

Implement one forgiving server-authoritative extraction activity that awards temporary unbanked prototype components.

Acceptance: reward identity and success come from the server; ordinary failure affects only the current unbanked test haul.

### 0.2C - Banking Boundary

Implement one explicit safe-workshop transition from unbanked haul to protected temporary component inventory for the current server session.

Acceptance: the transition is atomic, duplication-resistant, and multiplayer-isolated.

### 0.2D - SmallBiped_v1 Assembly

Allow server-validated selection of one HeadModule, ArmModule, and LegsModule option for the fixed SmallBiped_v1 frame.

Acceptance: ownership and compatibility are checked server-side; configured transforms are used; no unrestricted placement exists.

### 0.2E - Visible Construct

Create one derived physical Custom Construct in the owner's workshop using the approved frame/socket contract and existing placement principles.

Acceptance: the Construct is recoverable from authoritative prototype state, safely placed, and isolated by player.

### 0.2F - Multiplayer, Adversarial, and Fun Evaluation

Test malformed requests, duplicate banking, disconnect boundaries, incompatible modules, capacity, cleanup, and two-player isolation. Conduct a human play review focused on whether extraction and assembly are actually enjoyable.

Acceptance: technical integrity is demonstrated and the product hypothesis receives an explicit continue, revise, or stop decision.

## World Direction

Future world redesign must account for:

- salvage encounter space
- a safe workshop and banking zone
- clearly separate player workshops
- future modular display footprints
- social visibility
- traversal between risk and safety

The unaccepted Pass 13 environment prototype remains reference work only. Do not revive or polish it as the next pass until the active-salvage encounter and banking needs are defined.

## First-Session Target

The intended pacing target is:

- 0:00: spawn and understand workshop and salvage direction
- within the first minute: perform a forgiving active salvage interaction
- around minute 1: return with first components
- around minute 2: assemble or reveal the first creation
- immediately afterward: understand the visible creation and the next desirable salvage objective

These are design targets, not contractual guarantees or reasons to bypass validation.

## Success Evidence

Vertical Slice 0.2 succeeds only if human testing supports the statement:

**Recovering parts and building a creature is more compelling than the fixed Scrap-to-recipe loop.**

Useful evidence includes:

- players understand what is unbanked and what is safe
- extraction feels active rather than ceremonial
- the bank-or-push decision is readable when introduced
- component choices produce recognizable differences
- the first Construct reveal feels personal and shareable
- another player's creation is legible and interesting
- server state remains authoritative under multiplayer and malformed-input tests

If the core interaction is weak, do not compensate by adding dozens of components, rarities, zones, or effects.

## Explicitly Deferred

Vertical Slice 0.2 does not include:

- random per-instance component rolls
- affixes or mutations
- unrestricted freeform construction
- unrestricted sockets
- player-authored workshop placement
- a full field-companion system
- large or Colossal production frames
- a large zone catalog
- dozens of components
- trading or PvP stealing
- destructive prestige or rebirth
- persistence migration before prototype validation
- offline production
- monetization
- user-generated scripts
- runtime AI content generation

## Completion Gate

Do not describe 0.2 as complete because its data structures compile. Completion requires:

- one end-to-end active salvage and banking path
- one valid modular assembly path
- one visible Custom Construct
- server authority and multiplayer isolation
- lifecycle and adversarial testing
- a human verdict on the central fun hypothesis
