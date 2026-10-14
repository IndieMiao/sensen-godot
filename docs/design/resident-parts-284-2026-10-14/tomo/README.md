# SGODOT-284 / q(171) · Tomo charcoal hair increment

刘备 · 2026-10-14 · PR #407, `feat/284-resident-parts` → `farm-dev`.
Increment from `6475b892`; 上官婉儿's hold comment was confirmed before pushing.
Authority: director assignment and Plane comment `52267da0-e64b-4704-909b-c0b838a4ad2a`,
following 不知火舞's decision `ecdc10b6-244f-46d0-a389-389974f355d2`.

`hairhat0_npc_tomo` is a hairHat socket part, restricted to NPCs. The source
`SM_hairHat0.fbx` is byte-identical to hairhat0, including its filename, node
names, hierarchy, transforms, axes, units and geometry. Only the texture changes:
all hair luminances map monotonically through #261E1A / #3B302A / #5A4A40,
retaining baked strands and alpha. Inspection found no non-hair atlas regions.
Source PNG is 1024²; runtime remains 512² with original mipmap/compression settings.
The unchanged FBX retains its legacy texture reference; the extraction recipe
explicitly binds `T_tomo_hairHat_D.png` to the runtime part. Material floats match
hairhat0. Imported geometry/UVs/normals are exact; 1468 triangles, one mesh/surface.

The final look is `hairhat0_npc_tomo + glass0 + cloth0 + shoes2 + messengerbag3`,
under `res_tomo`. Runtime resident tables and production portraits are unchanged;
the director and 苏烈 integrate those separately after review.

## Actual review images

- [npc_lineup front](npc-lineup-front.png), [three-quarter](npc-lineup-three-quarter.png),
  [original combined capture](npc-lineup-both.png).
- [Full-body card, 300×660](tomo_card.jpg).
- [Stamp sheet: 32×40 above, 96×120 below](stamps.png).
- Exact stamp crops: [32×40](tomo_stamp_32x40.png), [96×120](tomo_stamp_96x120.png).

Godot 4.7.2 / Vulkan Mobile on Deck AMD Custom GPU 0405 (RADV VANGOGH).
The supplied baker ran unchanged with a window; it is not committed. The card
and postage sheet are its unedited outputs; separate stamp PNGs are exact crops.
The lineup uses the existing renderer, a Tomo-only fixture, frozen idle and the
same full-body framing as the first delivery. [Script provenance](review-script-provenance.json)
and [portrait crop metadata](portrait_crops.json) are retained. This is desktop
art evidence, not phone performance or integrated UI acceptance.

## Validation

- [Extraction](extract.log): `追加完成: 1 部件, 0 错误`; original three IDs skipped.
- [Preservation](preservation.json): manifest appends exactly one ID (41 → 42),
  original entries/text prefix exact; 408 existing asset/pipeline/avatar/NPC files
  byte-identical, including the first three delivered parts.
- [Required tests](tests.xml): **38/38 pass**, zero failures/errors/skips/orphans.
  `tests/catalog`, `tests/pipeline`, `tests/assembly/test_socket_placement.gd`;
  socket placement iterates NPC hairHat entries including Tomo.
- [Import audit](godot-validation.json): **37/37 pass** across all four parts,
  including Tomo's imported frames, exact FBX/mesh data and player-catalog exclusion.
- [Texture audit](texture-validation.json): original luminance min/median/max,
  palette, unchanged alpha and 68 output RGB levels.
- [Rebuild](reproducibility.json): consecutive FBX/PNG results byte-identical.
- [Combined validation](validation.json) records the complete outfit, sizes,
  image hashes and environment.

The Godot runner emits its existing remote-debugger port-0 startup diagnostic;
all eight suites complete successfully. Optional absent Xbot fixture and negative
catalog tests retain their existing warnings. The source FBX's legacy image path
is unresolved during its import, while the extracted runtime material correctly
uses the new PNG, verified both through the imported part and actual captures.

## Reproduce

From repository root, with Python Pillow/NumPy and the existing Godot toolchain:

```sh
python3 tools/art/recolor_tomo_284.py
python3 tools/art/prepare_resident_parts_review.py --tomo
godot --headless --path . --editor --import
godot --headless --path . --script res://tools/pipeline/extract_parts.gd -- res://assets/avatar/source/recipes_284.json --append
godot --headless --path . --editor --import
godot --headless --path . --script res://tools/art/verify_resident_parts_284.gd
GODOT_BIN="$(command -v godot)" ./addons/gdUnit4/runtest.sh -a res://tests/catalog -a res://tests/pipeline -a res://tests/assembly/test_socket_placement.gd
godot --path . --script res://output/resident-parts-284-tomo/npc_lineup_284.gd -- --out=output/resident-parts-284-tomo/npc-lineup.png
godot --path . --script res://tools/art/bake_resident_portraits.gd -- --looks=output/resident-parts-284-tomo/looks-new.json --ids=res_tomo --out=output/resident-parts-284-tomo/portraits
```

Already registered IDs are skipped. Preparation creates a local isolated QA
override and copies the supplied baker from `~/incoming/resident-parts/`.
Remove that temporary override, baker and generated UID after review; do not
commit them. See [source instructions](../../../../assets/avatar/source/README_284.md).

Five incremental attachments (front, three-quarter, card, stamp sheet, validation)
are delivered to SGODOT-284 as 刘备, with uploader identity and downloaded SHA-256
verified: [delivery receipt](delivery-verification.json).
Cross-review: 后裔; technical: 上官婉儿; visual: 不知火舞; merge after user approval.
