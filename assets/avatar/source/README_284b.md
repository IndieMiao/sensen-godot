# SGODOT-284 · Generated-city keeper hair variants

刘备 · 2026-10-14 · base farm-dev at 6a6ebf14 (includes #407).
Assigned by 上官婉儿, colors selected by 不知火舞. These two parts are for
generated-city keepers only; 苏烈 will place them in world.keeper_looks.
This asset delivery does not edit keeper looks or belong to release 0.2.6.

| ID | Original | Palette: shadow / midtone / highlight | Triangles |
|---|---|---|---:|
| hairhat41_npc_auburn | hairhat41 | #5E2F1C / #8A4A2E / #B06A45 | 2312 |
| hairhat43_npc_black | hairhat43 | #161312 / #2A2624 / #4A4440 | 1156 |

Both are hairHat socket parts, with one mesh/surface and the original tier and
offset. Original FBX filenames, bytes, node names, hierarchy, transforms, axes
and units are unchanged. The recolored PNGs have new filenames. Source textures
remain 1024² and runtime remains 512² with each base's original import settings.
The FBX retains its legacy texture reference; the recipe explicitly binds the
new PNG in the runtime scene.

Recoloring maps original hair luminance monotonically through the specified
three colors, preserving baked strands and shade variation without pure black.
The inspected atlas has distinct hair/accessory color families. For hairhat41,
the dark brown hair is selected by R < 128 and R-G < 20; ochre and pale pink-white
accessories stay byte-identical. For hairhat43, yellow hair is selected by
G-B > 30; all pink accessory pixels remain byte-identical. Alpha is unchanged.
The masks cover 69.05% and 96.10% of their respective source images.

Material floats are copied from each actual original runtime scene:

| Base | emission_strength | smoothness | ao_strength | diffuse_strength | rim_strength |
|---|---:|---:|---:|---:|---:|
| hairhat41 | 0.7 | 0.1 | 0.1 | 1.0 | 0.0 |
| hairhat43 | 0.3 | 0.1 | 0.1 | 1.0 | 0.0 |

## Runtime pipeline

The separate recipes_284b.json contains only these two variants. Do not reuse
or modify recipes_284.json. Following [README_229.md](README_229.md) and
[README_284.md](README_284.md), from the runtime checkout:

~~~sh
godot --headless --path . --editor --import
godot --headless --path . --script res://tools/pipeline/extract_parts.gd -- res://assets/avatar/source/recipes_284b.json --append
godot --headless --path . --editor --import
GODOT_BIN="$(command -v godot)" ./addons/gdUnit4/runtest.sh -a res://tests/catalog -a res://tests/pipeline -a res://tests/assembly/test_socket_placement.gd
~~~

The first extraction reports “追加完成: 2 部件, 0 错误”. The original 43 manifest
entries and their text prefix remain exact; two entries are appended (43 → 45).
Already registered IDs are skipped. To regenerate one part, remove only that
part's manifest entry before --append. Never omit --append.
Both IDs are appended to npc_only.json; the player outfit pool excludes them.

## Art sources and review: wp-3d-scene

The farm-dev PR contains only assets/avatar/**. Recoloring/preparation/audit
scripts, screenshots and validation belong to the companion wp-3d-scene PR:

- [Review images and validation](https://github.com/IndieMiao/sensen-godot/blob/wp-3d-scene/docs/design/keeper-hair-284-2026-10-14/README.md).
- [Source notes and texture audit](https://github.com/IndieMiao/sensen-godot/blob/wp-3d-scene/tools/art/source/keeper_hair_284/README.md).
- Tools: recolor_keeper_hair_284.py, prepare_keeper_hair_review_284.py and
  verify_keeper_hair_284.gd under tools/art in wp-3d-scene.

No Blender geometry export is needed: the original FBXs are the editable
geometry sources, and the deterministic Python script reproduces the PNGs.
The existing baker in wp-3d-scene is copied unchanged into the isolated runtime
checkout for windowed review only and is not added to this PR.

Review fixtures keeper_auburn / keeper_black wear the new hairHat with cloth1
and shoes1. Runtime keeper content is integrated separately by 苏烈.
Cross-review: 后裔; technical: 上官婉儿; visual: 不知火舞; user approval before merge.
