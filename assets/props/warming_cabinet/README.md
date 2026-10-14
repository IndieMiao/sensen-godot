# Warming Cabinet — SGODOT-282 v1.1

Two review options share identical cabinet, six servings and diagonal highlights:

- `warming_cabinet_a.glb`: alpha 0.15 glass pane; 1492 triangles, 9 mesh nodes, 15 surfaces, 3 materials.
- `warming_cabinet_b.glb`: no glass pane; 1490 triangles, 8 mesh nodes, 14 surfaces, 2 materials. Visual review currently prefers this approach; final choice remains with 不知火舞.

Import at scale 1. Dimensions **0.56 W × 0.50 D × 1.32 H metres**. Godot Y up, face +Z. Origin is floor level at the width centre of the **back plane Z=0**. Bounds, suggested box collider, sockets and review placements are in `manifest.json`; there are no collision or light nodes in either GLB.

`dish_1` through `dish_6` are separate MeshInstance3D nodes, each containing one bowl and serving. Order: upper left/right, middle left/right, bottom left/right, viewed from +Z. Their mesh transforms are identity; hide each node to remove one complete serving. `top_center`, `door_center` and `glow` are empty nodes. Door face Z=0.478, so `door_center` is 0.020 m in front of it. No horizontal door mullion.

Both GLBs reference the same external PNGs, so they import directly without runtime material replacement:

- `room_albedo_ao.png` is an **unchanged byte-for-byte copy** of the existing `warming_cabinet_placeholder` / Deluxe Room atlas, SHA-256 `9802eca7bf7b4607d712fbb99c0d6ab3acf48ba2638a8734177160bbeb4f1360`. This copy makes the new directory independently integrable: the placeholder directory is absent on the art branch. UVs sample constant existing color points; no wood grain is introduced. The source atlas is never modified.
- `interior_food.png` is the allowed 256×256 auxiliary palette for amber lining, shelf undersides, orange stew and golden bread. Neither opaque material emits light. A adds only its transparent glass material.

Keep these per-surface materials: applying the room's blanket `material_override` would erase the auxiliary palette and A's transparency. Godot imports A's glTF BLEND material as alpha depth prepass, with alpha exactly 0.15. Six independent dishes account for the multiple mesh nodes/surfaces.

Placement proposal only; this PR does not edit anchors:

| Room | Position | Yaw |
|---|---|---|
| Basic | (-2.850, 0.082, -1.690) | 90° |
| Standard | (-2.916, 0.082, -1.190) | 90° |

Standard uses the full v1.1 prop coordinate -2.916, with clearance from the -2.918 nominal back reference. The specified ground Y=0.082 is 0.5 mm below Standard's plank tops at 0.0825; this existing foot-support contact is recorded separately from obstacles. No intersections with walls, skirting, window, window plants, bookshelf/stool or spice rack were found.

Editable source and production scripts live on **wp-3d-scene**:
`tools/art/source/warming_cabinet_282/warming_cabinet.blend`,
`tools/art/build_warming_cabinet.py`. Review evidence is at
`docs/design/warming-cabinet-282-2026-10-14/`.

Art delivery only; not part of 0.2.6. 上官婉儿 handles technical review/integration, 不知火舞 visual acceptance, and the user approves merging. Programmers replace anchors separately.
