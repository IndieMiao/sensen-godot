# SGODOT-284 / q(171) · Ivo canvas clothing and revised footwear

刘备 · 2026-10-14. This revision replaces Ivo's rejected cloth42 outfit with
`cloth1_npc_ivo`, following 不知火舞's acceptance comment
`87e87ff2-ddef-4f65-b9bf-f2c309acda69` and 上官婉儿's assignment.
The director posted [还有增量，先别合](https://github.com/IndieMiao/sensen-godot/pull/407#issuecomment-6161625935)
before this increment. Runtime assets remain in #407 → farm-dev; these review
materials and art scripts remain in #412 → wp-3d-scene.

Final review looks ([JSON](looks-new.json)):

- Ivo: `hairhat_npc_ivo + mask16_npc_ivo + cloth1_npc_ivo + shoes3`.
- Granny Wu: `hairhat80_npc_granny_wu + cloth11 + shoes5`, no glasses.

Granny Wu's hair is already accepted and was retained; the optional darker
silver adjustment was not taken. All four previously delivered parts, the
original cloth1, footwear and runtime resident table remain byte-identical.
The director / 苏烈 integrates the final looks and production portraits separately.

## Review images

- [Front](npc-lineup-front.png), [three-quarter](npc-lineup-three-quarter.png),
  [original combined npc_lineup](npc-lineup-both.png).
- Full cards: [Ivo 300×660](ivo_card.jpg), [Granny Wu 300×660](granny_wu_card.jpg).
- [Postage sheet: actual 32×40 above, 3× 96×120 below](stamps.png).
- Exact crops: [Ivo 32×40](ivo_stamp_32x40.png), [96×120](ivo_stamp_96x120.png),
  [Granny Wu 32×40](granny_wu_stamp_32x40.png), [96×120](granny_wu_stamp_96x120.png).

Godot 4.7.2, Vulkan Mobile, Deck AMD Custom GPU 0405 (RADV VANGOGH).
The supplied portrait baker ran unchanged with a real window and isolated
`SensenResident284QA` data. Original card/stamp outputs and crop metadata are
retained. The lineup uses the existing renderer with a two-person fixture,
frozen idle and complete-foot framing; individual views are exact crops with
labels. [Script provenance](review-script-provenance.json) records hashes.
The supplied baker is not committed. This is desktop art review.

## Texture and import validation

`cloth1_npc_ivo` uses the cloth slot and mesh attachment: **1629 triangles,
one surface, 59 skin binds**, source texture 1024², runtime 512² with the
original mipmaps/compression and material parameters. The copied FBX retains
all original bytes, nodes, hierarchy, transforms, axes and units.

Shirt luminance maps through shadow/mid/highlight `#7A5E3E / #9C7A52 / #B8966A`;
shorts map through `#26231F / #3A3632 / #55504A`. The source shirt region is
mostly a single base color, so that plateau maps to the prescribed midtone;
existing lighter variations remain, with no invented texture. Shorts retain
their faint baked shading. The actual masks cover 62.49% shirt and 30.83%
shorts; the remaining 6.68% of light-grey details/buttons and all alpha bytes
are unchanged. The unchanged FBX keeps its legacy texture reference; the
recipe explicitly binds `T_ivo_cloth_D.png` to the extracted runtime material.

- [Import audit](cloth-import-validation.json): **16/16 passed**, including
  exact geometry, normals, UVs, indices, bone weights, skeleton rest and skin
  binds compared with cloth1, plus material and NPC-only catalog checks.
- [Extraction log](extract.log): `追加完成: 1 部件, 0 错误`; four existing IDs skipped.
- [Preservation](preservation.json): manifest **42 → 43**, only the new ID
  appended; existing entries and text prefix exact. 416 existing asset,
  renderer, pipeline and resident-table files remain byte-identical.
- [Texture audit](texture-validation.json) and [rebuild](reproducibility.json):
  consecutive generated FBX/PNG/import files are byte-identical.
- [Final-head tests](tests.xml): **38/38 passed, 8/8 suites; zero errors,
  failures, flaky, skipped or orphan cases**, on runtime commit
  `7575a81b366ded5a016dc25749eb0412e9598a16`. Paths: `tests/catalog`,
  `tests/pipeline`, `tests/assembly/test_socket_placement.gd`.
  See [test log](tests.log) and [combined validation](validation.json).

The test runner retains its existing port-0 debugger diagnostic and optional
Xbot-fixture warnings; all requested suites finish with exit code 0.
Temporary baker, QA override and generated untracked UIDs were removed after
testing; the runtime worktree is clean at the tested commit.

## Reproduce across the split branches

Use a runtime checkout of #407 and this art checkout of #412. With Pillow/NumPy
and Godot available, run from the art checkout (substitute the real runtime path):

```sh
python3 tools/art/recolor_ivo_cloth_284.py --runtime-root /path/to/runtime
python3 tools/art/prepare_resident_parts_review.py --project-root /path/to/runtime --out output/resident-parts-284-ivo-cloth
cp tools/art/verify_ivo_cloth_284.gd /path/to/runtime/output/resident-parts-284-ivo-cloth/
cd /path/to/runtime
godot --headless --path . --editor --import
# Existing IDs are skipped. To re-extract this part, remove ONLY its manifest
# entry first; preserve every other entry as documented in README_229.md.
godot --headless --path . --script res://tools/pipeline/extract_parts.gd -- res://assets/avatar/source/recipes_284.json --append
godot --headless --path . --editor --import
godot --headless --path . --script res://output/resident-parts-284-ivo-cloth/verify_ivo_cloth_284.gd
GODOT_BIN="$(command -v godot)" ./addons/gdUnit4/runtest.sh -a res://tests/catalog -a res://tests/pipeline -a res://tests/assembly/test_socket_placement.gd
godot --path . --script res://output/resident-parts-284-ivo-cloth/npc_lineup_284.gd -- --out=output/resident-parts-284-ivo-cloth/npc-lineup.png
godot --path . --script res://tools/art/bake_resident_portraits.gd -- --looks=output/resident-parts-284-ivo-cloth/looks-new.json --ids=res_granny_wu,res_ivo --out=output/resident-parts-284-ivo-cloth/portraits
```

Run the last two commands with a display, not headless. Preparation copies the
unchanged baker from `~/incoming/resident-parts/`; remove the temporary baker,
its generated UID and `override.cfg` afterwards. Never commit these fixtures.

Review images and validation are delivered to
[SGODOT-284](https://plane.sensenjoy.cn/zili/browse/SGODOT-284/) as 刘备
(`0fb1de1f-ead5-443b-9537-54cbac113260`), using the prefix
`SGODOT-284_IVO_CLOTH_v1_`; downloaded hashes and uploader identity are checked
in the [delivery receipt](delivery-verification.json). The accompanying archive
contains all review images, individual stamps, audits and the test log/XML.
Cross-review: 后裔; technical: 上官婉儿; visual: 不知火舞; merge after user approval.
