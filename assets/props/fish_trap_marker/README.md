# Fish Trap Marker · SGODOT-402 · v1.1

Approved concept A: a coral/cream buoy on a short sage stem, tied with rope to a visible woven cage crown.
Instantiate `fish_trap_marker.glb` at **scale 1**. Metres, Y up, +Z front; the origin is the water-surface centre.
User approval C64 (2026-11-04 13:55) requested a larger cage. The **1.35× enlargement is baked into every vertex**,
including the Blender source. Style, vertex colours, triangle count and the waterline pivot are retained.

| Measurement | Value |
|---|---:|
| Full bounds X × Y × Z | 0.6075 × 0.5805 × 0.6075 m |
| Above the water origin | 0.513 m |
| Submerged skirt | 0.0675 m |
| Cage crown above the origin | 0.135 m |
| Buoy body width / height | 0.405 / 0.297 m |
| Triangles / surfaces | 500 / 1 |

The sole opaque matte material uses linear vertex colours, roughness 0.9 and metallic 0. Coral is authored from
the i-trap SVG's **#E07A5F**. There are no textures, skeletons, animations, collisions or water/ripple geometry.
The cage has raised woven strips over a dark recessed dome; the hidden bottom of the short submerged skirt is open.

Keep `material_import.gd`, its `.gd.uid` and the `.glb.import` with the GLB. The importer enables linear vertex colours
and disables shadow casting. `gltf/texture_map_mode=1`; no shadow mesh or animation is imported.

Integration contract:

- Replace only the old trap factory. Remove its `root.scale = Vector3.ONE * FLOAT_SCALE`; the marker already has final dimensions.
- The fishing presentation still uses its existing 1.6 bobber scale. Its actual Godot vertex width is approximately 0.21838 m;
  the marker's 0.405 m buoy is approximately 85.5% wider. The nominal sphere-parameter width 0.224 m is not the tessellated result.
- Keep the existing origin position at water Y=0.055 and its ±0.012 m program motion. The cage crown stays 0.123 m above water at the low point.
- **Approved name-bar anchor: 1.15 m above the marker origin.** At integration, change
  `p0_pond.gd:606` from `Vector3(0, 0.6, 0)` to `Vector3(0, 1.15, 0)` in `_trap_frame`.
  This supersedes the earlier 1.0 m decision. The review applies this exact change only in a private b1 copy;
  runtime scene code is not part of this art PR. Icons and text remain program UI.

Editable source and reproduction: `tools/art/source/fish_trap_marker_402/README.md`.
Review and measured results: `docs/design/fish-trap-marker-402-2026-11-04/README.md`.
