# SGODOT-284 / q(171) · Ivo hat flat-light correction

刘备 · 2026-10-14. Following [后裔's cross-review](https://github.com/IndieMiao/sensen-godot/pull/407#issuecomment-6161655966)
and 上官婉儿's clarification, `hairhat_npc_ivo` now uses
`emission_strength=0.3`, matching its base hairHat. In `avatar_toon.gdshader`,
this is flat lighting for the whole mesh; it is not a separate lamp glow.
The lamp has no extra light/effect, and smoothness stays 0.05.
刘备 posted [还有增量，先别合](https://github.com/IndieMiao/sensen-godot/pull/407#issuecomment-6162278416)
before pushing.

Runtime #407 head: **`00ab44bed29e77a8629ecf361cbe2e99ad68f16d`**.
The small commit changes exactly three files: the recipe, the corresponding
material parameter in the extracted hat scene, and README_284's explanation
and stable `wp-3d-scene` links. All art evidence stays in #412.

## Current Ivo images

- [Full-body card, 300×660](ivo_card.jpg).
- [Postage sheet, actual 32×40 above and 3× 96×120 below](stamps.png).
- Exact individual crops: [32×40](ivo_stamp_32x40.png), [96×120](ivo_stamp_96x120.png).

Look: `hairhat_npc_ivo + mask16_npc_ivo + cloth1_npc_ivo + shoes3`.
The supplied baker ran unchanged with a real Godot 4.7.2 / Vulkan Mobile window
on the Deck AMD Custom GPU 0405 (RADV VANGOGH). Card and stamp sheet are original
baker outputs; individual stamps are exact crops. See [looks](looks-new.json),
[crop metadata](portrait_crops.json) and [script provenance](review-script-provenance.json).
The baker and QA fixtures are not committed. These images supersede Ivo's
earlier zero-emission images; Granny Wu and Tomo retain their prior accepted looks.

## Verification

- [Extraction](extract.log): removed only `hairhat_npc_ivo` from the manifest,
  then `--append` reported **追加完成: 1 部件, 0 错误**; the other four recipe IDs skipped.
- [Preservation](preservation.json): every regenerated manifest entry matches
  the original; original order was retained so the entire 43-entry manifest
  is byte-identical. After checking that only the emission parameter and
  random generated node IDs differed, the original node IDs were retained.
  The scene now differs by one material value only. **424 other files are
  byte-identical**, including all FBX/PNGs, other parts and npc_only.
- [Actual import audit](godot-validation.json): **37/37 passed**, including
  runtime hat emission 0.3, original frame/transform preservation, one surface
  and the unchanged 1423 triangles.
- [Final-head tests](tests.xml): **8/8 suites, 38/38 tests passed**, zero errors,
  failures, flaky, skipped or orphan cases, on runtime head `00ab44be`.
  Paths: `tests/catalog`, `tests/pipeline`, `tests/assembly/test_socket_placement.gd`.
  [Log](tests.log) and [combined validation](validation.json) include the exact head.

The test runner retains its existing port-0 debugger diagnostic and optional
Xbot-fixture warnings; all requested suites exit successfully. Temporary
baker, QA override and generated untracked UIDs were removed after the run.

## Reproduce

The runtime recipe already contains 0.3. In a #407 checkout, remove only the
Ivo hat manifest entry before re-extracting with `--append`, as documented in
README_229. Compare the resulting entry with its original, preserve the
original manifest order and retain original random node IDs when otherwise
identical. Do not change geometry or textures.

Use the #412 art checkout to prepare the runtime review directory:

```sh
python3 tools/art/prepare_resident_parts_review.py --project-root /path/to/runtime --out output/resident-parts-284-ivo-light
cp tools/art/verify_resident_parts_284.gd /path/to/runtime/output/resident-parts-284-ivo-light/
cd /path/to/runtime
godot --headless --path . --script res://output/resident-parts-284-ivo-light/verify_resident_parts_284.gd -- --out=output/resident-parts-284-ivo-light
godot --path . --script res://tools/art/bake_resident_portraits.gd -- --looks=output/resident-parts-284-ivo-light/looks-new.json --ids=res_ivo --out=output/resident-parts-284-ivo-light/portraits
```

The last command requires a display. Remove the temporary baker, its UID and
`override.cfg` after review. [Delivery receipt](delivery-verification.json):
new cards, stamps, validation and a complete review archive uploaded to
[SGODOT-284](https://plane.sensenjoy.cn/zili/browse/SGODOT-284/) under prefix
`SGODOT-284_IVO_LIGHT_v1_`, with 刘备's virtual identity
`0fb1de1f-ead5-443b-9537-54cbac113260`; downloads and uploader identity verified.
Cross-review: 后裔; technical: 上官婉儿; visual: 不知火舞; merge after user approval.
