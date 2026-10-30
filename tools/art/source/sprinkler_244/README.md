# SGODOT-244 Editable Sprinkler

Author: 黄忠. Dimensions follow the supplied v1.1 specification; the reference image only guides silhouette and palette.

Current model revision v1.2 follows `revision-v1.2.md` including Plane comment `217ba43a`: head lowered to 0.42 m, total height 0.525 m, riser taper 0.13 to 0.11 m with a greener palette. The head fills the 0.40 m envelope; its 0.10 m cap is rounder/taller. There are 798 triangles. Previous reference, specification and revision notes remain archived unchanged.

`sprinkler_244.blend` retains eight named parts in `Sprinkler_base` and `Sprinkler_head`. The base empty is at the bed origin, and the head empty and spray marker are at Godot `(0, 0.42, 0)` (Blender Z up). The source uses Godot `(x, y, z)` mapped to Blender `(x, -z, y)`.

Run `tools/art/build_sprinkler.py` inside Blender using its absolute path. Evaluated export copies merge into two vertex-painted meshes. The source parts remain editable. `source_parts.json` records part triangle counts; `tools/art/verify_sprinkler_source.py` compares actual source/export vertices. Full evidence and commands are in `docs/design/sprinkler-244-2026-10-30/README.md`.

The existing plot is an earthen bed, without a wooden frame. The game review compares the real plot rim and a separately measured farm storage wood sample; neither original asset is modified.
