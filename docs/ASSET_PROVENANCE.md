# ODDWORKS Asset Provenance

## Core Rule

Every third-party production asset must have clear provenance before it enters ODDWORKS production use.

Do not add fabricated provenance. If an asset's creator, source, URL, license, or usage rights are unknown, the asset is not ready for production.

## Original ODDWORKS Assets

ODDWORKS signature characters, including future Oddlings such as Toastmarshal, should be original project assets created internally.

Do not download a character, rename it, recolor it, or lightly edit it and treat it as an original Oddling. ODDWORKS should create original characters capable of standing on their own.

Third-party assets should primarily be limited to supporting content when rights are clear, such as:

- generic materials,
- generic environment props,
- textures,
- non-signature scenery.

## License Rule

"Free download" does not automatically mean free commercial use.

Prefer CC0 or public-domain-equivalent licenses for supporting assets where practical. Other licenses require explicit review and recording before use.

Unknown-license or no-license assets must not enter production merely because they are downloadable.

## Texture Rule

External textures used on original ODDWORKS geometry still require provenance and license documentation.

Creating the mesh internally does not make an unlicensed texture safe to use.

## Required Registry Fields

Every third-party production asset must record:

- internal asset name,
- original asset name,
- creator,
- source,
- source URL or reference,
- license,
- date obtained,
- attribution requirement,
- modifications,
- ODDWORKS usage.

## Registry

No third-party production assets have been approved or recorded yet.

| Internal Asset Name | Original Asset Name | Creator | Source | Source URL / Reference | License | Date Obtained | Attribution Requirement | Modifications | ODDWORKS Usage |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| _Template only_ |  |  |  |  |  |  |  |  |  |

## Internal Disposable Test Assets

These entries are internally created pipeline fixtures, not third-party production assets.

| Internal Asset Name | Original Asset Name | Creator | Source | Source URL / Reference | License | Date Obtained | Attribution Requirement | Modifications | ODDWORKS Usage |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| `ODDWORKS_PIPELINE_TEST` | `ODDWORKS_PIPELINE_TEST` | ODDWORKS internal, Codex-assisted Blender primitives | Internal Blender primitive geometry | `assets/source/blender/props/oddworks_pipeline_test.blend` | Internal disposable project fixture; no third-party license | 2026-09-02 | None | Created from simple box primitives with one orange material; exported as original multi-object, merged rigid, and textured diagnostic GLBs for pipeline verification | Disposable Blender-to-Roblox regression fixture only; not production gameplay content |
| `pipeline_test_albedo` | `pipeline_test_albedo.png` | ODDWORKS internal, Codex-assisted generated diagnostic pixels | Internal generated PNG texture | `assets/textures/pipeline_test_albedo.png` | Internal disposable project fixture; no third-party license | 2026-09-03 | None | Created as a 64x64 red/green/blue/orange albedo diagnostic with black dividers and a white orientation marker; embedded into `oddworks_pipeline_test_textured.glb` | Disposable UV/albedo texture pipeline fixture only; not production gameplay content |
| `ODDWORKS_RIG_TEST` | `ODDWORKS_RIG_TEST` | ODDWORKS internal, Codex-assisted Blender primitives | Internal Blender primitive mesh, armature, weights, and animation | `assets/source/blender/props/oddworks_rig_test.blend` | Internal disposable project fixture; no third-party license | 2026-09-06 | None | Created as one skinned mesh with a `Root -> Lower -> Upper` armature and a short bend animation; exported as rigged GLB and FBX animation for pipeline verification | Disposable rigging/skinning/animation regression fixture only; not production gameplay content |
