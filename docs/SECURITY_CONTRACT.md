# ODDWORKS Security Contract

## Core Rule

THE CLIENT IS UNTRUSTED.

The Roblox client is responsible for presenting the game and requesting actions. The server decides what is valid, performs authoritative state changes, and owns the truth.

## Authority Model

The server is authoritative over:

- currencies
- crafting cost
- inventory
- ownership
- Oddling creation
- progression
- unlocks
- workshop ownership
- rewards
- purchases
- persistent data
- authoritative cooldowns
- production generation

The client is primarily responsible for:

- input
- camera
- UI
- presentation
- local visual effects
- requesting actions

## Request Model

Client:

I would like to do X.

Server:

Is X valid and permitted?

Server:

Performs X if valid.

The client should never be treated as proof that X happened, that X was affordable, that X was unlocked, or that X produced a specific reward.

## Remote Contract Rules

No RemoteEvent or RemoteFunction should be added without documenting:

- name
- direction
- payload
- validation
- authorization/context checks
- rate limit
- authoritative state affected
- failure behavior

Each remote should have a narrow purpose. Do not add generic remotes that accept arbitrary action names, arbitrary Instance references, or broad state mutation payloads.

## Client-Originated Data Validation

All client-originated data must be validated for relevant:

- type
- shape
- bounds
- enum or identifier membership
- ownership
- permissions
- proximity or context
- state prerequisites
- rate limits

Validation should happen before state changes, rewards, costs, generation, or persistence.

## Never Trust Client-Provided Values

Do not trust client-provided:

- currency balances
- prices
- reward amounts
- rarity
- ownership claims
- unlock status
- production amount
- purchase completion
- arbitrary server Instance references

The client may identify what it is trying to interact with, but the server must resolve and validate the authoritative object and player context.

## Malformed Input Threat Model

Future implementation and tests should consider malformed inputs including:

- nil
- unexpected types
- negative numbers
- huge numbers
- NaN where relevant
- infinity where relevant
- oversized strings
- unexpected tables
- invalid identifiers
- destroyed instances
- instances belonging to other players
- repeated or spam requests

Failure behavior should be boring: reject, optionally warn or rate-limit, and leave authoritative state unchanged.

## Rate Limiting

Rate limiting is required for:

- gameplay remotes
- expensive server operations
- client-triggerable interactions where abuse matters

Rate limits should be enforced server-side and should fail closed. Client UI cooldowns may improve feel, but they are not security.

## Economy And Progression Safety

Economy-sensitive code must be server-owned. Crafting, upgrade purchase, reward collection, unlocks, and production ticks should be derived from server-side definitions and server-side player state.

Do not let clients submit final results such as "give me 500 Hype" or "create this rare Oddling." Clients should submit requests such as "craft recipe Toastmarshal at station A," and the server should decide the outcome.

## Persistence Safety

Persistent data systems must be added in a dedicated pass. That pass must define:

- save schema
- load defaults
- migration strategy
- failure behavior
- retry strategy
- abuse cases
- test strategy

No production persistence should be introduced as a side effect of unrelated feature work.

## Adversarial Testing Requirement

Future economy/security-sensitive passes must include adversarial testing. At minimum, they should test invalid payloads, invalid ownership, impossible state transitions, repeated requests, and boundary values.

Codex must not claim security testing passed unless those tests were actually performed.
