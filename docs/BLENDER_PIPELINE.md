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

## Asset Structure Categories

### Simple Rigid Prop

Use this category when an object does not need moving limbs, separate animated pieces, or runtime articulation.

Prefer one `MeshPart` or merged rigid geometry when articulation is unnecessary. A simple crate, sign, tool, or non-animated workshop prop should not become several loose physical pieces by accident.

### Multi-Part Rigid Model

Use this category when multiple pieces should remain separate for organization, separate materials, collision tuning, or editing clarity.

Multiple `MeshPart` instances may live under one Roblox `Model`, but grouping alone does not physically connect unanchored `BasePart` instances. Physical moving assemblies require deliberate `WeldConstraint`, joint, or constraint behavior when appropriate.

### Animated Oddling

Use this category for characters expected to animate.

Do not solve articulated characters by simply merging or welding every body piece. Toastmarshal is expected to be an animated Oddling, so a future production pass should investigate:

```text
mesh(es)
-> armature
-> bones
-> skinning / rigid weighting as appropriate
-> Blender animation test
-> Roblox rig import
```

Do not weld Toastmarshal into one solid statue, merge all future character geometry blindly, or build the rig before the dedicated character-rigging pass.

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

## Verified Dry-Run Findings

Pass 5.5C created one disposable pipeline regression fixture:

```text
assets/source/blender/props/oddworks_pipeline_test.blend
assets/exports/props/oddworks_pipeline_test.glb
```

The fixture is not a production prop.

Verified Blender source facts:

- Root object: `ODDWORKS_PIPELINE_TEST`, authored as an Empty at location `(0, 0, 0)`.
- Root transform: rotation `(0, 0, 0)`, scale `(1, 1, 1)`.
- Child mesh objects: `pipeline_test_body`, `pipeline_test_front_probe_negative_y`, `pipeline_test_top_marker_positive_z`.
- Bounds: minimum `(-1.0, -1.05, 0.0)`, maximum `(1.0, 0.6, 1.4)`.
- Dimensions: `(2.0, 1.65, 1.4)` in Blender units.
- Grounding reference: bottom of the mesh bounds sits on Blender `Z=0`.
- Intended forward: the protruding piece extends on Blender negative Y.
- World up: the top marker extends on Blender positive Z.
- Material: one simple orange material named `pipeline_test_simple_orange`.

Verified GLB export facts:

- Export command path: Blender MCP `export_glb`.
- Blender operator: `bpy.ops.export_scene.gltf`.
- Important settings used: `export_format='GLB'`, `use_selection=True`, `export_apply=True`.
- Exported content: selected fixture hierarchy only.
- Blender exporter: `Khronos glTF Blender I/O v5.2.40`.
- No animations, rigs, external textures, or complex shader graph were added.
- GLB output was valid glTF 2.0.
- GLB preserved semantic node names and the simple orange material.

Manual Roblox import observation for the original multi-object export:

- The disposable `ODDWORKS_PIPELINE_TEST` imports visibly into Roblox.
- Orientation appears upright.
- Scale appears reasonable for the test fixture.
- Grounding appears approximately correct.
- Fixture components are not behaving or structured as one intentional rigid physical object.
- The intended orange material appears gray rather than visibly orange.

Verified Studio inspection for the original multi-object import:

- Imported root: `Workspace.ODDWORKS_PIPELINE_TEST_SCENE.ODDWORKS_PIPELINE_TEST`.
- Imported root class: `Model`.
- MeshPart count: `3`.
- Constraint or joint count: `0`.
- Direct children under the imported root are separate `Model` instances for `pipeline_test_body`, `pipeline_test_front_probe_negative_y`, and `pipeline_test_top_marker_positive_z`.
- MeshParts are unanchored, collidable `MeshPart` instances with no `WeldConstraint` or joint connecting them.
- Roblox bounding box size: `(2.0, 1.4, 1.65)`.
- Roblox bounding box bottom Y: `0.0`.
- Roblox root pivot sits at ground height `Y=0.0`.
- Blender positive Z mapped to Roblox positive Y for this import.
- Blender negative Y mapped to Roblox negative Z for this import.
- Imported MeshParts use gray `Plastic` with color approximately `(0.639, 0.635, 0.647)` and no `TextureID`.

Material transfer is not verified as acceptable for this pipeline until an importer setting, Blender material adjustment, or Roblox material/color workflow preserves or deliberately reapplies the intended color.

Verified GLB axis observation:

- The exported GLB encodes glTF Y-up data.
- Blender positive Z appeared as GLB positive Y in node translations.
- The Blender negative-Y front protrusion appeared along GLB positive Z in the exported file.

The manual Studio import confirms this fixture arrived upright and mapped Blender negative Y to Roblox negative Z when imported with World Forward set to Front, World Up set to Top, and Scale Unit set to Stud. Do not generalize this beyond the tested simple GLB path without another import test.

Verified Roblox import status:

- Roblox Studio MCP was available and returned Edit mode after Play mode was stopped.
- A scripted local import attempt using `AssetService:CreateMeshPartAsync(Content.fromUri("file:///Users/bhann/Documents/Roblox%20Project/assets/exports/props/oddworks_pipeline_test.glb"))` failed with `Failed to load mesh asset`.
- Direct scripted local import from file URI did not work; manual use of Studio's interactive 3D Importer was required.

Verified rigid fixture variant:

```text
assets/exports/props/oddworks_pipeline_test_merged.glb
```

- Source object: `ODDWORKS_PIPELINE_TEST_RIGID_MERGED`.
- Geometry: one Blender mesh built from the three original visible fixture meshes.
- Vertex count: 24.
- Face count: 18.
- Bounds: minimum `(-1.0, -1.05, 0.0)`, maximum `(1.0, 0.6, 1.4)`.
- Dimensions: `(2.0, 1.65, 1.4)` in Blender units.
- Transform: location `(0, 0, 0)`, rotation `(0, 0, 0)`, scale `(1, 1, 1)`.
- Material: `pipeline_test_simple_orange`.
- GLB structure: one scene node, one mesh, one primitive, one material.
- GLB material payload: base color factor `(1.0, 0.42, 0.08, 1.0)`, metallic `0`, roughness `0.55`.

Verified manual Roblox import for the merged rigid fixture:

- Importer settings used: World Forward `Front`, World Up `Top`, Scale Unit `Stud`.
- Imported root: `Workspace.ODDWORKS_PIPELINE_TEST_SCENE.ODDWORKS_PIPELINE_TEST_RIGID_MERGED`.
- Imported root class: `Model`.
- MeshPart count: `1`.
- Constraint or joint count: `0`.
- Direct child: `ODDWORKS_PIPELINE_TEST_RIGID_MERGED_mesh` as a `MeshPart`.
- MeshPart size: `(2.0, 1.4, 1.65)`.
- MeshPart orientation: `(0, 0, 0)`.
- Roblox bounding box bottom Y: `0.0`.
- Roblox root pivot sits at ground height `Y=0.0`.
- The front protrusion is visible from the negative Roblox Z side, matching the original import's Blender negative-Y to Roblox negative-Z mapping.
- The imported MeshPart is gray `Plastic` with color approximately `(0.639, 0.635, 0.647)` and no `TextureID`.

Geometry pipeline result:

- For simple rigid props, Blender joined rigid geometry exported as one GLB mesh imported into Roblox as one `MeshPart` under a `Model`.
- Scale remained reasonable for the test fixture.
- The authored ground-bottom reference survived this test import closely enough for disposable geometry validation.
- Final runtime placement should still use the rules in [World Placement](WORLD_PLACEMENT.md), because imported pivots and bounding boxes must be accounted for per asset.

Material pipeline result:

- The Blender source and GLB both contain the expected orange material data.
- The current tested flat-material workflow imported as gray Plastic in Roblox.
- Treat flat Blender material color transfer as pending, not production-verified.
- Before production character completion, verify either an explicit UV/albedo texture workflow or an intentionally Roblox-authored material/color workflow.

Do not apply the Merge Meshes rule to future rigged Oddlings unless a dedicated rigging/import test proves it is correct for that asset category.

If a repeatable rigid-structure or material problem occurs across imports, prefer correcting Blender authoring, export settings, or importer settings instead of manually repairing every imported Roblox copy.

## Verified Texture Dry-Run Preparation

Pass 5.5D adds a disposable textured variant to test whether image-based color transfers more reliably than flat Blender material color.

Files:

```text
assets/textures/pipeline_test_albedo.png
assets/exports/props/oddworks_pipeline_test_textured.glb
```

The textured variant is not a production prop.

Verified diagnostic texture facts:

- Texture name: `pipeline_test_albedo`.
- File path: `assets/textures/pipeline_test_albedo.png`.
- Size: `64x64`.
- Format: PNG, 8-bit RGBA.
- Content: ODDWORKS-internal diagnostic color blocks only.
- Pattern: red upper-left, green upper-right, blue lower-left, orange lower-right, black dividers/border, and a small white lower-left orientation marker.
- Third-party content: none.

Verified Blender textured fixture facts:

- Textured object: `ODDWORKS_PIPELINE_TEST_TEXTURED`.
- Source geometry: duplicate of the verified `ODDWORKS_PIPELINE_TEST_RIGID_MERGED` mesh.
- The verified rigid geometry fixture remains present as `ODDWORKS_PIPELINE_TEST_RIGID_MERGED`.
- Vertex count: `24`.
- Face count: `18`.
- Bounds: minimum `(-1.0, -1.05, 0.0)`, maximum `(1.0, 0.6, 1.4)`.
- Dimensions: `(2.0, 1.65, 1.4)` in Blender units.
- Transform: location `(0, 0, 0)`, rotation `(0, 0, 0)`, scale `(1, 1, 1)`.
- UV layer: `pipeline_test_uv`.
- UV loop count: `72`.
- Material: `pipeline_test_textured_albedo`.
- Material setup: Image Texture node using `pipeline_test_albedo.png` linked into Principled BSDF Base Color.
- The Blender material does not use procedural shaders, normal maps, metallic maps, emission, transparency, or external materials.

Verified UV strategy:

- Each face receives intentional UV coordinates instead of random generated placement.
- Dominant-axis projection maps each face to stable local axes.
- Front and back faces use local X/Z projection so the diagnostic texture can test left/right and up/down orientation on the intended forward side.
- Top and bottom faces use local X/Y projection.
- Side faces use local Y/Z projection.
- The UVs use a small margin inside the texture to reduce edge bleeding from the black border.

Verified Blender visual check:

- Blender material-preview viewport showed the red, green, blue, and orange diagnostic pattern on the textured fixture.
- The fixture remained chunky, upright, grounded at Blender `Z=0`, and visibly directional.

Verified textured GLB export facts:

- Export command path: Blender MCP `export_glb`.
- Blender operator: `bpy.ops.export_scene.gltf`.
- Important settings used: `export_format='GLB'`, `use_selection=True`, `export_apply=True`.
- Exported content: selected textured fixture only.
- GLB output was valid glTF 2.0.
- GLB structure: one scene, one node, one mesh, one primitive, one material.
- Mesh attributes include `POSITION`, `NORMAL`, and `TEXCOORD_0`.
- Material `pipeline_test_textured_albedo` uses a base-color texture.
- Texture count: `1`.
- Image count: `1`.
- Image MIME type: `image/png`.
- The PNG image is embedded in the GLB through a buffer view, not referenced as an external URI.

Verified manual Roblox 3D Importer settings for the textured fixture:

- Import the file `assets/exports/props/oddworks_pipeline_test_textured.glb`.
- World Forward: `Front`.
- World Up: `Top`.
- Scale Unit: `Stud`.

Manual Roblox visual verification result:

- The textured fixture imported through the same one rigid `MeshPart` path.
- The fixture remained upright.
- Scale remained reasonable for the regression fixture.
- The authored bottom/grounding reference remained valid for the fixture.
- The diagnostic texture rendered visibly in Roblox Studio.
- Red, green, blue, and orange regions were visible.
- Black separators and the white orientation marker were visible.
- Roblox represented the basic albedo texture with `MeshPart.TextureID`.
- No `SurfaceAppearance` was required for this basic albedo test.

Verified Studio inspection for the textured import:

- Imported root: `Workspace.ODDWORKS_PIPELINE_TEST_SCENE.ODDWORKS_PIPELINE_TEST_TEXTURED`.
- Imported root class: `Model`.
- MeshPart count: `1`.
- Constraint or joint count: `0`.
- MeshPart size: `(2.0, 1.4, 1.65)`.
- MeshPart orientation: `(0, 0, 0)`.
- Roblox bounding box bottom Y: `0.0`.
- Roblox root pivot sits at ground height `Y=0.0`.
- Appearance representation: the imported `MeshPart` has `TextureID=rbxassetid://115440966970381`.
- No `SurfaceAppearance`, `Texture`, or `Decal` descendants were present under the imported textured model.
- Manual visual inspection confirmed the diagnostic texture and orientation markers were visible in Roblox Studio.

Texture pipeline status:

- The currently verified early ODDWORKS appearance path is Blender mesh -> intentional UV map -> small albedo/base-color texture -> GLB with embedded image -> Roblox 3D Importer -> `MeshPart.TextureID`.
- Flat Blender Principled BSDF base color alone did not reliably transfer in the tested pipeline; the explicit UV/albedo image workflow did transfer.
- This verifies the basic albedo/color workflow only. It does not prove every future material, shader, PBR, transparency, normal map, or `SurfaceAppearance` workflow.
- For first production characters, prefer stylized color blocks, small efficient textures, limited material count, and readable silhouettes.

Future Toastmarshal production has two largely independent art concerns:

```text
STRUCTURE:
mesh
-> armature
-> bones
-> skinning
-> animation

APPEARANCE:
UV
-> albedo/color texture
-> Roblox-compatible appearance
```

Passing this texture test does not verify character rigging. Passing a future rigging test will not automatically verify textures.

## Current Scope

Pass 5.5B created infrastructure only. Pass 5.5C added the disposable geometry regression fixture documented above. Pass 5.5D adds a disposable textured fixture for manual Roblox texture verification.

Do not create Toastmarshal, Conejurer, downloaded food models, Poly Haven assets, production GLB/FBX exports, or production Roblox imports in this pass.
