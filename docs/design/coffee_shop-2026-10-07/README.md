# Coffee Shop — SGODOT-179

Review draft produced by 刘备 on 2026-10-07. User art approval is pending; Plane remains In Progress.

## Reference and visual scope

Actual Figma export: file `OMLTC3yw3u2WDjOZhLnhaR`, node `545:2956`.
[Reference](https://www.figma.com/design/OMLTC3yw3u2WDjOZhLnhaR/Gensen--US-?node-id=545-2956). Local export SHA-256: `bac78a88a5cb5fdc3aa2d2e7a026c31ec402bc84b5a978c84413c2951d44ce7a`.
The full image was inspected before modeling. Geometry is original; unshown backs, depths and metre dimensions are inferred.

![Reference and runtime comparison](comparison.png)

## Deliverables and rebuild

- Editable named Blender objects/collections: `tools/art/source/coffee_shop/coffee_shop.blend`.
- Generator: `tools/art/build_coffee_shop.py`; shared helpers remain in the Coffee Shop source directory. Basic Room is unchanged.
- Runtime modules, atlas, layout/collisions and budget: `assets/rooms/coffee_shop/`.
- Reusable art scene: `scenes/coffee_shop/coffee_shop_art.tscn`. Contains artwork and simple box collisions only.
- Godot metres, Y up, front +Z; each GLB has its own floor/mount pivot. Repeated objects use the same GLB.

```sh
blender --background --factory-startup --python "$PWD/tools/art/build_coffee_shop.py"
python3 tools/art/render_shop_review.py coffee_shop
```

For manual source edits, use `-- --bake-only` to rebake/export the saved source. A full rebuild overwrites the generated `.blend`; preserve intentional edits first.
The renderer needs the current host's legitimate DISPLAY/XAUTHORITY. Pillow is needed only for packaging comparison images.

## Asset budget

| Metric | Value |
|---|---:|
| Unique GLBs / placed instances | 32 / 52 |
| Unique / placed triangles | 110,588 / 166,484 |
| Static mesh surfaces | 52 |
| Shared atlas | 2048 × 2048, mipmaps + VRAM compression |
| GLB bytes, total | 2,873,560 |
| Atlas PNG bytes | 3,711,561 |

One shared matte atlas material; separate soft translucent material for glass modules where present. Color/surface detail and softened contact AO are baked; direct lighting remains dynamic. Padded palette swatches protect subpixel detail from black seams. Major rearrangements require rebaking contact AO.

## Verification and limits

Blender 5.2.2 LTS; Godot 4.7.2 Mobile/Vulkan on `AMD Custom GPU 0405 (RADV VANGOGH)`. All 32 GLBs pass container/mesh/surface checks and contain no duplicated embedded images; the assembled render contains all 52 instances. Whole/detail/front/side/top images rendered at 1400 × 1400. Source import settings are retained beside the atlas.

The images are real Godot renders of the exported models. No Android, character/movement benchmark, gameplay integration, release or physical-phone performance claim is part of these art-only cards.

Differences / inferred choices: Window gardens use simplified opaque stylized glazing without refraction. Vines are more regular and less dense than the concept, and floor plants use broad leaves instead of split monstera leaves. Chair/rug weaving and surface detail are simplified; runtime shadows are firmer than the painted reference. Hidden backs and construction depths are inferred.

![Actual model orthographic views](orthographic.png)

Delivery: Lark self-review messages and downloaded-attachment verification are recorded privately under `output/coffee_shop/delivery/`; no chat identifiers or credentials are committed.
