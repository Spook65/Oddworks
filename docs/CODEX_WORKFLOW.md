# ODDWORKS Codex Workflow

## Active Product Lens

Gameplay and art passes must treat ODDWORKS as:

**Salvage Adventure + Modular Invention + Collection / Workshop**

The active player-facing loop is:

**Find -> Extract -> Escape / Bank -> Assemble -> Flex**

The simplest expression is:

**Find weird parts -> get them home -> build weird creatures.**

Do not optimize future development around the old Scrap-to-fixed-pet loop. Existing fixed crafting, Toastmarshal, workshops, Hype, persistence, and display systems are valuable technical foundations, but they are not the complete product direction.

## Contracts to Read

Before a significant pass, read the documents relevant to its behavior:

- GAME_DIRECTION.md for the product north star
- ART_DIRECTION.md for visual language and art categories
- SALVAGE_DESIGN_CONTRACT.md for extraction, risk, and banking
- MODULAR_ODDLING_CONTRACT.md for frames, components, sockets, and Constructs
- SECURITY_CONTRACT.md for authority and attacker-controlled inputs
- VERTICAL_SLICE_PLAN.md for current experiment boundaries
- WORLD_PLACEMENT.md for physical placement
- PERSISTENCE.md for the verified schema and session lifecycle
- MONETIZATION_CONTRACT.md before any commercial design

If a prompt conflicts with an active contract, identify the conflict before implementation. Do not silently follow an obsolete assumption.

## Questions for Meaningful Progression

For every meaningful progression feature, answer:

1. What does the player physically do to earn this?
2. What is at risk?
3. What is banked and safe?
4. What is server-authoritative?
5. What is persistent truth?
6. What is derived representation?
7. Does this strengthen Find -> Extract -> Escape -> Assemble -> Flex?
8. Is this MVP or future depth?

A feature that cannot answer these questions is not ready for implementation.

## Required Workflow for Significant Passes

Each significant implementation pass should:

1. Read the relevant contracts.
2. Inspect the current implementation and repository state.
3. State the affected system and the player action being changed.
4. Identify authoritative, persistent, session-only, and derived state.
5. Identify client/server authority boundaries.
6. Identify attacker-controlled inputs when networking or world interactions are involved.
7. Make the smallest complete change that tests the current hypothesis.
8. Avoid unrelated refactors and speculative modules.
9. Run available static, dependency, and build verification.
10. Sync and test in Studio where practical.
11. Inspect Output and runtime hierarchy.
12. Perform adversarial and multiplayer tests when authority or lifecycle is involved.
13. Report exactly what changed.
14. Report what could not be verified.
15. Suggest one focused commit without committing unless explicitly requested.

## Prompt and Report Shape

Future Codex prompts and reports should respect:

- Project
- Task
- Current problem
- Goal
- Allowed files
- Do not touch
- Out of scope
- Implementation requirements
- Security requirements
- Monetization and legal notes
- Verification
- Acceptance
- Output report
- Suggested commit

## Scope Discipline

Do not add new features merely because they may be useful later.

Finish the requested pass, verify it honestly, and leave future features for future prompts. Helpful ideas belong in risks or next-pass recommendations, not hidden implementation.

In particular, do not turn the first modular experiment into a full inventory, procedural item, base-building, companion, or persistence rewrite.

## Do Not Touch vs Out of Scope

**DO NOT TOUCH** means existing systems or files that must not be modified.

**OUT OF SCOPE** means functionality that must not be implemented yet.

Codex must respect both. Permission to edit a file does not authorize an out-of-scope feature, and a relevant future feature does not override a protected file.

## Gameplay Codex Contract

The Gameplay agent should prefer concrete player verbs over passive numbers. For a salvage or progression pass it must define:

- the physical action
- the authoritative encounter or workshop context
- success and failure conditions
- the unbanked-to-banked boundary
- the smallest state mutation required
- how existing systems derive presentation from that truth

The agent must preserve verified architecture where it fits. It should add narrow APIs to existing service owners rather than bypassing encapsulation or creating a competing state system.

The Gameplay agent must not treat more rarity, longer timers, or larger prices as substitutes for an enjoyable interaction.

## Blender and Art Codex Contract

The Blender or Art agent must distinguish:

### Signature Art

Signature art is bespoke character identity. It may use authored silhouettes, rigs, and animation that best serve an original ODDWORKS character.

### Modular Art

Modular art is frame-and-socket-compatible construction content. It must obey the approved:

- frame size
- socket identity
- orientation
- attachment transform
- rig compatibility
- collision and footprint assumptions
- silhouette requirement
- ODDWORKS material and style language

The art agent must not independently change those contracts. If exact geometry or transforms have not been approved, it should stop at specification or reference work rather than producing incompatible assets by guesswork.

All art work must retain source/interchange/runtime separation, provenance, and the repository's existing reproducible asset pipeline.

## Authoritative, Persistent, and Derived State

Every pass should name its data category:

- **Authoritative state**: server-owned gameplay truth.
- **Persistent state**: the compact subset of authoritative state saved across sessions.
- **Session-only state**: authoritative state valid only in the current server session.
- **Derived representation**: models, HUD, animation, display allocation, and other reconstructable presentation.

Do not persist derived models or duplicate static configuration into player saves. Do not allow presentation failure to corrupt authoritative ownership.

Schema-v1 persistence remains active. Modular prototype data must not enter it without a dedicated migration and validation pass.

## Security and Monetization Gates

Networking, economy, component inventory, banking, assembly, persistence, rewards, purchases, and ownership changes must consult the relevant contracts before implementation.

Security-sensitive passes require adversarial tests. Monetization-sensitive passes require policy, legal, UX clarity, and technical-security review. Vertical Slice 0.2 remains free of monetization.

## External Services and Dependencies

Core ODDWORKS gameplay should not depend on third-party web APIs.

Prefer Roblox-native capabilities where justified:

- DataStoreService with the verified ProfileStore integration
- MemoryStoreService
- MessagingService
- PathfindingService
- HttpService.GenerateGUID for server-generated IDs
- Roblox networking, text filtering, and analytics

Open-source Luau or Wally packages may be introduced only for a clear infrastructure problem after:

- source review
- license review
- maintenance review
- security review

Do not add a dependency merely to avoid writing a small, understandable piece of gameplay logic.

## Source of Truth

Filesystem-managed Luau is canonical.

Roblox Studio is appropriate for world authoring, visual inspection, and runtime testing. Rojo-managed scripts must not diverge from root src. Source-controlled Roblox models and persistent world content must remain reconstructable through the canonical root project.

Art source, interchange exports, and Roblox runtime templates must stay clearly separated according to the existing asset pipeline.

## Truthful Verification

Codex must never claim:

- Studio testing passed
- Rojo build passed
- multiplayer testing passed
- security testing passed
- persistence testing passed
- visual review passed
- static analysis passed

unless that verification was actually performed.

When verification cannot be performed, report it plainly. Setup through the Studio developer harness may arrange a scenario, but it does not prove a bypassed production mechanic works.

## Current Experiment Guardrail

Vertical Slice 0.2 exists to answer one question:

**Is actively recovering parts and building a creature substantially more fun than collecting Scrap and pressing a fixed craft button?**

Do not scale content, migrate persistence, or authorize a large modular-art pass until the end-to-end prototype and human play review provide evidence.
