# ODDWORKS Salvage Design Contract

## Status

This is the active design contract for future active-salvage work in ODDWORKS Direction v2.

The current server-validated SalvageService remains useful as a security and economy proof. Its repeated prompt-to-Scrap interaction is not the final salvage experience described here. Everything marked future in this document is a design requirement, not a claim about implemented gameplay.

## Player Promise

Salvage should make the player feel that they found something strange, worked to recover it, and made a meaningful decision about getting it home.

The simple promise is:

**Find weird parts, get them home, build weird creatures.**

The primary field verbs are:

**Find -> Extract -> Escape / Bank**

## Active Salvage Rule

Meaningful components require an activity, extraction, challenge, discovery, or risk. A repeated hold-to-interact reward can support onboarding or common utility, but it must not carry the full progression economy by itself.

An active salvage opportunity should normally include:

1. A readable signal or discovery.
2. A server-authoritative encounter context.
3. An extraction activity or commitment.
4. A component or haul that is temporarily unbanked.
5. A complication, decision, or route back to safety.
6. A clear banking transition.
7. A workshop use for the recovered material.

The first prototype needs only one forgiving encounter. It does not need a catalog of unrelated minigames.

## Core Salvage Loop

The intended loop is:

**Explore -> Find Salvage Signal -> Active Extraction -> Obtain Unbanked Haul -> Survive Complication or Choose Whether to Push Farther -> Return to Safe Workshop -> Bank Components**

Long-term, banked components can feed assembly, display, Hype, and progression. Vertical Slice 0.2 stops at a visible PrototypeConstruct and does not require Custom Construct Hype.

## Salvage Complication Philosophy

Salvage complication is a reusable design umbrella. It does not mean every encounter becomes a monster chase.

Possible future complications include:

- guardian activation
- unstable-core timer
- machinery or security activation
- environmental hazard
- closing route
- optional deeper valuable signal
- push-your-luck decision

Complications should fit the object, zone, and desired pace. They should create a legible problem rather than arbitrary punishment.

## Unbanked and Banked State

Ordinary salvage failure should place the **current unbanked haul** at risk.

For Vertical Slice 0.2, the state boundary is:

- **UNBANKED:** vulnerable temporary salvage-run state owned by the server
- **BANKED:** protected temporary component inventory for the current server session

Banked does not mean ProfileStore-persistent during this experiment. Production schema v1 remains unchanged. Persistence for components and Constructs requires a later migration only after the modular loop passes its human fun and technical gates.

The following should normally remain safe:

- previously banked components
- owned Signature Oddlings
- owned Custom Constructs
- established workshop progression
- prior collection discoveries

This boundary lets field play carry tension without teaching players that their collection can disappear unpredictably.

Banking is an authoritative state transition, not a client presentation event. Vertical Slice 0.2A must define exactly when an unbanked component enters protected session inventory and make the transition resistant to duplication, disconnect races, and replayed requests.

## Unbanked-Haul Legibility

The player must clearly understand when they are carrying unbanked loot and therefore what is currently at risk.

Future presentation may use a HUD indicator, a carried container or component, a backpack or haul visualization, or another clear mechanism. This correction pass does not choose the final presentation.

The visual and UI representation is derived. Server-owned UnbankedComponents state remains authoritative even if presentation is missing, delayed, or locally altered.

## Push-Your-Luck Decision

A future salvage route may offer a safe opportunity to bank a valuable haul while revealing a potentially better signal deeper in the zone.

The decision is:

**BANK NOW**

or

**PUSH FARTHER**

The player should receive enough information to understand that a choice exists. Failure after pushing farther risks the current unbanked haul, not old owned progression.

## Resource Roles

### Scrap

Scrap is a fungible common construction currency used for general utility, workshop upgrades, and assembler or building costs.

### Components

Components are physical build pieces such as Servo Arm, Clown Face, or Zombie Legs. They are recovered and banked through salvage, then used by controlled assembly rules.

### Cores and Blueprints

Cores and Blueprints are stronger identity or progression pieces. They may enable Signature Oddlings, advanced Constructs, unusual frames, or special assembly possibilities.

These resource classes are conceptual Direction v2 contracts. Components, Cores, Blueprints, and unbanked-haul state are not implemented yet.

## Rarity and Opportunity

The initial conceptual rarity ladder is:

- Common
- Rare
- Legendary

Rarity should primarily come from:

- zone difficulty
- encounter or opportunity quality
- extraction performance
- special conditions
- controlled randomness

Progression should unlock better opportunities. It should not make an unchanged starter junk pile inexplicably produce endgame Legendary rewards.

The first modular prototype uses deterministic configured effects for part type and rarity. It does not add random per-instance stat rolls.

## World Contract

Future world work must provide:

- a readable salvage encounter space
- a recognizable safe workshop and banking zone
- traversal that makes the movement between risk and safety meaningful
- clear sight lines or landmarks
- separate player workshops
- space for future modular display footprints
- social visibility without allowing decorative content to become authority

The unaccepted Pass 13 environment prototype is reference work only. A future redesign should build around the Direction v2 loop rather than polish the old fixed-crafting layout in isolation.

## Future Server Trust Boundary

This section describes future requirements, not implemented networking.

The client may request or signal:

- an attempt to interact with a salvage encounter
- an allowed extraction input
- an intent to bank
- an assembler selection later in the loop

The server must determine:

- whether the encounter exists and is active
- whether the player is eligible and in valid context
- extraction progress and success
- complication state
- reward identity and rarity
- whether a haul is unbanked or protected in temporary session inventory
- component ownership
- all persistent payloads

The client must never submit a complete authoritative reward or component record. Client timing, position claims, completion claims, and displayed UI are attacker-controlled inputs and require server validation.

## First Active-Salvage Prototype

The first experiment should contain one forgiving active salvage encounter and only enough temporary component state to answer whether recovery feels better than repeated prompt collection.

It should prove:

**active salvage -> temporary component reward -> safe banking -> simple assembly input**

It should not introduce a large zone catalog, procedural missions, multiple currencies, random item rolls, trading, offline production, or production persistence migration.

## Evaluation Questions

1. Does finding the signal create curiosity?
2. Does extraction require a meaningful action?
3. Is the current unbanked risk understandable?
4. Is the route or decision back to safety readable?
5. Does the recovered component create anticipation for assembly?
6. Can the server reconstruct and validate every reward transition?
7. Is the encounter still enjoyable without rare rewards?

If active recovery is not more engaging than the existing Scrap prompt, adding more rarity or content will not solve the core problem.

## Explicitly Deferred

The first active-salvage prototype does not include:

- dozens of encounter types
- every complication listed above
- random rolled component stats
- affixes or mutations
- PvP stealing
- destructive loss of banked collections
- offline production
- quests
- trading
- monetization
- runtime AI-generated encounters or rewards
