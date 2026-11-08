# Alcatraz middle stairs A — SGODOT-424

This is an incremental art/data generator pinned to art base `edd184d65`. It preserves the accepted island assets and only clips the two ground meshes where the new closed stairs/platforms replace their surface. No gameplay scripts or production tests are edited.

- `baseline_layout.json`: immutable input from the base.
- `layout.py`: placements, 6 openings / 12 terminals, 4 bench moves, navigation and data contract. Requires Shapely >=2.1. Named fields and measurements are in `construction.json`.
- `build.py`: Blender named treads/platforms/terminal and exact triangle clipping of base ground. Interpolates and preserves vertex colour, normals and UV. Requires the base Git object to be available.
- `alcatraz_mid_stairs.blend`: editable incremental source, with named construction cutters. It supplements the existing complete-island blend.
- `route_verified.json`: actual Godot NavigationServer path and its navigation-data SHA. Refuses stale route evidence after a navigation change. Centerline uses the existing straight-flight convention; actual tread distance is also retained.
- `review.gd`: native P0 fixture, true navigation/walking, physical click and foot probes, HUD audit, overhead and 360×800 stills. Copy it into the isolated current-P0 review project. `hud_helper.gd` is copied from the original island review tool; no in-game HUD code is modified.
- `check_review.py`: NumPy near-tree ray intersections over live nav samples and the route.
- `verify_old_routes.gd`: read-only Godot proof of all original stair corridors and original route legs.

Generate layout with Python/Shapely, then always use the shared lock for Blender/Godot:

```sh
python3 tools/art/source/alcatraz_mid_stairs_424/layout.py
flock ~/gs66-render.lock blender --background --factory-startup --python "$PWD/tools/art/source/alcatraz_mid_stairs_424/build.py"
```

For a layout change, refresh `route_verified.json` from the actual Godot map before final export; do not hand-adjust the reported distance. The runtime probe uses the same .25 m/.1 m map and region geometry as the landmark. The current source staging uses P0 base `cf82ca0ac` (#886); preserve its two landmark scripts when overlaying art assets.

The renderer already merges `render_merge_into` placements into the terrace mesh. New guard/endpost transforms remain in layout, with that flag, so their collision follows actual triangles instead of the old conservative sloped-rail boxes. Use master `layout.placements` as the full placement/collision/render contract; `placement_points.json` remains the transform handoff.

See `docs/design/alcatraz-mid-stairs-424-2026-11-08/README.md` for exact coordinates, width/route metrics, the existing summit flowerbed issue, global canopy baseline, and validation. This is a draft proposal awaiting the user's road approval.
