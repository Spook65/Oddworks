# ODDWORKS Game Direction

## High Concept

ODDWORKS is a social collection/workshop game built around:

collect -> craft -> display -> earn -> upgrade -> flex -> repeat

Players gather strange materials and junk, create original absurd creatures called Oddlings, display them physically in their workshop, earn progression from their collection, upgrade the workshop, unlock stranger creations, and show their collection to other players.

The current keycard/core arena is not the production game. It is a temporary toolchain-validation prototype.

## Player Fantasy

The player should feel like they operate an increasingly ridiculous workshop full of bizarre living creations.

Progress should be physically visible in the world rather than existing only inside inventory menus. A stronger player should have a workshop that looks, moves, sounds, and feels stranger than it did five minutes ago.

## Core Design Principles

- Immediately understandable actions: gather, craft, place, upgrade, visit.
- Short satisfying sessions: a player should accomplish something meaningful in a few minutes.
- Visible progression: upgrades and collections should appear physically in the world.
- Collection focus: Oddlings are the emotional and social center of the game.
- Upgrade focus: the workshop should become more capable and more expressive over time.
- Social status and flex: players should want others to see what they built and collected.
- Surprising original characters: Oddlings should be weird, readable, funny, and ownable as ODDWORKS creations.
- Low initial mechanical complexity: the first session should be easy to understand without a tutorial wall.
- Depth layered on top of simple actions: recipes, variants, placement, upgrade choices, and social play can add depth after the core loop is clear.

Simple player-facing gameplay does not require simple internal engineering. Internally, systems should still be secure, testable, modular, and server-authoritative.

## Vertical Slice 0.1

Vertical Slice 0.1 should prove the core loop at small scale:

- 1 small playable junkyard/workshop environment
- multiplayer-compatible architecture
- at least 2 workshop plots
- Scrap resource
- Hype progression resource
- several salvage nodes
- one crafting station
- Toastmarshal as the first functional Oddling
- Conejurer as a second recipe/unlock
- physical Oddling display
- one workshop upgrade
- minimal HUD
- server-authoritative state

Vertical Slice 0.1 explicitly excludes:

- persistence initially
- monetization initially
- trading
- rebirths
- quests
- daily rewards
- global leaderboard
- large content catalogue

## First Session Target

Target first-session path, roughly 2 to 5 minutes:

1. Spawn into a small junkyard/workshop space.
2. Gather Scrap from obvious salvage nodes.
3. Use one crafting station to craft the first Oddling.
4. See the Oddling physically appear in the workshop.
5. Begin earning Hype from the displayed Oddling.
6. Spend Hype or Scrap on one workshop upgrade.
7. Discover the next goal, such as unlocking Conejurer or improving the workshop display.

The first session should leave the player with a visible before/after change in their space.

## Feature Test

Any proposed feature that does not strengthen:

collect -> craft -> display -> earn -> upgrade -> flex

requires explicit justification before implementation.

## Product Ceiling

Future possibilities include:

- more Oddlings
- mutations and variants
- more regions
- workshop customization
- social visiting
- collection achievements
- co-op mechanics
- analytics
- compliant monetization

These are future possibilities, not MVP commitments.
