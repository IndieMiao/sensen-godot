# SGODOT-244 Editable Sprinkler

Author: 黄忠. Dimensions follow the supplied v1.1 specification; the reference image only guides silhouette and palette.

Current model revision v1.1 also incorporates `revision-v1.1.md`: stronger riser/hub/arms, 0.10 m cap and rounded 0.25 m pad, 778 triangles. The original reference and specification remain archived unchanged.

`sprinkler_244.blend` retains eight named parts in `Sprinkler_base` and `Sprinkler_head`. The base empty is at the bed origin, and the head empty and spray marker are at Godot `(0, 0.55, 0)` (Blender Z up). The source uses Godot `(x, y, z)` mapped to Blender `(x, -z, y)`.

Run `tools/art/build_sprinkler.py` inside Blender using its absolute path. Evaluated export copies merge into two vertex-painted meshes. The source parts remain editable. `source_parts.json` records part triangle counts; `tools/art/verify_sprinkler_source.py` compares actual source/export vertices. Full evidence and commands are in `docs/design/sprinkler-244-2026-10-30/README.md`.

The existing plot is an earthen bed, without a wooden frame. The game review compares the real plot rim and a separately measured farm storage wood sample; neither original asset is modified.
