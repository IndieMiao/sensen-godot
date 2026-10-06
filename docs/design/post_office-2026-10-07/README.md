# Post Office · art review candidate

Plane [SGODOT-176](https://plane.sensenjoy.cn/zili/browse/SGODOT-176), owner Zhao Yun / 赵云. **In Progress, awaiting user review.** Produced 2026-10-07 under the user's request to proceed sequentially overnight and send each scene through Lark CLI.

Reference: Figma file `OMLTC3yw3u2WDjOZhLnhaR`, node [545:2967](https://www.figma.com/design/OMLTC3yw3u2WDjOZhLnhaR/Gensen--US-?node-id=545-2967). The [original export](reference.png) was downloaded and visually inspected before modeling.

![Figma and actual Godot render](comparison.png)

The post office uses copper-brown timber, a blue panelled entrance and service counter, red pillar box with a cut-out slot, sorting cabinet with twelve repeated letter stacks, parcel shelving and canvas mailbags. The packing table holds a carton, twine, a scale and stationery. A wall clock, decorative world map and POST OFFICE sign retain the reference identity. Crates, packing tools and plants remain individually named in the editable source.

## Deliverables

- [Editable Blender model](../../../tools/art/source/post_office/post_office.blend), with named objects and module collections.
- [Deterministic scene generator](../../../tools/art/build_post_office.py), using the [room pipeline](../../../tools/art/scene_room_pipeline.py).
- [GLB placement and collision manifest](../../../assets/rooms/post_office/layout.json), individual local pivots and a shared external base-color/contact-AO atlas.
- [Reusable Godot art scene](../../../scenes/post_office/post_office_art.tscn), without gameplay/account/network dependencies.
- [Whole-scene runtime image](godot.png), [model orthographic views](orthographic-sheet.png), [budget and verification hashes](verification-summary.json).

## Reconstruction and contract

```sh
blender --background --factory-startup --python "$PWD/tools/art/build_post_office.py" -- --views
python3 tools/art/prepare_room_review.py post_office
godot --headless --editor --path output/post_office-2026-10-07/godot-project --import --quit
godot --path output/post_office-2026-10-07/godot-project \
  --script res://tools/art/review_room.gd -- post_office \
  "$PWD/output/post_office-2026-10-07"
```

Use the actual host display for rendering. Blender 5.2.0 LTS and Godot 4.7.2 were used here. `--geometry-only` skips bake/export. Rebuilding replaces this scene's `.blend`; preserve manual edits deliberately. Source assets from Basic Room remain read-only.

Coordinates are metres, Godot Y-up/front +Z and Blender `(x,-z,y)`. Modules export about their own floor/mounting pivot; placement is in the manifest. The baked atlas contains procedural surface detail and softened contact AO, with live runtime sunlight. Rebake after major rearrangement. Raw GLBs must bind this atlas. Triangulation occurs before UV bake/export to keep surface interpolation consistent, and empty atlas gutters are extended before mip generation.

## Validation and budget

Actual Godot **Mobile / Vulkan**, AMD Custom GPU 0405 (RADV VANGOGH), 1440×1080. 49 meshes have atlas materials and finite nonempty bounds; 9 simple collision shapes are present. The imported triangle count matches the export manifest.

| Metric | Measured |
|---|---:|
| Unique GLBs / placed instances | 35 / 49 |
| Unique / placed triangles | 67,960 / 78,004 |
| Static surfaces | 49 |
| GLB bytes combined | 2,804,576 |
| Atlas source PNG bytes | 2,576,486 |
| Shared atlas | 2048 × 2048 |

Texture imports enable mipmaps and VRAM compression. Fine geometry keeps uncompressed vertices and disables automatic mesh LODs. Static surface counts exclude renderer shadow passes; PNG bytes are not GPU memory. No physical-phone performance measurement is claimed.

## Inferences and differences

The 6.6 × 6.0m floor and hidden geometry are inferred. The paper labels use generic strokes, not real addresses. The world map is an original simplified decorative silhouette, not geographic navigation data. The card beside the door uses a botanical placeholder and the register uses the shared shop design. The parcel pile is less dense and material wear is simplified. The English POST OFFICE wording is preserved.

The door aperture and letter-box slot are real cutouts. Room containment and large furnishings use simple boxes; paper, labels, hands and parcels are decorative. No route transition, postal interaction or character traversal is implemented.

This is an art-only candidate awaiting review. No gameplay/map integration, avatar benchmark, Android QA, production build, migration or release is included.
