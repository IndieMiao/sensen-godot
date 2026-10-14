# SGODOT-284 / q(171) · Granny Wu and Ivo NPC parts

刘备 · 2026-10-14. Specification and 不知火舞's final decisions:
[spec-v1.1.md](../../../tools/art/source/resident_parts_284/spec-v1.1.md).
The design reference supplies color/shape direction; existing part scale and
FBX frames remain authoritative. Review base: `farm-dev`, `a8e0b548`.

| New ID | Base | Edit | Triangles |
|---|---|---|---|
| hairhat80_npc_granny_wu | hairhat80_npc_ama | Silver hair, warm red pin; FBX byte-identical | 764 |
| hairhat_npc_ivo | hairhat51 | Rounded mustard helmet, brass headlamp, retained/shortened grey hair | 1423 |
| mask16_npc_ivo | mask16_npc_kai | Grey jaw beard; one-third vertical extent | 320 |

All three are static `SM_` socket parts, one mesh and one surface each. Original
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
Its ivory lamp face has `emission_strength=0`, with no light or glow object.

Granny Wu's original luminance curves become silver #E4E0D8 / shade #B9B4AC and
red #A63830 / shade #7A2A25, preserving hair shading. Ivo's beard uses #A9A49C /
#7F7A73. The helmet atlas uses #C99A3A / #9E7628, brass #9B7B46, lens #F3E6C4,
and grey hair #B8B3AB / #8C877F. Each part has one PNG. Source sizes match their
bases (512², 2048², 512²); inherited import settings cap all runtime textures at
512², with mipmaps and VRAM compression.

**Optional clothing skipped:** cloth42's atlas includes a monster face, stripe
pattern and multicolor modeled decorations. It is not a simple plain-workwear
recolor. Use the explicitly approved original `cloth42` fallback this round;
no `cloth42_npc_ivo` ID is registered. Final review looks are:

- Granny Wu: `hairhat80_npc_granny_wu + cloth11 + shoes3`, no glasses.
- Ivo: `hairhat_npc_ivo + mask16_npc_ivo + cloth42 + shoes4`.

## Rebuild and append

Run from the repository root. Texture generation requires Python with Pillow
and NumPy; geometry generation uses Blender 5.2.2 LTS's bundled FBX parser/writer.

```sh
python3 tools/art/recolor_resident_parts_284.py
blender --background --factory-startup --python "$PWD/tools/art/build_resident_parts_284.py"
godot --headless --path . --editor --import
godot --headless --path . --script res://tools/pipeline/extract_parts.gd -- res://assets/avatar/source/recipes_284.json --append
```

On the original base, output is `追加完成: 3 部件, 0 错误` and the manifest changes
only by the three entries at its end (38 → 41). In this delivered tree, those IDs
already exist, so `--append` correctly skips them. To regenerate changed new
parts, first remove only these three new entries; keep all prior entries intact,
then append again. Never run extraction without `--append`.
`npc_only.json` appends the same three IDs, excluding them from player outfits.
The existing runtime NPC table is unchanged; 苏烈 registers the looks after merge.

## Review and checks

```sh
python3 tools/art/prepare_resident_parts_review.py --bake-script "$HOME/incoming/resident-parts/bake_resident_portraits.gd"
godot --headless --path . --editor --import
godot --headless --path . --script res://tools/art/verify_resident_parts_284.gd
GODOT_BIN="$(command -v godot)" ./addons/gdUnit4/runtest.sh -a res://tests/catalog -a res://tests/pipeline -a res://tests/assembly/test_socket_placement.gd
godot --path . --script res://output/resident-parts-284/npc_lineup_284.gd -- --out=output/resident-parts-284/npc-lineup.png
godot --path . --script res://tools/art/bake_resident_portraits.gd -- --looks=output/resident-parts-284/looks-new.json --ids=res_granny_wu,res_ivo --out=output/resident-parts-284/portraits
```

Use an active display for tests and captures. Preparation creates an uncommitted
`override.cfg` with isolated `SensenResident284QA` data and a localhost:9 network
endpoint, plus a local copy of the supplied baker. **Do not commit the baker, its
UID or override.cfg**; it is owned by the separate portrait integration. The
lineup fixture reuses `npc_lineup.gd` with two temporary resident looks, a frozen
idle frame and adjusted camera distance/target to show complete feet. It does
not edit `outpost_npcs.json` or the production lineup tool.

[Review images, test results and delivery receipt](../../../docs/design/resident-parts-284-2026-10-14/README.md).
Cross-review: 后裔. Technical: 上官婉儿. Visual: 不知火舞. Merge after user approval.
