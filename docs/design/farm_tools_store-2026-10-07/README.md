# Farm Tools Store · art review candidate

Plane [SGODOT-174](https://plane.sensenjoy.cn/zili/browse/SGODOT-174), owner Zhao Yun / 赵云. **In Progress, awaiting user review.** Produced 2026-10-07 under the user's request to proceed sequentially overnight and send each scene through Lark CLI.

Reference: Figma file `OMLTC3yw3u2WDjOZhLnhaR`, node [545:2961](https://www.figma.com/design/OMLTC3yw3u2WDjOZhLnhaR/Gensen--US-?node-id=545-2961). The [original export](reference.png) was downloaded and visually inspected before modeling.

![Figma and actual Godot render](comparison.png)

The farm tools shop keeps the warm timber/plaster shell, real arched window, green entrance and English FARM TOOLS sign. New editable modules include a planked sales counter with register, pegboard tools, long shovel/fork/rake rack, seed packet shelves, open terracotta pots, watering cans, display table with gloves and sacks, tool barrel and supply crates. Repeated seed packets share one GLB; other goods remain named inside their source modules.

## Deliverables

- [Editable Blender model](../../../tools/art/source/farm_tools_store/farm_tools_store.blend), with named objects and module collections.
- [Deterministic scene generator](../../../tools/art/build_farm_tools_store.py), using the [room pipeline](../../../tools/art/scene_room_pipeline.py).
- [GLB placement and collision manifest](../../../assets/rooms/farm_tools_store/layout.json), individual local pivots and a shared external base-color/contact-AO atlas.
- [Reusable Godot art scene](../../../scenes/farm_tools_store/farm_tools_store_art.tscn), without gameplay/account/network dependencies.
- [Whole-scene runtime image](godot.png), [model orthographic views](orthographic-sheet.png), [budget and verification hashes](verification-summary.json).

## Reconstruction and contract

```sh
blender --background --factory-startup --python "$PWD/tools/art/build_farm_tools_store.py" -- --views
python3 tools/art/prepare_room_review.py farm_tools_store
godot --headless --editor --path output/farm_tools_store-2026-10-07/godot-project --import --quit
godot --path output/farm_tools_store-2026-10-07/godot-project \
  --script res://tools/art/review_room.gd -- farm_tools_store \
  "$PWD/output/farm_tools_store-2026-10-07"
```

Use the actual host display for rendering. Blender 5.2.0 LTS and Godot 4.7.2 were used here. `--geometry-only` skips bake/export. Rebuilding replaces this scene's `.blend`; preserve manual edits deliberately. Source assets from Basic Room remain read-only.

Coordinates are metres, Godot Y-up/front +Z and Blender `(x,-z,y)`. Modules export about their own floor/mounting pivot; placement is in the manifest. The baked atlas contains procedural surface detail and softened contact AO, with live runtime sunlight. Rebake after major rearrangement. Raw GLBs must bind this atlas. Triangulation occurs before UV bake/export to keep surface interpolation consistent, and empty atlas gutters are extended before mip generation.

## Validation and budget

Actual Godot **Mobile / Vulkan**, AMD Custom GPU 0405 (RADV VANGOGH), 1440×1080. 41 meshes have atlas materials and finite nonempty bounds; 7 simple collision shapes are present. The imported triangle count matches the export manifest.

| Metric | Measured |
|---|---:|
| Unique GLBs / placed instances | 36 / 41 |
| Unique / placed triangles | 82,824 / 85,144 |
| Static surfaces | 41 |
| GLB bytes combined | 3,313,008 |
| Atlas source PNG bytes | 2,867,417 |
| Shared atlas | 2048 × 2048 |

Texture imports enable mipmaps and VRAM compression. Fine geometry keeps uncompressed vertices and disables automatic mesh LODs. Static surface counts exclude renderer shadow passes; PNG bytes are not GPU memory. No physical-phone performance measurement is claimed.

## Inferences and differences

The 6.8 × 6.0m footprint, hidden backs and aisle dimensions are inferred from a single perspective. Compared with the source image, the register and plants use simpler geometry, the gloves are flatter, and labels use original crop emblems rather than detailed print. FARM TOOLS remains verbatim English. The round lantern replaces a more elaborate door-side fixture. Broad layout and colors are retained, with real-time lighting and lower-frequency surface detail.

Colliders are simple authored volumes for downstream integration; this art delivery does not establish avatar-controller behavior.

This is an art-only candidate awaiting review. No gameplay/map integration, avatar benchmark, Android QA, production build, migration or release is included.
