# ODDWORKS Security Contract

## Core Rule

**THE CLIENT IS UNTRUSTED.**

The Roblox client presents the game and requests allowed actions. The server resolves authoritative context, validates the request, performs state changes, and owns gameplay truth.

## Current Verified Authority Model

The current server owns:

- Scrap and Hype
- WorkshopLevel
- workshop assignment and occupancy
- recipe definitions and crafting results
- Signature Oddling ownership counts
- physical display reconciliation
- display-derived Hype production
- progression and recipe unlock reconciliation
- sanitized state replication
- schema-v1 persistent data and profile sessions
- authoritative cooldowns and request throttles

The current client owns only presentation and input responsibilities such as:

- HUD rendering
- local interface state
- camera
- input
- local visual feedback
- narrow requests defined by server-owned contracts

This section describes verified architecture. Future component, salvage-haul, and Custom Construct systems are not implemented merely because their security boundaries are specified later in this document.

## Request Model

Client:

**I would like to attempt X.**

Server:

**Is X valid for this player in this authoritative context?**

Server performs X only after successful validation.

The client is never proof that an action happened, a cost was affordable, a reward was earned, a recipe was unlocked, an object was nearby, or an assembly was compatible.

## Remote Contract Rules

No RemoteEvent or RemoteFunction should be added without documenting:

- name
- direction
- exact payload shape
- attacker-controlled fields
- type and bounds validation
- authorization and context checks
- rate limit
- authoritative state affected
- failure behavior

Each remote needs one narrow purpose. Do not add generic remotes that accept arbitrary action names, broad mutation tables, arbitrary Instance references, or client-authored state records.

Use the Player supplied by Roblox to OnServerEvent. Do not accept a client-provided Player identity for the acting user.

## Client-Originated Data Validation

Validate all relevant client input before a state change, reward, cost, spawn, generation step, or persistence update:

- type
- shape and argument count
- numeric finiteness and integer requirements
- numeric and string bounds
- enum or stable identifier membership
- ownership
- permissions
- proximity and world context
- current lifecycle state
- prerequisites
- rate limit

Server-side ProximityPrompt.Triggered is also an interaction signal, not automatic authorization. The server should still validate player state, encounter identity, ownership, and reasonable distance where those checks matter.

## Never Trust Client-Provided Values

Do not trust client-provided:

- currency balances
- prices or costs
- reward amounts
- rarity
- ownership claims
- unlock status
- production amount or interval
- workshop level or capacity
- purchase completion
- arbitrary server Instance references
- arbitrary transforms or positions
- persistence keys, namespaces, schema versions, or save payloads

The client may identify an allowed intent using bounded IDs. The server resolves definitions and context from trusted configuration and state.

## Malformed Input Threat Model

Implementation and tests should consider:

- nil or missing arguments
- extra arguments
- unexpected types
- negative, fractional, or huge numbers
- NaN and infinity where relevant
- oversized strings
- unexpected or cyclic tables
- invalid identifiers
- destroyed Instances
- Instances belonging to another player or system
- repeated, concurrent, or replayed requests
- requests during join, leave, profile loss, or shutdown boundaries

Failure should be boring: reject, optionally log or rate-limit, and leave authoritative state unchanged.

## Transactions and Rollback

Operations that exchange one authoritative resource for another must be treated as transactions.

Validate before mutation. Reserve or spend in a deliberate order. If a later required mutation fails, restore the earlier mutation when it can be done safely. Never let a client retry create a double reward, duplicate bank, negative balance, or charged-without-result state.

Derived presentation failure must not roll back valid ownership. For example, failure to create a physical model does not delete an already-authoritative Oddling.

## Rate Limiting

Rate limiting is required for:

- gameplay remotes
- expensive server operations
- repeated state-changing requests
- client-triggerable interactions where abuse matters

Limits are server-owned and fail closed. Client UI cooldowns improve presentation but provide no security.

Rate limits supplement validation. A request inside a limit can still be invalid.

## Economy and Progression Safety

Economy, crafting, upgrades, reward collection, unlocks, display production, and banking decisions must use server configuration and server-owned player state.

Clients submit intent, not results. A client must not request “give me 500 Hype,” “create a Legendary component,” or “advance my workshop.” It may request a documented action, after which the server independently decides the outcome.

## Persistence Safety

ODDWORKS currently uses server-only ProfileStore session handling with explicit schema-v1 validation and Studio mock isolation. The persistent payload is a compact authoritative subset; session-only and derived representations are reconstructed.

Clients must never choose:

- a DataStore key
- a profile owner
- a store namespace
- a schema version
- a raw save payload
- a session-release policy

Profile acquisition or session loss must fail safely. Gameplay must not continue on fake defaults when a returning player's authoritative profile cannot be acquired.

Any future persistence expansion requires a dedicated pass defining schema changes, migration, validation, failure behavior, rollback, test namespaces, and adversarial tests. Modular prototype data must not enter schema v1 as a side effect of unrelated work.

## Derived Representation

HUD state, runtime models, animations, display allocation, and workshop decoration are derived representations.

Derived systems may read safe snapshots or narrow server APIs. They must not become a second source of authority, and deleting a derived Instance must not delete ownership. Reconciliation should reconstruct representation from authoritative state where practical.

## Future Modular System Trust Boundary (Not Implemented)

The following rules constrain future Direction v2 systems. They do not claim that active salvage, component inventories, banking, frames, sockets, or Custom Constructs currently exist.

### Client May Request

- a salvage interaction or allowed extraction input
- an intent to bank the current haul
- an assembler selection using bounded IDs
- an allowed placement or rotation request for presentation

### Server Must Authoritatively Determine

- encounter identity, lifecycle, eligibility, and success
- reward identity and amount
- rarity
- unbanked and banked inventory
- component ownership and availability
- recipe or Signature recognition
- frame and socket compatibility
- authored attachment transforms
- Construct creation success
- server-generated unique IDs when persistent individual records require them
- deterministic stats and future bounded rolls
- persistent payload

The client must never submit a complete authoritative component or Construct record.

### Unbanked-to-Banked Transition

Future banking must be an atomic server-owned transition. It must defend against duplicate requests, disconnect timing, replay, and two simultaneous bank attempts. Ordinary salvage failure may discard the current unbanked haul but must not normally delete previously banked progression.

For Vertical Slice 0.2, banked components are protected only for the current server session; banking does not add them to ProfileStore schema v1. The server also owns the transition between banked availability and reserved or installed component state.

### Assembly and Placement

Future assembly must validate that the player owns each banked component and that each module is compatible with the chosen frame and socket. Attachment transforms come from server configuration, not arbitrary client CFrames.

If the client requests an allowed preview orientation or placement, the server must constrain it to owned context, allowed surfaces, workshop bounds, collision and footprint rules, and supported values before it affects authoritative state.

### Unique IDs

The one session-only Vertical Slice 0.2 PrototypeConstruct does not require a persistent GUID. When unique Construct records become necessary because multiple Constructs coexist, survive sessions, retain player-authored identity, or gain histories or trading, IDs must be generated or approved by the server. HttpService.GenerateGUID is a preferred Roblox-native option when globally unique IDs are justified. A client-provided ID is never proof of ownership or uniqueness.

## Third-Party Code and Services

Core gameplay should not depend on third-party web APIs. Open-source dependencies require source, license, maintenance, and security review before adoption.

Do not import Creator Store scripts, admin systems, networking frameworks, or opaque model behavior. Art assets must be sanitized before repository use.

## Logging and Privacy

Security-relevant failures should be identifiable without log flooding. Do not dump full player saves, private tables, access tokens, or massive client payloads into logs.

Logs support diagnosis; they are not authorization or persistent truth.

## Adversarial Testing Requirement

Economy, salvage, banking, assembly, persistence, and ownership passes require tests appropriate to their boundary. At minimum consider:

- malformed payloads
- invalid ownership
- impossible state transitions
- spam and concurrent attempts
- boundary values
- wrong-player context
- disconnect and rejoin timing
- missing derived assets
- multiplayer isolation

Codex must not claim security testing passed unless those tests were actually performed.
