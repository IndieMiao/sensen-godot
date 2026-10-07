# Blacksmith Shop · art review candidate

Plane [SGODOT-178](https://plane.sensenjoy.cn/zili/browse/SGODOT-178), owner Zhao Yun / 赵云. **In Progress, awaiting user review.** Produced 2026-10-07 under the user's request to proceed sequentially overnight and send each scene through Lark CLI.

Reference: Figma file `OMLTC3yw3u2WDjOZhLnhaR`, node [545:2965](https://www.figma.com/design/OMLTC3yw3u2WDjOZhLnhaR/Gensen--US-?node-id=545-2965). The [original export](reference.png) was downloaded and visually inspected before modeling.

![Figma and actual Godot render](comparison.png)

The forge workshop includes a true arched furnace cavity and shallow lining, stone piers and log store, tapered riveted extraction hood, open flue with sculpted smoke, coal bed and fire. The foreground anvil has a flared waist, tapered horn and cut-out hardy socket. Other modules include a small stump-mounted anvil, tool racks, swords, horseshoes, hammers/tongs, quenching barrel, coal bucket, workbench, ingot crate and draped leather apron. The sign retains FORGE WORKSHOP on two lines. The stump anvil instances the same GLB at a uniform 0.48 scale; its collider inherits that transform.

## Deliverables

- [Editable Blender model](../../../tools/art/source/blacksmith_shop/blacksmith_shop.blend), with named objects and module collections.
- [Deterministic scene generator](../../../tools/art/build_blacksmith_shop.py), using the [room pipeline](../../../tools/art/scene_room_pipeline.py).
- [GLB placement and collision manifest](../../../assets/rooms/blacksmith_shop/layout.json), individual local pivots and a shared external base-color/contact-AO atlas.
- [Reusable Godot art scene](../../../scenes/blacksmith_shop/blacksmith_shop_art.tscn), without gameplay/account/network dependencies.
- [Whole-scene runtime image](godot.png), [model orthographic views](orthographic-sheet.png), [budget and verification hashes](verification-summary.json).

## Reconstruction and contract

```sh
blender --background --factory-startup --python "$PWD/tools/art/build_blacksmith_shop.py" -- --views
python3 tools/art/prepare_room_review.py blacksmith_shop
godot --headless --editor --path output/blacksmith_shop-2026-10-07/godot-project --import --quit
godot --path output/blacksmith_shop-2026-10-07/godot-project \
  --script res://tools/art/review_room.gd -- blacksmith_shop \
  "$PWD/output/blacksmith_shop-2026-10-07"
```

Use the actual host display for rendering. Blender 5.2.0 LTS and Godot 4.7.2 were used here. `--geometry-only` skips bake/export. Rebuilding replaces this scene's `.blend`; preserve manual edits deliberately. Source assets from Basic Room remain read-only.

Coordinates are metres, Godot Y-up/front +Z and Blender `(x,-z,y)`. Modules export about their own floor/mounting pivot; placement is in the manifest. The baked atlas contains procedural surface detail and softened contact AO, with live runtime sunlight. Rebake after major rearrangement. Raw GLBs must bind this atlas. Triangulation occurs before UV bake/export to keep surface interpolation consistent, and empty atlas gutters are extended before mip generation.

## Validation and budget

Actual Godot **Mobile / Vulkan**, AMD Custom GPU 0405 (RADV VANGOGH), 1440×1080. 34 meshes have atlas materials and finite nonempty bounds; 13 simple collision shapes are present. The imported triangle count matches the export manifest.

| Metric | Measured |
|---|---:|
| Unique GLBs / placed instances | 33 / 34 |
| Unique / placed triangles | 74,274 / 75,186 |
| Static surfaces | 34 |
| Runtime materials | 2 |
| GLB bytes combined | 3,583,580 |
| Atlas source PNG bytes | 2,543,312 |
| Shared atlas | 2048 × 2048 |

Texture imports enable mipmaps and VRAM compression. Fine geometry keeps uncompressed vertices and disables automatic mesh LODs. Static surface counts exclude renderer shadow passes; PNG bytes are not GPU memory. No physical-phone performance measurement is claimed.

## Inferences and differences

The 6.4 × 6.0m footprint, backs and construction dimensions are inferred. Surface wear, heat shimmer, sparks and smoke motion are simplified: smoke is seven static low-poly puffs, fire is the existing sculpted Basic Room flame kit, and quenching water is a static colored surface. Iron uses a matte stylized response and the hanging tool assortment is reduced. The review renderer uses a single small unshadowed forge light; no particle system or new render pass is required.

Simple boxes cover the main furniture, barrels and forge. Furnace arch, chimney throat and anvil socket are modeled as actual openings. Tool use, forging, physics, walking and resource interactions are outside this art-only scope.

This is an art-only candidate awaiting review. No gameplay/map integration, avatar benchmark, Android QA, production build, migration or release is included.
