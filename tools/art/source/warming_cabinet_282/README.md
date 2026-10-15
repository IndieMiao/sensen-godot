# Warming Cabinet editable source

Author: 刘备 / `0fb1de1f-ead5-443b-9537-54cbac113260`.
Authority: `spec-v1.1.md`, 上官婉儿; concept `SGODOT-282_warming-cabinet-sheet-v1.png`; 不知火舞's Plane comment `10319435-75d5-43dd-8995-221e62028790`.

`warming_cabinet.blend` retains named cabinet boards, feet, frame, one vertical mullion, shelves, bowls/servings, brass fittings, diagonal highlights and an A-only transparent pane. Each mesh has `export_group` and `swatch` properties. Source coordinates are Godot metres converted to Blender `(x,-z,y)`. No baked wood grain, new lights or emissive materials.

Rebuild from repository root (Blender 5.2.2 LTS):

```sh
blender --background --factory-startup --python "$PWD/tools/art/build_warming_cabinet.py"
blender --background --factory-startup --python "$PWD/tools/art/verify_warming_cabinet.py"
python3 tools/art/prepare_warming_cabinet_review.py
godot --headless --path output/warming-cabinet-282/project --editor --import
godot --path output/warming-cabinet-282/project
```

The final Godot command requires a working display. It captures an isolated Vulkan Mobile project, with no player saves, accounts or production autoloads. `output/.gdignore` prevents class-cache pollution. Desktop capture is not a physical-phone performance test.

`atlas-swatches.json` records the existing atlas pixels, original GLB/triangle and source hashes. The optional `select_swatches.py` audit helper requires Pillow/NumPy and recovers those UVs; the builder consumes the committed choices. UVs are constant per triangle so neither original atlas wood grain nor blank regions appear. Main texture is a byte-identical copy, not a rebake. The auxiliary 256² four-color PNG is built deterministically with no image-generation dependency.

`review-fixture.json` freezes the current farm-dev anchors' provenance and seasoning prop transform. It does not change either anchors file. The fixture assembles both real room scenes, their existing shared plants and the Basic spice rack. It retains the existing cabinet warm lamp at its old world position/energy (0.9), adding no lamp to the new asset.

Camera: current P0 default **43° / 6.72 m orthographic width at 360×800**, each kit's own yaw. Fixture is panned to `(-1.1, 1.25, -0.45)` to show the kitchen beside an actual character. Additional 3.5 m detail views are explicitly labeled. Isolated views use neutral kit light with cast shadows off, so they are geometry/material inspections rather than room-lighting claims.

Validation reads actual exported triangles, walks GLB node transforms, audits palette UVs, compares A/B geometry and uses BVHs against all real room modules, instances, shared plants and the anchor spice rack. Twelve back-plane rays per room verify wall/skirting clearance, and deliberate wall penetration is a positive control. The prescribed Y=0.082 has a 0.5 mm foot-support contact with Standard's Y=0.0825 floor, recorded separately. Actual Godot import validates bounds, mesh/surface counts, sockets, per-dish nodes and transparency.

Repeated clean generation produced byte-identical GLBs, PNGs and manifest. `.blend` is the editable source; export-only merged copies are removed before saving.
