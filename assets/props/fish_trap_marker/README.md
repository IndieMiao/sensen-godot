# Fish Trap Marker · SGODOT-402 · v1

Approved concept A: a coral/cream buoy on a short sage stem, tied with rope to a visible woven cage crown.
Instantiate `fish_trap_marker.glb` at **scale 1**. Metres, Y up, +Z front; the origin is the water-surface centre.

| Measurement | Value |
|---|---:|
| Full bounds X × Y × Z | 0.45 × 0.43 × 0.45 m |
| Above the water origin | 0.38 m |
| Submerged skirt | 0.05 m |
| Cage crown above the origin | 0.10 m |
| Buoy body width / height | 0.30 / 0.22 m |
| Triangles / surfaces | 500 / 1 |

The sole opaque matte material uses linear vertex colours, roughness 0.9 and metallic 0. Coral is authored from
the i-trap SVG's **#E07A5F**. There are no textures, skeletons, animations, collisions or water/ripple geometry.
The cage has raised woven strips over a dark recessed dome; the hidden bottom of the short submerged skirt is open.

Keep `material_import.gd`, its `.gd.uid` and the `.glb.import` with the GLB. The importer enables linear vertex colours
and disables shadow casting. `gltf/texture_map_mode=1`; no shadow mesh or animation is imported.

Integration contract:

- Replace only the old trap factory. Remove its `root.scale = Vector3.ONE * FLOAT_SCALE`; the marker already has final dimensions.
- The fishing presentation still uses its existing 1.6 bobber scale. Its actual Godot vertex width is approximately 0.21838 m;
  the marker's 0.30 m buoy is 37.4% wider. The nominal sphere-parameter width 0.224 m is not the tessellated result.
- Keep the existing origin position at water Y=0.055 and its ±0.012 m program motion. The cage crown stays 0.088 m above water at the low point.
- Icons and text remain program UI. At a 360×800 logical viewport, the current 0.6 m prompt anchor covers the upper buoy.
  The review includes a **0.9 m anchor proposal** that clears it; this is for the integrator to review, with no runtime code change in this PR.

Editable source and reproduction: `tools/art/source/fish_trap_marker_402/README.md`.
Review and measured results: `docs/design/fish-trap-marker-402-2026-11-04/README.md`.
