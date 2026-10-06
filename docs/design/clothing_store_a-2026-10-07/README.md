# Clothing Store A — SGODOT-186

Review draft produced by 刘备 on 2026-10-07. User art approval is pending; Plane remains In Progress.

## Reference and visual scope

Actual Figma export: file `OMLTC3yw3u2WDjOZhLnhaR`, node `545:2959`.
[Reference](https://www.figma.com/design/OMLTC3yw3u2WDjOZhLnhaR/Gensen--US-?node-id=545-2959). Local export SHA-256: `696c1ba820110951c0a21d8b1f571d12806773fd5f3dc70252f0e8da432a085a`.
The full image was inspected before modeling. Geometry is original; unshown backs, depths and metre dimensions are inferred.

![Reference and runtime comparison](comparison.png)

## Deliverables and rebuild

- Editable named Blender objects/collections: `tools/art/source/clothing_store_a/clothing_store_a.blend`.
- Generator: `tools/art/build_clothing_store_a.py`; shared helpers remain in the Coffee Shop source directory. Basic Room is unchanged.
- Runtime modules, atlas, layout/collisions and budget: `assets/rooms/clothing_store_a/`.
- Reusable art scene: `scenes/clothing_store_a/clothing_store_a_art.tscn`. Contains artwork and simple box collisions only.
- Godot metres, Y up, front +Z; each GLB has its own floor/mount pivot. Repeated objects use the same GLB.

```sh
blender --background --factory-startup --python "$PWD/tools/art/build_clothing_store_a.py"
python3 tools/art/render_shop_review.py clothing_store_a
```

For manual source edits, use `-- --bake-only` to rebake/export the saved source. A full rebuild overwrites the generated `.blend`; preserve intentional edits first.
The renderer needs the current host's legitimate DISPLAY/XAUTHORITY. Pillow is needed only for packaging comparison images.

## Asset budget

| Metric | Value |
|---|---:|
| Unique GLBs / placed instances | 43 / 64 |
| Unique / placed triangles | 70,398 / 90,716 |
| Static mesh surfaces | 64 |
| Shared atlas | 2048 × 2048, mipmaps + VRAM compression |
| GLB bytes, total | 2,408,300 |
| Atlas PNG bytes | 3,121,515 |

One shared matte atlas material; separate soft translucent material for glass modules where present. Color/surface detail and softened contact AO are baked; direct lighting remains dynamic. Padded palette swatches protect subpixel detail from black seams. Major rearrangements require rebaking contact AO.

## Verification and limits

Blender 5.2.2 LTS; Godot 4.7.2 Mobile/Vulkan on `AMD Custom GPU 0405 (RADV VANGOGH)`. All 43 GLBs pass container/mesh/surface checks and contain no duplicated embedded images; the assembled render contains all 64 instances. Whole/detail/front/side/top images rendered at 1400 × 1400. Source import settings are retained beside the atlas.

The images are real Godot renders of the exported models. No Android, character/movement benchmark, gameplay integration, release or physical-phone performance claim is part of these art-only cards.

Differences / inferred choices: The black/blue BLOCK THEORY layout, English wall slogans, black pendant trio, changing-room curtain, wood/steel display table, checkout, streetwear racks and front bench follow the reference. Clothing/racks share the B boutique generator; hoodies, varsity jackets, cargos, caps and sneakers are static display props with simplified folds. Shirt graphics and the monochrome art are original schematic marks, without the detailed concept prints or shoe brand emblem. Graffiti has fewer strokes, plants are sparser and the concrete tile pattern is more regular. The mirror uses a painted highlight and lamps have no local light/glow; the shared matte atlas does not reproduce metallic reflections. Exterior door scenery and small tabletop greenery are omitted. Unseen construction/dimensions are inferred; no wearable garments, store UI or gameplay are included.

![Actual model orthographic views](orthographic.png)

Delivery: Lark self-review messages and downloaded-attachment verification are recorded privately under `output/clothing_store_a/delivery/`; no chat identifiers or credentials are committed.
