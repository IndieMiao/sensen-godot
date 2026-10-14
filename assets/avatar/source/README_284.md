# SGODOT-284 / q(171) · Granny Wu, Ivo and Tomo NPC parts

刘备 · 2026-10-14. Specification and 不知火舞's final decisions:
[spec-v1.1.md in the wp-3d-scene art branch](https://github.com/IndieMiao/sensen-godot/blob/wp-3d-scene/tools/art/source/resident_parts_284/spec-v1.1.md).
The design reference supplies color/shape direction; existing part scale and
FBX frames remain authoritative. Review base: `farm-dev`, `a8e0b548`.

| New ID | Base | Edit | Triangles |
|---|---|---|---|
| hairhat80_npc_granny_wu | hairhat80_npc_ama | Silver hair, warm red pin; FBX byte-identical | 764 |
| hairhat_npc_ivo | hairhat51 | Rounded mustard helmet, brass headlamp, retained/shortened grey hair | 1423 |
| mask16_npc_ivo | mask16_npc_kai | Grey jaw beard; one-third vertical extent | 320 |
| hairhat0_npc_tomo | hairhat0 | Warm dark brown hair texture; FBX byte-identical | 1468 |
| cloth1_npc_ivo | cloth1 | Canvas tan shirt, charcoal shorts; light details and FBX unchanged | 1629 |

The four head parts are static `SM_` socket parts; `cloth1_npc_ivo` is an `SK_`
cloth mesh with the original 59 skin binds. Every part has one mesh/surface. Original
node names, hierarchy, transforms, axes, units and bone frames are preserved.
The hat and beard generator substitutes **Geometry only** inside the original
binary FBX container, with no scene re-export and no compensating recipe offset.
The FBX encoder canonicalizes FileId/CreationTime; all other non-geometry
metadata and objects compare exactly. Godot independently confirms the original
node paths, bone rests and extracted mesh transforms.

The helmet's dome/brim are fitted 0.08 m lower in mesh coordinates after the
first render exposed a gap above the retained hair. The beard keeps its original
width/depth and topology, scales vertical geometry by 1/3 and fits the jaw by a
2 cm mesh-space lift. Neither adjustment changes any FBX node or socket transform.
The original hairHat runtime maximum is 2784 triangles; the helmet uses 1423.
The hat uses `emission_strength=0.3`, matching the base hairHat material. In
`avatar_toon.gdshader` this is the whole mesh's flat-light floor; the ivory lamp
face has no separate light or glow effect. The 0.3 correction follows 后裔's
cross-review and 上官婉儿's clarification; `smoothness=0.05` is retained.

Granny Wu's original luminance curves become silver #E4E0D8 / shade #B9B4AC and
red #A63830 / shade #7A2A25, preserving hair shading. Ivo's beard uses #A9A49C /
#7F7A73. The helmet atlas uses #C99A3A / #9E7628, brass #9B7B46, lens #F3E6C4,
and grey hair #B8B3AB / #8C877F. Each part has one PNG. Source sizes match their
bases (512², 2048², 512²); inherited import settings cap all runtime textures at
512², with mipmaps and VRAM compression.

Final looks follow 不知火舞's acceptance correction (SGODOT-284 comment
`87e87ff2-ddef-4f65-b9bf-f2c309acda69`):

- Granny Wu: `hairhat80_npc_granny_wu + cloth11 + shoes5`, no glasses.
- Ivo: `hairhat_npc_ivo + mask16_npc_ivo + cloth1_npc_ivo + shoes3`.
- Tomo: `hairhat0_npc_tomo + glass0 + cloth0 + shoes2 + messengerbag3`.

Ivo's shirt uses shadow/mid/highlight #7A5E3E / #9C7A52 / #B8966A; shorts use
#26231F / #3A3632 / #55504A. The original light-grey details and buttons remain
byte-identical. Recoloring preserves source luminance differences and alpha;
the shirt's mostly solid base stays at the prescribed midtone. The 1024² source
uses cloth1's original import settings (512² runtime) and material parameters.
`SK_dt_skin01.fbx`, mesh geometry/UVs/weights and all 59 skin binds are unchanged.
Granny Wu's already accepted hair texture is retained; the optional hair adjustment
was not taken. These review looks do not edit the runtime resident table.

Tomo is the October 14 increment authorized by 上官婉儿 after 不知火舞's review.
The original hairhat0 texture contains only hair. Its complete luminance range
is mapped monotonically through shadow #2E1F16, median #4A3324 and highlight
#6B4C36, preserving strand shading and alpha. No geometry is changed: the
original filename, all FBX bytes, nodes, hierarchy, transforms, axes and units
are retained. Source resolution remains 1024² and runtime remains 512² with
the original mipmap/VRAM compression settings. Shader floats match hairhat0.

## Runtime import and append (farm-dev)

This branch keeps the five source FBX/PNG directories, import settings, extracted
parts/socket scenes/thumbnails, `recipes_284.json`, `parts_manifest.json` and
`npc_only.json`. The pipeline runs from the repository root without art scripts:

```sh
godot --headless --path . --editor --import
godot --headless --path . --script res://tools/pipeline/extract_parts.gd -- res://assets/avatar/source/recipes_284.json --append
```

The recipe appends five entries on the original base (38 → 43). The Ivo clothing
increment appends only one entry to the previous delivery (42 → 43). Already present
IDs are skipped. To regenerate one changed part, remove only that part's manifest
entry, retain every other entry, then run `--append` as documented in
[README_229.md](README_229.md). Never extract without `--append`.
`npc_only.json` excludes all five IDs from player outfits. Runtime NPC looks and
production portraits are integrated separately by 上官婉儿 / 苏烈.

## Art sources and review (在 wp-3d-scene)

按 10-08 美术整合规则，审阅图、验证 JSON、生成/审核脚本和 Blender 源文件在
**wp-3d-scene**，不随运行时 PR #407 进入 farm-dev。合并后的长期材料入口为
[`wp-3d-scene`](https://github.com/IndieMiao/sensen-godot/tree/wp-3d-scene)，
审阅材料从已检查的 `1e8da88e` 原样迁移。

- [Review images, validation and delivery receipts](https://github.com/IndieMiao/sensen-godot/blob/wp-3d-scene/docs/design/resident-parts-284-2026-10-14/README.md).
- [Ivo hat flat-light correction and latest portraits](https://github.com/IndieMiao/sensen-godot/blob/wp-3d-scene/docs/design/resident-parts-284-2026-10-14/ivo-light/README.md).
- [Ivo canvas clothing and revised footwear review](https://github.com/IndieMiao/sensen-godot/blob/wp-3d-scene/docs/design/resident-parts-284-2026-10-14/ivo-cloth/README.md).
- [Tomo's final warm brown images and validation](https://github.com/IndieMiao/sensen-godot/blob/wp-3d-scene/docs/design/resident-parts-284-2026-10-14/tomo/README.md).
- [Named Blender sources and specification](https://github.com/IndieMiao/sensen-godot/tree/wp-3d-scene/tools/art/source/resident_parts_284).
- Art scripts in that branch: `tools/art/build_resident_parts_284.py`,
  `prepare_resident_parts_review.py`, `recolor_resident_parts_284.py`,
  `recolor_tomo_284.py`, `recolor_ivo_cloth_284.py`,
  `verify_resident_parts_284.gd`, and `verify_ivo_cloth_284.gd`.

For regeneration, use an isolated art checkout containing the runtime/source
assets from #407 and the companion art files above. The Python texture scripts
require Pillow/NumPy; geometry generation uses Blender 5.2.2 LTS. Follow the
review instructions in the art branch, including the unchanged, uncommitted
portrait baker and a separate QA user-data directory. Those commands are for
the art checkout, not a bare farm-dev checkout.

## Runtime checks

With an active display and isolated QA user data, run on the runtime branch:

```sh
GODOT_BIN="$(command -v godot)" ./addons/gdUnit4/runtest.sh -a res://tests/catalog -a res://tests/pipeline -a res://tests/assembly/test_socket_placement.gd
```

The socket test includes all NPC hairHat entries, including Tomo. The art-only
import verifier and saved evidence live in wp-3d-scene; the final runtime-head
test result is recorded in PR #407's description.

Cross-review: 后裔. Technical: 上官婉儿. Visual: 不知火舞. Merge after user approval.
