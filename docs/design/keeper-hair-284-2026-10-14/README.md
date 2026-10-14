# SGODOT-284 · Auburn and soft-black keeper hair

刘备 · 2026-10-14. Two texture-only hairHat variants assigned by 上官婉儿,
with colors selected by 不知火舞, to widen the generated-city keeper pool.
This work is outside 0.2.6. 苏烈 integrates the parts into world.keeper_looks
after approval; runtime keeper content is unchanged here.

Runtime branch: feat/284-keeper-hair → farm-dev, based on 6a6ebf14 after #407.
Art branch: wp-3d-scene-liubei-keeper-hair-284 → wp-3d-scene, based on 5fbd5da5.
Tested runtime head: **7ae449f52067941690471a004e3ff28fdbd808be**.
The runtime PR contains only assets/avatar/**; the art PR contains this
review, source notes and generation/preparation/audit scripts.

| Part | Base | Triangles | Surface | Original emission / smoothness |
|---|---|---:|---:|---|
| hairhat41_npc_auburn | hairhat41 | 2312 | 1 | 0.7 / 0.1 |
| hairhat43_npc_black | hairhat43 | 1156 | 1 | 0.3 / 0.1 |

Both original FBXs are byte-identical copies, retaining filenames, node names,
hierarchy, transforms, axes and units. Extracted geometry/UVs/normals/indices,
node transforms, offsets and tier match their bases. All five material floats
match each original part; only the albedo PNG reference differs. Source PNGs
are 1024², imported at the original 512² size with mipmaps/VRAM compression.

## Review images

- [npc_lineup front](npc-lineup-front.png), [three-quarter](npc-lineup-three-quarter.png),
  [original combined capture](npc-lineup-both.png).
- Full cards: [auburn, 300×660](keeper_auburn_card.jpg),
  [soft black, 300×660](keeper_black_card.jpg).
- [Postage sheet: actual 32×40 above, 3× 96×120 below](stamps.png).
- Individual stamps: [auburn 32×40](keeper_auburn_stamp_32x40.png),
  [96×120](keeper_auburn_stamp_96x120.png), [black 32×40](keeper_black_stamp_32x40.png),
  [96×120](keeper_black_stamp_96x120.png).
- [Original/recolored atlas comparison](texture-comparison.png).

The review fixtures keeper_auburn / keeper_black both use cloth1 and shoes1.
The npc_lineup renderer uses a two-person fixture with frozen idle and complete
feet framing; front/three-quarter sheets are exact crops with labels.
The existing wp-3d-scene baker ran unchanged with a real window. Original card
and postage outputs, [crop metadata](portrait_crops.json), [looks](looks-new.json)
and [script provenance](review-script-provenance.json) are retained. Individual
stamps are exact crops from the baker's sheet.

Environment: Godot 4.7.2, Vulkan Mobile, Deck AMD Custom GPU 0405 (RADV VANGOGH),
isolated SensenKeeperHair284QA data directory. These are desktop art captures.
The temporary runtime copy of the baker and the QA override were removed.

## Color preservation and validation

Auburn maps original hair luminance through **#5E2F1C / #8A4A2E / #B06A45**,
preserving the ochre and pale pink-white accessory pixels. Soft black maps
hair through **#161312 / #2A2624 / #4A4440**, preserving all pink accessories.
The curves keep the baked light/dark strands and avoid pure black.
The inspected atlases have distinct hair/accessory color families. Selection
rules are R < 128 and R-G < 20 for hairhat41; G-B > 30 for hairhat43.
**324,519 and 40,928 non-hair pixels respectively retain their original RGBA**;
all alpha bytes are unchanged. The output hair retains 165 / 57 RGB levels.

- [Texture audit](texture-validation.json): masks, source min/median/max
  luminance, palettes, preserved pixels and generated hashes.
- [Actual Godot audit](godot-validation.json): **36/36 passed** across the two
  parts, including exact FBX, geometry, imported/extracted transforms,
  all material floats, texture binding and player-pool exclusion.
- [Extraction log](extract.log): **追加完成: 2 部件, 0 错误**.
- [Preservation audit](preservation.json): all original **43 manifest entries
  and text prefix unchanged**, two entries appended (43 → 45); 425 existing
  avatar/pipeline/renderer/resident-table files byte-identical. Base import
  parameters retained; recipes_284.json untouched.
- [Rebuild record](reproducibility.json): all eight FBX/PNG/import files
  byte-identical across consecutive generator runs.
- [Tests](tests.xml) on **7ae449f5**: **38/38 cases, 8/8 suites**, zero errors,
  failures, flaky, skipped or orphan cases. Paths: tests/catalog,
  tests/pipeline, tests/assembly/test_socket_placement.gd. The socket test
  iterates both new NPC hairHat entries. [Log](tests.log).
- [Combined validation](validation.json): exact tested head, measurements,
  material values, looks, image dimensions/hashes and runtime scope.

The GDUnit runner retains its existing port-0 debugger diagnostic and optional
Xbot-fixture warnings; all requested suites exit 0. Runtime worktree is clean
after removing generated untracked UIDs and temporary review files.

## Reproduce using the split checkouts

In the art checkout, with Python Pillow/NumPy and the runtime checkout present:

~~~sh
python3 tools/art/recolor_keeper_hair_284.py --runtime-root /path/to/runtime
python3 tools/art/prepare_keeper_hair_review_284.py --runtime-root /path/to/runtime
cp tools/art/verify_keeper_hair_284.gd /path/to/runtime/output/keeper-hair-284/
cd /path/to/runtime
godot --headless --path . --editor --import
godot --headless --path . --script res://tools/pipeline/extract_parts.gd -- res://assets/avatar/source/recipes_284b.json --append
godot --headless --path . --editor --import
godot --headless --path . --script res://output/keeper-hair-284/verify_keeper_hair_284.gd
GODOT_BIN="$(command -v godot)" ./addons/gdUnit4/runtest.sh -a res://tests/catalog -a res://tests/pipeline -a res://tests/assembly/test_socket_placement.gd
godot --path . --script res://output/keeper-hair-284/npc_lineup_284b.gd -- --out=output/keeper-hair-284/npc-lineup.png
godot --path . --script res://tools/art/bake_resident_portraits.gd -- --looks=output/keeper-hair-284/looks-new.json --ids=keeper_auburn,keeper_black --out=output/keeper-hair-284/portraits
~~~

Already registered IDs are skipped. For regeneration, remove only the relevant
manifest entries before --append, following README_229. Never omit --append.
The last two commands require a display. The preparation script copies the
existing art-branch baker unchanged; do not add it to the runtime PR.
Remove the temporary baker, its UID and override.cfg afterwards.
[Runtime source instructions](https://github.com/IndieMiao/sensen-godot/blob/7ae449f52067941690471a004e3ff28fdbd808be/assets/avatar/source/README_284b.md).
No Blender geometry export is involved in these texture-only variants.

All review images and reports are delivered to
[SGODOT-284](https://plane.sensenjoy.cn/zili/browse/SGODOT-284/) with prefix
SGODOT-284_KEEPER_HAIR_v1_, as 刘备
(virtual_user_id 0fb1de1f-ead5-443b-9537-54cbac113260).
[Receipt](delivery-verification.json) confirms downloaded SHA-256 and uploader.
The review archive includes all images, individual stamps, audits and test XML/log.
Cross-review: 后裔; technical: 上官婉儿; visual: 不知火舞; user approval before merge.
