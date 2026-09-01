# ODDWORKS World Placement

## Core Rule

Do not position grounded world objects with arbitrary guessed Y offsets.

Placement should be derived from actual object bounds and intended surfaces. A prop that is meant to rest on a surface should use the surface top plus the prop's half-height, not a visually guessed center position.

## Simple BasePart On Horizontal BasePart

For an axis-aligned `BasePart` resting on another horizontal `BasePart`, use:

```text
surfaceTopY = surface.Position.Y + surface.Size.Y / 2
objectCenterY = surfaceTopY + object.Size.Y / 2
```

`BasePart.Position` and `BasePart.CFrame` normally represent the part's center/reference location, not its bottom contact point. If a 3-stud-tall object should stand on a surface at Y 0.475, its center Y should be 0.475 + 1.5 = 1.975.

For the current salvage placeholders, `SalvageField` is the intended surface:

```text
SalvageField.Position.Y = 0.3
SalvageField.Size.Y = 0.35
SalvageField top Y = 0.3 + 0.35 / 2 = 0.475

Salvage node Size.Y = 3
Salvage node half-height = 1.5
Correct salvage node center Y = 0.475 + 1.5 = 1.975
```

## Persistent Static World Content

For hand-authored or simple static world geometry:

- use exact dimensions and positions,
- verify contact in Studio Edit mode,
- prefer Studio visual authoring when appropriate,
- do not create runtime systems merely to place static scenery.

Static Rojo configuration is appropriate for small bootstrap placeholders. Large authored maps, detailed props, and final art may use Studio-authored assets when that becomes the better workflow.

## Runtime Object Placement

Future runtime-spawned props and Oddlings should not assume a fixed ground Y.

When runtime placement has an actual consumer, use server-authoritative `Workspace:Raycast()` or another appropriate world query to discover the real placement surface. The raycast result can determine where the object should stand without trusting a client-provided position.

Do not introduce a general placement framework until a production system needs it.

## Models

Future Roblox `Model` instances may have pivots that are not located at their physical bottom.

Model placement should account for:

- `Model` pivot,
- `Model:GetBoundingBox()`,
- bounding-box size and position,
- pivot-to-bottom offset,
- `Model:PivotTo()`.

Avoid assuming `PivotTo(surfacePosition)` automatically means feet, wheels, or the bottom of the model touch the surface.

## Uneven Terrain And Slopes

Raycast results can provide:

- hit `Position`,
- surface `Normal`.

Future placement design should intentionally decide whether each object type:

- stays world-upright,
- aligns to the surface normal,
- or uses another authored orientation rule.

Do not add slope-alignment code until a production object needs it.

## Large And Colossal Objects

Large future Oddlings require more than vertical ground placement.

Future passes may need:

- bounding-volume checks,
- available display area,
- overlap or collision checks,
- workshop clearance constraints.

Do not implement those systems before there is a real spawning or display feature that needs them.

## Art And Design Rule

Physical grounding matters visually.

Characters and props should not appear unintentionally:

- floating,
- buried,
- clipping,
- hovering due to arbitrary offsets.

Intentional hovering is allowed only when it is part of the character or art design.
