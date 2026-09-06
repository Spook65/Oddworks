# Toastmarshal Art Specification

## Purpose

This document defines the Common/base Toastmarshal before production modeling begins.

Toastmarshal currently exists as gameplay data through recipe id `Toastmarshal` and owned Oddling counts. This specification gives the first production model a stable visual target for Pass 5.6.

Do not treat this document as permission to create `toastmarshal.blend`, production meshes, textures, rigs, exports, Roblox imports, or gameplay code.

## One-Sentence Fantasy

Toastmarshal is an absurd, tiny, over-serious kitchen marshal: a confident toasted commander who treats snack-time scraps like a grand workshop campaign.

## Originality Rule

Toastmarshal must be an original ODDWORKS character created internally.

Do not intentionally imitate meme characters, Pokemon, copyrighted mascots, existing Roblox pets, anime/game characters, or near-identical parody designs. Generic ingredients such as toast, frying pans, kitchen tools, badges, and marshal/commander language may be combined into an original ODDWORKS design.

All production Toastmarshal geometry, rigging, animation, and character-specific texture work should be created internally unless a future supporting asset has documented provenance in [Asset Provenance](../ASSET_PROVENANCE.md).

## Character Personality

Toastmarshal should feel:

- funny,
- confident,
- slightly ridiculous,
- cute enough to collect,
- serious about a mission that is obviously too small for the drama.

Avoid scary, realistic, grotesque, gritty, or derivative treatment. The joke is not that Toastmarshal is incompetent; the joke is that a tiny toast-bodied marshal behaves like a decorated commander in a salvage workshop.

## Silhouette

The base silhouette should be readable at Roblox gameplay distance and mobile screen sizes.

Chosen silhouette direction:

- chunky rounded toast body as the largest visual mass,
- oversized frying-pan marshal helmet sitting like a dramatic command cap,
- one readable spatula-saber held or worn as the signature tool,
- small expressive limbs that support the body without competing with it.

Must remain recognizable in future variants:

- toast-based body outline,
- pan/helmet marshal identity,
- front face placement on the toast body,
- compact body with oversized headgear/tool proportion language.

Avoid many tiny attachments, dangling charms, elaborate straps, or silhouette clutter on the Common version.

## Proportions

Use approximate relative proportions for v0.1 modeling:

- Body: largest mass, roughly 55-65% of total visual height excluding tool extremes.
- Face: on the front of the toast body, large enough to read from distance.
- Arms: small to medium, expressive, and secondary to the toast body.
- Legs: short, sturdy, and visibly grounded.
- Pan/helmet: intentionally oversized, roughly wider than the toast crown but not so large that it hides the body.
- Spatula-saber: one clear tool, large enough to read as a prop but not larger than the character's main body.

These proportions support industrial toybox absurdism: simple chunky masses, one strong joke, and a collectible toy-like read instead of realistic anatomy.

## Face

The face sits on the front broad face of the toast body.

Baseline facial language:

- two simple dark oval eyes,
- small stern-but-cute mouth,
- slight brow/eye angle or eyelid shape suggesting over-serious confidence,
- no tiny eyelashes, teeth, wrinkles, or high-resolution facial detail required.

The face should read as "tiny commander taking this seriously" at small sizes. Use bold shapes and high contrast rather than texture-heavy details.

## Signature Equipment

Common Toastmarshal uses two signature equipment ideas:

- Pan/marshal helmet: an upside-down or fitted frying-pan-like helmet with a simple brim/lip that reads as commander headgear.
- Spatula-saber: a single stylized spatula tool carried like a command saber or baton.

Do not add multiple weapons, medals, capes, backpacks, crowns, or aura effects to the Common version. Those are variant space.

## Body Construction Plan

Plan the Blender model around meaningful authoring pieces:

- toast body mesh,
- face geometry or face texture region,
- left arm,
- right arm,
- left leg,
- right leg,
- pan/helmet accessory,
- spatula-saber accessory.

The final asset should follow the verified rigged Oddling pipeline in [Blender Pipeline](../BLENDER_PIPELINE.md), not the simple rigid prop merge rule. Pieces may be separate authoring objects if helpful, but the production import should be planned around a rigged/skinned character structure rather than loose unconnected Roblox parts.

## Rig Plan

Use the minimum initial Toastmarshal skeleton needed for display and simple animation:

```text
Root
-> Body
   -> Face
   -> Arm_L
   -> Arm_R
   -> Leg_L
   -> Leg_R
   -> Helmet
   -> Tool_R
```

Proposed bone roles:

- `Root`: grounded placement/reference bone, no primary deformation.
- `Body`: main toast body deformation and idle bob control.
- `Face`: optional reference/attachment bone for face plane, face texture region, or simple expression testing.
- `Arm_L`, `Arm_R`: arm deformation or rigid limb movement.
- `Leg_L`, `Leg_R`: short leg deformation or rigid leg movement.
- `Helmet`: attachment/control bone for the pan helmet if it needs independent bounce or tilt.
- `Tool_R`: attachment/control bone for the spatula-saber.

Keep the v0.1 rig small. Do not build facial rigs, fingers, IK systems, walk cycles, or complex controllers until a production need appears.

## Animation Plan

Minimum initial animation set:

- `IDLE`: required for first display. Should include a tiny proud bounce, subtle helmet settle, and maybe a small tool twitch.
- `WORK_PRODUCE_HYPE`: planned later for a display loop when Hype production becomes physical.
- `SPAWN_CRAFT_REVEAL`: optional future animation for the crafting reveal.

Do not scope walk, run, combat, emote catalogue, or facial animation for the first production model. Toastmarshal's current role is workshop collectible/display Oddling, not a player-controlled combat character.

## Common Appearance

Common Toastmarshal should be visually modest so future variants have room to grow.

Base palette direction:

- Bread center: warm toasted tan.
- Crust: deeper golden brown.
- Pan/helmet: soft dark iron or blue-gray metal.
- Face: dark charcoal eyes and mouth.
- Accent: small butter-yellow or red-orange marshal detail.
- Tool: pale metal spatula head with a darker handle.

Use a limited stylized palette with strong material contrast. Avoid photoreal crumbs, realistic burn marks, excessive grunge, glowing eyes, giant auras, or rare-looking effects on the Common version.

## Texture Plan

Use the verified early ODDWORKS appearance path from [Blender Pipeline](../BLENDER_PIPELINE.md):

```text
Blender mesh
-> intentional UV map
-> small albedo/base-color texture
-> GLB with embedded image
-> Roblox 3D Importer
-> MeshPart.TextureID
```

Plan a small stylized albedo texture with:

- broad bread/crust color blocks,
- simple face shapes,
- small marshal accent,
- optional very soft toast variation only if it remains readable.

Do not maximize texture resolution by default. Choose the smallest resolution that supports the actual v0.1 read during modeling. Early target: start around `128x128` or `256x256` only if the face and crust shapes need the extra room.

## Geometry Direction

Follow industrial toybox absurdism:

- chunky forms,
- clean silhouette,
- smooth enough curves where they matter,
- efficient topology,
- low to moderate detail,
- exaggerated proportions,
- readable from medium/far distance.

Avoid photoreal bread, hyper-detailed metal, microgeometry crumbs, dense bevel clutter, or a production triangle budget before measuring the real model in-game.

## Scale Target

Toastmarshal should feel collectible and visible beside a normal Roblox avatar without feeling giant.

Initial target: approximately 35-60% of a normal Roblox avatar's total height after import. The Common version should land closer to the middle of that range unless readability testing says otherwise.

Do not lock exact Blender units until Pass 5.6 creates and imports the real v0.1 model.

## Grounding Rule

Toastmarshal's logical ground point is the bottom of its feet or lowest intentional contact points.

Author the Blender source with deliberate grounding, predictable bounds, and a clear root/pivot strategy. Follow [World Placement](../WORLD_PLACEMENT.md): do not assume the Blender pivot alone guarantees Roblox ground contact. Runtime placement may need model bounds, pivot-to-bottom offsets, and `Model:GetBoundingBox()` checks.

## Duplicate Display Consideration

Gameplay already allows duplicate Toastmarshal ownership counts:

```text
OwnedOddlings.Toastmarshal
0 -> 1 -> 2 -> 3 ...
```

Common Toastmarshal should look good when several are displayed together in one workshop. Avoid huge silhouettes, noisy attachments, oversized VFX, or sprawling poses that make 3-5 Common Toastmarshals visually crowd the display area.

## Future Variant DNA

Do not lock mutation or rarity names in this pass.

Must keep across variants:

- toast-based silhouette,
- pan/marshal identity,
- recognizable front face placement,
- compact body with oversized equipment,
- confident over-serious personality.

May change in future variants:

- crust/material treatment,
- pan shape/details,
- tool shape/details,
- size,
- accessories,
- glow/VFX,
- animation personality,
- mutation features.

Future variants should not rely on "same model, different color" alone. Strong variants should combine multiple noticeable changes such as proportions, geometry, accessory treatment, texture/material, VFX, animation, or size.

## Mobile And Distance Readability

Toastmarshal must remain recognizable on desktop, mobile-sized views, and medium/far gameplay distance.

Prioritize:

- large face shapes,
- one strong body silhouette,
- one readable helmet shape,
- one readable tool.

Do not put core identity into details that only work in close-up screenshots.

## Pass 5.6 Modeling Acceptance Checklist

Version 0.1 modeling should be judged on:

- silhouette reads as Toastmarshal from medium/far Roblox camera distance,
- character is clearly original ODDWORKS IP,
- toast body is the largest visual mass,
- pan/marshal helmet reads clearly,
- spatula-saber reads without hiding the body,
- proportions feel tiny, over-serious, and collectible,
- face is simple and readable,
- hierarchy uses semantic object and bone names,
- Blender source uses negative Y forward and positive Z up,
- grounded reference is deliberate at the bottom of feet/contact points,
- scale target is tested in Roblox before being documented as final,
- topology is rig-friendly enough for idle/display animation,
- UV/albedo plan follows the verified TextureID pipeline,
- Common version leaves visual room for future variants,
- no copyrighted, downloaded, or derivative character content is used.

Version 0.1 does not need final polish, a complete animation library, advanced materials, rare variant effects, or gameplay integration.
