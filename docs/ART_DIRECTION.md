# ODDWORKS Art Direction v2

## Status

This document is the active visual contract for ODDWORKS. The v2 identity is **chunky industrial toybox**: playful machinery, readable modular construction, and original characters living in a restrained salvage world.

The art should support the gameplay hierarchy. Oddlings and Constructs are the visual stars. The environment gives them context, contrast, and usable space without competing for attention.

## Active Art Identity: Chunky Industrial Toybox

ODDWORKS combines:

- playful industrial junk
- exaggerated proportions
- oversized bolts and fasteners
- hoses, springs, pipes, and practical connectors
- patched and repainted metal
- painted warning marks
- readable silhouettes
- cartoon weirdness
- evidence that objects were assembled, repaired, and personalized

The result should feel tactile and buildable, like a box of mismatched industrial toys that still belongs to one coherent universe.

ODDWORKS must not drift into:

- realistic gore
- grimdark realism
- muddy visual noise
- dense photorealistic scrap
- neon simulator soup
- copied meme, movie, game, or creator IP

## Visual Hierarchy

Signature Oddlings and Custom Constructs should be visually stronger than the environment. Their silhouettes, faces, moving parts, and player-selected modules should remain readable at normal Roblox camera distances.

The environment should usually use restrained materials and colors:

- dirty neutral metal
- concrete
- rust
- worn wood
- rubber
- faded industrial paint

Strong color has a gameplay or identity purpose:

- danger and salvage activity
- player accents
- success and stability
- anomalies and exotic discoveries
- important interactable landmarks

Color should guide attention, not cover every surface equally.

## Signature Art

Signature Oddlings are authored ODDWORKS characters such as Toastmarshal and a future production Conejurer.

Signature art may use:

- bespoke silhouettes
- bespoke rigs
- custom animation sets
- authored personality and performance
- special recipe or discovery presentation

Signature Oddlings do not need to conform to the modular frame grammar when a bespoke structure better expresses the character. They must still obey world placement, performance, originality, and workshop-footprint requirements.

## Modular Art

Custom Constructs are assembled from compatible authored modules. They use a controlled visual and technical grammar rather than unrestricted freeform sculpting.

Every modular asset must communicate its function and connection points clearly. Modules from very different themes must still look as if they were built in the same ODDWORKS workshop. Shared cues may include fastener scale, connector shapes, material roughness, paint treatment, edge language, and mechanical plausibility.

Modular work must obey the approved contract for:

- frame size
- socket identity
- orientation
- attachment transform
- rig compatibility
- collision and footprint assumptions
- silhouette
- ODDWORKS material and style language

An art or Blender pass must not independently change those contracts to make one asset convenient. Contract changes require an explicit gameplay-and-art review because they affect every compatible module.

## Planned Blender Socket Grammar

The first planned modular frame is **SmallBiped_v1**. Its prototype chassis and core geometry are built into the frame.

Its player-selectable module roles and socket vocabulary are:

- HeadModule -> HeadSocket
- ArmModule -> ArmSocket
- LegsModule -> LegsSocket

A Core is not selectable geometry in SmallBiped_v1. Cores remain available to future Signature Oddlings, advanced frames, major passives, and authored discoveries.

These names express intended roles only. Exact geometry, axes, transforms, scale, pivots, mirroring behavior, and rig relationships are intentionally not finalized in this direction-freeze pass.

Before modular assets enter production, a dedicated frame-contract pass must create and verify a canonical reference asset. Blender and art agents must author against that reference rather than inventing module scale or connection standards asset by asset.

That pass must also freeze whether ArmModule represents one selected visible arm plus a built-in frame arm or a paired-arm assembly, and whether LegsModule represents the complete paired lower-body assembly. Individual left/right customization is outside the first prototype.

## Frame and Size Classes

Conceptual frame classes are:

- Small
- Medium
- Large
- Colossal / Showcase

Frame class determines physical size and expected footprint. Rarity does not determine size. A Legendary Small component does not become physically enormous simply because it is rare.

Extremely large Constructs should eventually use a purpose-built showcase mechanic. Standard workshops must not be forced to accept unlimited dimensions or unsafe collision footprints.

## Component Readability

Component shape should suggest its gameplay domain without requiring a stat panel for basic comprehension:

- Arm / Tool: extraction
- Legs / Mobility: movement, stamina, or traversal
- Head / Sensor: detection or information
- Core: major identity or passive behavior
- Face / Showpiece: Hype and social presentation
- Back / Utility: carrying, protection, or utility

Rarity variants should remain recognizably related. Material, finish, added detail, and controlled effects may communicate Common, Rare, and Legendary tiers without destroying the base component silhouette.

The first modular prototype uses deterministic authored variants. It does not require random visual mutations or procedurally generated geometry.

One ComponentId uses one prototype model across Common, Rare, and Legendary metadata. Rarity may change configured effects and UI presentation, but it does not require separate Blender geometry in Vertical Slice 0.2. Small material or VFX distinctions may be considered later.

## Workshop and Display Art

Workshops should make creation and collection physically legible. Display positions, assembly locations, banking points, and upgrade landmarks should be understandable before decorative polish is added.

Display art may frame or decorate authoritative placement anchors, but it must not replace them. Decorative pads, rails, lights, and props are presentation. Server-owned slots and placement contracts remain gameplay truth.

Workshop art should support social comparison without making every plot a wall of effects. A visitor should be able to read what was built, what is rare, and where the owner has progressed.

## Salvage-Zone Art

Salvage spaces should visually distinguish risk from safety. Signals, extraction machinery, unstable objects, hazards, routes, and banking direction need readable silhouettes and restrained color coding.

Generic environment content may use carefully audited and documented third-party assets. Signature Oddlings, signature components, modular frame pieces, and defining ODDWORKS iconography should be original unless separately and explicitly licensed.

Decorative junk never becomes gameplay authority. A visual scrap pile may surround an encounter, but the server-controlled encounter and reward state determine what can be extracted.

## Physical Grounding

Characters, modules, props, and structures must follow docs/WORLD_PLACEMENT.md.

They should not appear unintentionally:

- floating
- buried
- clipping
- hovering because of guessed offsets

Intentional hovering is allowed only when it is an authored behavior. Modular pivots and socket transforms do not remove the need to measure the final assembled Construct's ground contact and footprint.

## Originality and Asset Safety

Do not use or create:

- direct copies of existing meme or brainrot characters
- copyrighted characters or recognizable third-party creatures
- trademark or logo copies
- internet celebrity likenesses
- ripped Roblox models
- near-identical parody assets
- imported scripts or behavior hidden inside art assets

ODDWORKS should create original objects capable of becoming memorable, not borrow recognition from somebody else's IP.

Third-party assets require documented source, creator, usage status, review, and sanitization. Availability in the Creator Store or another experience does not prove permission or safety.

## Art Review Questions

Before accepting a Signature or Modular asset, ask:

1. Is the silhouette readable at the expected camera distance?
2. Does it feel like ODDWORKS rather than a borrowed universe?
3. Is function or personality legible?
4. Does it obey the approved frame, socket, orientation, and placement contracts?
5. Are pivots, bounds, collision, and footprint suitable for Roblox runtime use?
6. Does its color support the scene hierarchy?
7. Is asset provenance clear?
8. Is this appropriate for the current prototype rather than speculative future production?
