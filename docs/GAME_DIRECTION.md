# ODDWORKS Game Direction

## Direction Freeze v2

This document is the active product direction for ODDWORKS. Vertical Slice 0.1
remains valuable as a verified technical foundation, but its fixed
Scrap-to-recipe loop is not the final product target.

Focused implementation boundaries live in:

- [Salvage Design Contract](SALVAGE_DESIGN_CONTRACT.md)
- [Modular Oddling Contract](MODULAR_ODDLING_CONTRACT.md)
- [Vertical Slice Roadmap](VERTICAL_SLICE_PLAN.md)

## North Star

ODDWORKS is a social salvage-and-invention adventure where players venture
into strange junk zones, recover valuable components through active
extraction, survive complications long enough to bank their haul, and combine
those components into personalized Constructs or discover authored Signature
Oddlings.

Creations generate workshop Hype, make collections physically visible, and
eventually help players reach stranger and more dangerous salvage
opportunities.

The player-simple version is:

**FIND WEIRD PARTS -> GET THEM HOME -> BUILD WEIRD CREATURES**

Primary player verbs:

**FIND -> EXTRACT -> ESCAPE / BANK -> ASSEMBLE -> FLEX**

## Core Loop

**EXPLORE -> FIND SALVAGE SIGNAL -> ACTIVE EXTRACTION -> OBTAIN UNBANKED HAUL
-> SURVIVE COMPLICATION / CHOOSE WHETHER TO PUSH FARTHER -> RETURN TO SAFE
WORKSHOP -> BANK COMPONENTS -> ASSEMBLE -> DISPLAY -> GENERATE HYPE -> IMPROVE
WORKSHOP / ACCESS -> REPEAT**

The detailed loop may gain depth, but it must continue to read simply as:
find weird parts, get them home, build weird creatures.

## Design Pillars

### Active Salvage

Meaningful components require an activity, extraction, challenge, discovery,
or risk. Repeatedly holding one prompt for a guaranteed fungible reward is not
the long-term salvage fantasy.

### Invention

Players combine compatible components through a controlled modular grammar to
create personalized Constructs. Choices should produce visible, understandable
differences rather than arbitrary complexity.

### Signature Discovery

ODDWORKS retains authored characters such as Toastmarshal. Signature Oddlings
carry bespoke identity, silhouettes, personality, animation, and discovery
paths that modular construction should not dilute.

### Workshop Ownership

Progress lives physically in the player's workshop. Displays, upgrades,
Constructs, Signature Oddlings, and future assembly capabilities should make
advancement visible without requiring an inventory screen.

### Social Spectacle

Other players should be able to understand and enjoy a workshop's impressive,
strange, or funny creations. Future world events may create shared spectacle,
but social systems must grow from meaningful play rather than replace it.

### Push Farther

Progression and better builds should eventually open stranger salvage
opportunities. Advancement unlocks better encounters, information, access, and
choices rather than making a starter junk pile produce endgame rewards.

## Player Fantasy

The player operates an increasingly ridiculous workshop while becoming capable
of returning from increasingly strange expeditions. They should feel clever
for finding and safely extracting unusual parts, inventive when assembling
them, and proud when another player sees the result.

## Salvage Complications

"Salvage complication" is the reusable design umbrella, not a synonym for
"monster chase."

Possible future complications include:

- guardian activation
- unstable-core timer
- machinery or security activation
- environmental hazard
- closing route
- optional deeper valuable signal
- push-your-luck decision

Ordinary salvage failure should normally threaten the current unbanked haul.
Banked progression, owned Constructs, and Signature Oddlings should not
normally be lost.

## Push-Your-Luck Decision

A future expedition may offer a safe opportunity to bank a valuable haul while
revealing a potentially better opportunity deeper in the zone.

The intended decision is **BANK NOW or PUSH FARTHER**.

Failure risks current unbanked haul, not the collection earned before the
expedition.

## Resource Model

### Scrap

Scrap is fungible common construction currency used for workshop upgrades,
assembler or building costs, and general utility. It is not a substitute for
specific physical components.

### Components

Components are physical build pieces recovered and banked through salvage.
Examples include Servo Arm, Clown Face, and Zombie Legs. Exact production
content is not committed by these examples.

### Cores And Blueprints

Cores and blueprints are stronger identity or progression pieces. They may
enable Signature Oddlings, advanced Constructs, special frames, or authored
capabilities.

These resource classes are design contracts only; Components, Cores, and
Blueprints are not implemented yet.

## Rarity Philosophy

The initial conceptual rarity ladder is **Common -> Rare -> Legendary**.

Rarity should primarily come from:

- zone difficulty
- encounter or opportunity
- extraction performance
- special conditions
- controlled randomness

Progression unlocks better opportunities. A starter junk pile should not
magically produce endgame Legendary rewards.

The first modular prototype uses deterministic configured effects for each
part type and rarity. It does not use random per-instance stat rolls. Future
numeric variation may exist only within bounded component domains, while
special behaviors remain authored.

## Signature Oddlings And Custom Constructs

### Signature Oddlings

Signature Oddlings include Toastmarshal and a future production Conejurer.
They have authored ODDWORKS identity, bespoke silhouettes and personality,
bespoke animation where appropriate, finite Oddling Index entries, and
authored recipe, blueprint, or discovery paths.

### Custom Constructs

Custom Constructs use player-selected compatible modules and a controlled
frame/socket grammar. They may eventually be named by players. Individual
builds belong to "My Builds" and do not each become canonical species or
Oddling Index entries.

This separation protects ODDWORKS character identity while supporting player
creativity.

## Future Collection Information Architecture

Future collection presentation should distinguish:

- **Oddling Index:** authored Signature discoveries
- **Part Catalog:** discovered component types
- **My Builds:** individual player-created Constructs

This is information architecture, not a commitment to implement collection UI
in the next pass.

## Workshop And Hype

Hype remains workshop reputation and attention.

Displayed creations generate Hype. Workshop and Hype progression may
eventually unlock:

- workshop expansion
- more display capacity
- assembler capability
- salvage access
- event access

Hype should not become a second generic Scrap currency. Hype represents what
the workshop attracts or proves; Scrap remains practical construction utility.

## Future Field Role

The possible long-term split is **DISPLAY -> generates Hype** and
**DEPLOY -> assists salvage expedition**.

Component domains are designed partly so Constructs could eventually affect
expeditions. Field companions are future depth, not part of the first modular
prototype.

## First-Session Target

Conceptual target:

- 0:00: spawn and understand workshop and salvage directions
- within the first minute: perform a forgiving active salvage interaction
- around minute one: return with first components
- around minute two: assemble or reveal the first creation
- immediately afterward: understand display/Hype and see the next desirable
  salvage objective

These times are design targets, not contractual guarantees.

## Progression Direction

Preferred long-term progression currently includes:

- Workshop Level
- salvage access or rank
- assembler capability
- component catalog
- Signature Index
- stronger and stranger Builds

Destructive prestige or rebirth is not part of the current core direction.
Do not delete a player's collection merely to grant a multiplier.

## Discovery And Shareability

ODDWORKS should not be designed purely for social-media manipulation. Normal
gameplay should nevertheless create memorable moments:

- close extraction escape
- rare component discovery
- absurd custom Construct reveal
- Signature Oddling discovery
- anomaly or event
- impressive workshop

Gameplay should create the clip. Marketing should not need to make mundane
gameplay appear exciting.

## Existing Technical Foundation

The following verified systems remain useful:

- PlayerStateService
- PersistenceService
- WorkshopService
- OddlingDisplayService
- HypeService
- CraftingService
- ProgressionService
- StateReplicationService
- Studio-only developer harness
- Toastmarshal production asset pipeline

They are not wasted work. Several will evolve:

- PlayerState and Persistence may later represent banked Components and Builds.
- Crafting may evolve into assembler transactions while retaining server
  authority and rollback principles.
- OddlingDisplayService may evolve into a broader creation-display layer.
- Workshop and Hype remain core progression foundations.
- SalvageService is a secure interaction proof, not the final active-salvage
  design.

## Next Experiment

Vertical Slice 0.2 is the Salvage + Modular Invention Proof:

**active salvage -> temporary component reward -> safe banking -> simple
assembly -> visible modular Construct**

Its question is:

> Is actively recovering parts and building a creature substantially more fun
> than collecting Scrap and pressing a fixed craft button?

Do not commit to persistence migration, full inventory, massive world redesign,
or large modular-art production until that question has evidence.

## Feature Test

Meaningful progression features must strengthen:

**FIND -> EXTRACT -> ESCAPE -> ASSEMBLE -> FLEX**

If they do not, they require explicit justification.
