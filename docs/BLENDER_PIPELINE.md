# ODDWORKS Blender Pipeline

## Purpose

This document defines the production asset pipeline for ODDWORKS Blender-authored art.

ODDWORKS uses Blender MCP as tooling, but the ODDWORKS repository remains the project source of truth.

## Folder Layout

Canonical editable Blender source files live in:

```text
assets/source/blender/oddlings/
assets/source/blender/props/
assets/source/blender/environment/
```

Roblox-ready interchange exports live in:

```text
assets/exports/oddlings/
assets/exports/props/
assets/exports/environment/
```

Shared texture assets live in:

```text
assets/textures/
```

## Source-Of-Truth Rule

`.blend` files are the canonical editable 3D source.

`.glb` and `.fbx` files are exported game-engine interchange files.

Roblox imported assets are runtime or game representations. They are not the canonical authoring source.

If a model needs correction after Roblox import or testing, update the Blender `.blend` source first, then export again.

## Production Flow

Use this flow for production Blender assets:

```text
design/spec
-> Blender .blend source
-> review
-> export GLB/FBX
-> Roblox import
-> Roblox test
-> correction in Blender source if needed
```

Do not treat exported files or imported Roblox copies as the editable master.

## File Naming Standard

Use predictable lowercase file names with words separated by hyphens only when needed.

Example canonical character source:

```text
assets/source/blender/oddlings/toastmarshal.blend
```

Example export:

```text
assets/exports/oddlings/toastmarshal.glb
```

Do not create manual backup names such as:

```text
toast-final.blend
toast-final2.blend
toast-REAL-final.blend
```

Git history provides versioning. Meaningful milestones should be captured with Git commits instead of duplicate "final" files.

## Initial Blender Model Standards

ODDWORKS assets should be chunky, readable, stylized, and relatively efficient.

Avoid unnecessary polygon density. Do not set a hard triangle budget until actual game, camera, performance, and character requirements have been measured.

Use these initial authoring standards:

- Blender source convention is negative Y forward and positive Z up.
- Asset dimensions should be intentional and documented when important.
- Do not invent exact Blender-to-Roblox scale conversion numbers until verified through an actual Roblox import test.
- Grounded characters and props should have an intentional bottom, feet, base, or contact reference.
- Pivots and origins must be deliberately authored for the asset's expected use.
- Apply or clean transforms before export when appropriate for the asset.
- Object names should be semantic, such as `body`, `helmet`, `handle`, or `left-wheel`, rather than `Cube.001` or `Cylinder.004`.
- Hero assets should have a clean hierarchy that is easy to inspect and revise.

## Grounding And Placement

Blender authoring should support future Roblox grounding by using predictable pivots, bounding geometry, and intentional character bottoms.

See [World Placement](WORLD_PLACEMENT.md) for the Roblox placement rules.

Do not assume a Blender pivot alone guarantees Roblox ground contact. Roblox placement may need model bounds, pivot-to-bottom offsets, `Model:GetBoundingBox()`, and import-specific testing.

## Materials

Imported material compatibility must be tested in Roblox.

Do not assume complex Blender shader graphs will transfer identically into Roblox. Prefer simple, game-friendly material structures for early assets.

## Provenance

Third-party production assets require provenance before use. Record them in [Asset Provenance](ASSET_PROVENANCE.md).

External textures used on original meshes still require provenance and license documentation.

## MCP Tooling Boundary

Blender MCP is tooling, not ODDWORKS project content.

The external connector lives at:

```text
/Users/bhann/Documents/Tools/blender-codex-mcp
```

Keep that repository outside ODDWORKS. Do not vendor, copy, or commit the external Blender MCP source into this project.

## Blender Source Safety

Before major destructive Blender operations:

- save the canonical source,
- verify the intended file path,
- use Git checkpoints between meaningful asset milestones.

Do not create uncontrolled duplicate manual backups inside production folders.

## Current Scope

This pass creates infrastructure only.

Do not create Toastmarshal, Conejurer, downloaded food models, Poly Haven assets, production GLB/FBX exports, or Roblox imports in this pass.
