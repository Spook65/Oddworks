# SmallBiped_v1 Technical Contract

## Status

This document is the frozen geometry, socket, component, runtime-assembly, and art-handoff contract for the Vertical Slice 0.2 modular prototype.

It specifies future implementation. No frame, module, RemoteEvent, runtime template, or production asset is created by this documentation pass.

## Frame Scope

The prototype contains exactly one frame:

- FrameId: **SmallBiped_v1**
- built-in chassis and internal core identity
- one HeadModule selection
- one ArmModule selection
- one LegsModule selection

SmallBiped_v1 does not expose separate left/right arms, separate left/right legs, a Core module, Back module, tail, or unrestricted sockets.

## Limb Semantics

The prototype decisions are:

- **ArmModule is one complete paired-arm assembly.** One selection supplies both visible arms and attaches through one ArmSocket.
- **LegsModule is one complete paired lower-body and mobility assembly.** One selection supplies both legs and attaches through one LegsSocket.

This keeps the inventory, assembly request, runtime hierarchy, and shared idle rig to one choice and one joint per role. Individual left/right customization is deferred.

## Canonical Roblox Orientation

All runtime frame and module contracts use Roblox space:

- units: studs
- +X: Construct right
- +Y: up
- -Z: Construct forward
- +Z: Construct rear
- rotations: right-handed Roblox CFrame conventions

The bind pose is upright and faces Roblox -Z. Runtime code must not add an orientation-correction rotation.

## Root, Pivot, and Ground Plane

SmallBiped_v1 uses one BasePart named **RootPart**.

The canonical local coordinate system is:

- root origin: center of RootPart
- Model pivot: exactly equal to RootPart.CFrame
- RootPart local CFrame: identity
- bind-pose ground plane: local Y = -3.0 studs
- grounded root height: 3.0 studs above the resolved surface

RootPart properties for the prototype template are:

- Size: Vector3.new(1, 1, 1)
- Transparency: 1
- Massless: true
- CanCollide: false
- CanTouch: false
- CanQuery: false

For an upright horizontal display surface represented by ground CFrame G, the target frame pivot is conceptually:

```luau
G * CFrame.new(0, 3, 0)
```

The display system must still resolve the actual authoritative surface according to WORLD_PLACEMENT.md. It must not assume world Y = 0 or trust a client-provided CFrame.

RootPart is the only anchored part for a workshop display. Frame and module geometry remains unanchored but rigidly connected to RootPart. All displayed Construct parts use CanCollide = false, CanTouch = false, and CanQuery = false for the prototype.

## Blender Orientation and Scale

Blender source uses the already-verified ODDWORKS pipeline convention:

- Blender +X: character right
- Blender +Z: up
- Blender -Y: forward
- 1 Blender unit: 1 Roblox stud
- authored ground plane: Blender Z = 0
- object transforms applied before export
- object scale: 1, 1, 1
- corrective runtime rotation: prohibited

Manual Roblox import uses World Forward = Front, World Up = Top, and Scale Unit = Stud unless a later pipeline verification explicitly supersedes those settings.

With the verified GLB path, Blender -Y maps to Roblox -Z and Blender +Z maps to Roblox +Y.

## Exact Socket Transforms

The frame contains three Attachments parented directly to RootPart. Each Attachment.CFrame is relative to RootPart and has identity rotation.

| Socket | Attachment.CFrame | Role |
| --- | --- | --- |
| HeadSocket | CFrame.new(0, 1.5, 0) | HeadModule mount |
| ArmSocket | CFrame.new(0, 0.25, 0) | paired ArmModule mount |
| LegsSocket | CFrame.new(0, -1.25, 0) | paired LegsModule mount |

Identity rotation means each socket inherits the frame axes: +X right, +Y up, and -Z forward.

Individual modules may not move or rotate these sockets. A contract revision must update the frame reference, this table, gameplay configuration, and all compatible art together.

## Module Root Contract

Every module runtime template is a Model containing:

- one BasePart named **ModuleRoot**
- one Attachment named **MountAttachment**, parented to ModuleRoot
- visual MeshParts or Parts rigidly connected to ModuleRoot

The module contract is:

- Model pivot equals ModuleRoot.CFrame
- ModuleRoot local CFrame is identity
- MountAttachment.CFrame is identity
- module forward is -Z
- module up is +Y
- module scale is authored in studs and applied before export
- no module may include scripts, remotes, independent economy data, or authoritative stats

ModuleRoot properties are Size = Vector3.new(0.25, 0.25, 0.25), Transparency = 1, Massless = true, and all three collision/touch/query flags false. Visual geometry is rigidly connected to this nonvisual root.

Geometry may extend around ModuleRoot within its allowed envelope. MountAttachment is the immutable connection reference, not necessarily the visual center of the module.

## Module Envelopes

Bounds below are axis-aligned bind-pose bounds relative to each module's MountAttachment. Geometry, including decorative pieces, must remain inside them.

| Module role | X range | Y range | Z range | Maximum dimensions |
| --- | --- | --- | --- | --- |
| HeadModule | -1.25 to +1.25 | -0.25 to +2.0 | -1.0 to +1.0 | 2.5 W x 2.25 H x 2.0 D |
| ArmModule | -2.5 to +2.5 | -0.8 to +0.8 | -0.9 to +0.9 | 5.0 W x 1.6 H x 1.8 D |
| LegsModule | -1.5 to +1.5 | -1.75 to +1.0 | -1.2 to +1.2 | 3.0 W x 2.75 H x 2.4 D |

The lowest intended foot contact for every LegsModule is exactly 1.75 studs below LegsSocket. Since LegsSocket is at root-local Y = -1.25, the assembled feet reach the root-local ground plane at Y = -3.0.

Loose hoses, effects, or animation must not silently exceed these prototype envelopes. An explicit contract revision is required when a module cannot fit.

## SmallBiped Footprint

The bind-pose assembled Construct envelope is limited to:

- maximum width: 5.0 studs
- maximum depth: 3.0 studs
- maximum height above the ground plane: 6.5 studs
- root-to-ground offset: 3.0 studs

The shared idle must remain inside a runtime clearance envelope of:

- 5.5 studs wide
- 3.5 studs deep
- 6.75 studs high

These bounds constrain prototype art and display clearance. They do not create a workshop grid or authorize arbitrary player placement.

## Required Frame Runtime Hierarchy

The future frame template should follow this minimum contract:

```text
SmallBiped_v1_Frame (Model; pivot = RootPart.CFrame)
├── RootPart (BasePart)
│   ├── HeadSocket (Attachment)
│   ├── ArmSocket (Attachment)
│   └── LegsSocket (Attachment)
├── Chassis (MeshPart or Model geometry)
└── AnimationController
    └── Animator (may be created by the server if absent)
```

Runtime assembly adds one module Model and one canonical Motor6D for each selected role.

## Prototype Component Metadata

Every server-owned component definition requires:

- ComponentId: stable base identity without rarity suffix
- DisplayName: player-facing name
- Slot: Head, Arm, or Legs
- ArtModel: runtime template name shared by all rarities
- SupportedRarities: Common, Rare, Legendary
- GameplayDomain: Signal, Extraction, or Mobility
- ConfiguredEffects: deterministic values by rarity
- CompatibleFrames: exactly SmallBiped_v1 for this prototype

The client never defines or overrides this metadata.

## Frozen Component Catalog

The first prototype has exactly six base ComponentIds.

### Head Components

| ComponentId | DisplayName | ArtModel | Domain | Effect key | Common | Rare | Legendary |
| --- | --- | --- | --- | --- | ---: | ---: | ---: |
| ClownMask | Clown Mask | ClownMask_Prototype | Signal | SignalRangeBonusStuds | 4 | 7 | 10 |
| SignalScanner | Signal Scanner | SignalScanner_Prototype | Signal | SignalRangeBonusStuds | 8 | 14 | 22 |

### Arm Components

| ComponentId | DisplayName | ArtModel | Domain | Effect key | Common | Rare | Legendary |
| --- | --- | --- | --- | --- | ---: | ---: | ---: |
| RustClaw | Rust Claw | RustClaw_Prototype | Extraction | ExtractionSpeedPercent | 4 | 9 | 16 |
| ServoArm | Servo Arm | ServoArm_Prototype | Extraction | ExtractionSpeedPercent | 5 | 12 | 22 |

### Legs Components

| ComponentId | DisplayName | ArtModel | Domain | Effect key | Common | Rare | Legendary |
| --- | --- | --- | --- | --- | ---: | ---: | ---: |
| StitchedBoots | Stitched Boots | StitchedBoots_Prototype | Mobility | CarryMoveSpeedPercent | 3 | 6 | 10 |
| SpringLegs | Spring Legs | SpringLegs_Prototype | Mobility | CarryMoveSpeedPercent | 5 | 9 | 14 |

These values are prototype configuration, not final production balance. They provide only three understandable effect keys and no general RPG stat sheet.

## Component Identity and Rarity

ComponentId and Rarity are separate values.

Example:

```text
ComponentId = ServoArm
Rarity = Rare
```

The server resolves that pair to ServoArm compatibility and art plus the Rare ExtractionSpeedPercent value of 12.

Rarity:

- does not change socket compatibility
- does not change frame size or module envelope
- does not create random rolls
- does not select different geometry
- changes deterministic configured effects and client-safe presentation metadata

ServoArm Common, Rare, and Legendary all use ServoArm_Prototype. The six base ComponentIds require approximately six module models, not eighteen rarity-specific models.

## Runtime Assembly Mechanism

The prototype uses deterministic server-created Motor6D joints.

For every module, the bind-pose alignment contract is:

```luau
motor.Part0 = smallBipedFrame.RootPart
motor.Part1 = module.ModuleRoot
motor.C0 = frameSocket.CFrame
motor.C1 = module.ModuleRoot.MountAttachment.CFrame
```

At identity Motor6D.Transform, this aligns the two authored attachment frames according to the JointInstance relationship:

```text
Part0.CFrame * C0 = Part1.CFrame * C1
```

The exact per-role mapping is:

| Joint | Part0 | Part1 | C0 source | C1 source |
| --- | --- | --- | --- | --- |
| HeadJoint | SmallBiped_v1 RootPart | selected Head ModuleRoot | HeadSocket.CFrame | Head MountAttachment.CFrame |
| ArmJoint | SmallBiped_v1 RootPart | selected Arm ModuleRoot | ArmSocket.CFrame | Arm MountAttachment.CFrame |
| LegsJoint | SmallBiped_v1 RootPart | selected Legs ModuleRoot | LegsSocket.CFrame | Legs MountAttachment.CFrame |

MountAttachment.CFrame is contractually identity for SmallBiped_v1, so C1 currently resolves to identity. The runtime must still derive C1 from MountAttachment.CFrame so the relationship remains explicit and auditable.

For each selected module:

1. Clone the server-owned ArtModel template.
2. Validate ModuleRoot and MountAttachment.
3. Parent the module under the derived Construct Model.
4. Create the canonical Motor6D with Part0 = RootPart and Part1 = ModuleRoot.
5. Set Motor6D.C0 to the matching socket Attachment.CFrame.
6. Set Motor6D.C1 to MountAttachment.CFrame, which is identity for v1.

Canonical joint names are:

- HeadJoint
- ArmJoint
- LegsJoint

Visual parts inside a module use WeldConstraints or an equivalent rigid connection to ModuleRoot. Modules must not create their own replacement joint to RootPart.

Runtime corrective rotations, guessed offsets, or arbitrary per-module positioning are prohibited. Incorrect alignment must be fixed in the Blender source, frame socket, or module MountAttachment contract rather than hidden in gameplay code.

Motor6D is chosen over anchoring every module because it keeps the assembly fixed to the anchored RootPart while allowing one shared animation to transform the three canonical joints.

This is a narrow SmallBiped_v1 mechanism, not a generalized attachment graph.

## Animation Contract

SmallBiped_v1 may use one shared idle animation through AnimationController and Animator.

The shared idle may animate only:

- HeadJoint
- ArmJoint
- LegsJoint

Prototype modules are rigid assemblies and require no internal bones or module-specific animation tracks. The paired ArmModule moves as one authored assembly; independent arm animation is intentionally unavailable in v1.

The initial idle should use modest joint motion and remain within the runtime clearance envelope. LegsJoint should remain close enough to its bind transform that intended ground contact does not visibly slide or float.

If a module needs an incompatible skeleton, independent limb timing, or motion outside these limits, it is not compatible with SmallBiped_v1 and requires a future frame contract.

## Derived Display Contract

The physical Roblox Model is derived from the authoritative PrototypeConstruct selections.

Runtime display construction must:

- resolve the server-owned frame template
- resolve each selected ComponentId to its server-owned ArtModel
- ignore rarity for geometry selection
- create the three canonical joints
- place the Model using the root-to-ground contract
- disable collision, touch, and query on display geometry
- start the shared idle when the frame and animation asset support it

No Instance, Model, socket CFrame, or runtime part reference belongs in authoritative player state. Deleting the derived Model must not delete component ownership or PrototypeConstruct state; reconciliation should rebuild it.

### 0.2E Prototype Placement

The repository authors one non-authoritative `PrototypeConstructDisplay` marker and one visible `PrototypeConstructPad` beneath each plot. These do not replace workshop assignment or Construct state.

- Plot01 marker: `CFrame.new(-22, 0.45, 0)`
- Plot02 marker: `CFrame.new(22, 0.45, 0)`
- marker rotation: identity, so the Construct faces Roblox `-Z`
- pad center: marker position minus `Vector3.new(0, 0.1, 0)`
- pad size: `Vector3.new(7, 0.2, 5)`

The marker CFrame represents the standing surface. The runtime service places RootPart at `marker.CFrame * CFrame.new(0, 3, 0)`, preserving the frozen root-local ground plane at `Y = -3`. The markers are separate from `OddlingDisplaySlots`, the assembler, and the salvage intake.

For the 0.2E technical proof, `default.project.json` maps the primitive frame and six primitive module templates beneath `ServerStorage.ODDWORKSAssets.Constructs`. These repository-authored primitives prove hierarchy, socket alignment, Motor6D binding, and reconstruction only; they are not final Blender art.

## Production Replacement Paths

Future Blender replacements for the 0.2E primitive templates should use these repository roles:

```text
assets/source/blender/constructs/small_biped_v1.blend
assets/source/blender/components/<component_id_snake_case>.blend
assets/exports/constructs/small_biped_v1_frame.glb
assets/exports/components/<component_id_snake_case>.glb
assets/roblox/constructs/SmallBiped_v1_Frame.rbxm
assets/roblox/components/<ArtModel>.rbxm
```

The 0.2E primitive proof is currently authored directly through `default.project.json`. A later art pass may replace those entries with the versioned Roblox model paths above without changing the server-only runtime contract. Runtime templates live under a Constructs asset hierarchy separate from Signature Oddlings.

## Naming Contract

- FrameId: SmallBiped_v1
- frame runtime template: SmallBiped_v1_Frame
- frame root: RootPart
- chassis: Chassis
- sockets: HeadSocket, ArmSocket, LegsSocket
- module roots: ModuleRoot
- module mount: MountAttachment
- joints: HeadJoint, ArmJoint, LegsJoint
- ComponentIds: PascalCase without rarity suffix
- ArtModels: ComponentId plus _Prototype

Names are case-sensitive stable identifiers once implementation begins.

## Blender and Import Acceptance

Before any modular asset is accepted, verify:

1. Applied Blender transforms and 1:1 stud scale.
2. Blender -Y forward and +Z up.
3. Imported Roblox -Z forward and +Y up.
4. Required root and mount names.
5. MountAttachment identity transform.
6. Geometry inside the correct module envelope.
7. Legs contact at root-local Y = -3.0 when assembled.
8. No scripts, remotes, or unreviewed behavior in the Roblox template.
9. Runtime pivot equals the required root CFrame.
10. Shared idle compatibility and runtime clearance.
11. Source, export, runtime model, texture, and provenance files are reproducible.

## Explicit Non-Goals

SmallBiped_v1 does not include:

- separate Core geometry selection
- separate left/right limb selection
- Back modules or tails
- arbitrary sockets
- freeform transforms
- rarity-specific geometry
- random stats or affixes
- procedural meshes
- bespoke rig per component
- player-authored placement
- field-companion AI
- final production art
