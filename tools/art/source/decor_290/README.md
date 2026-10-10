# SGODOT-290 editable decorations

Author: 刘备. Brief: 上官婉儿, 2026-10-10; visual direction: 不知火舞.
The accepted brief is retained as [spec-v1.1.md](spec-v1.1.md). Reference image:
Plane SGODOT-290, comments `f84c9bac` and `b491b80c`; `decor_sheet_v1.png`.
The concept supplies silhouettes and colour families; measurements follow the brief.

Rebuild from the repository root with Blender 5.2:

```sh
blender --background --factory-startup --python "$PWD/tools/art/build_decor_assets.py"
```

This overwrites only this source file, the eleven `deco_*.glb` exports and their
manifest entries. Existing farm kit entries and assets are retained. Each
collection is a decoration; components, leaves, petals and sockets have editable
names. Source collections are laid out for inspection after export. Their
`source_display_offset_blender` property records that display-only translation.
The runtime GLBs are exported at the local floor/axle origin before this layout.
Update the generator when making design changes: rerunning it replaces manual
`.blend` edits. The `.gdignore` keeps editable sources out of runtime imports.

The helpers take Godot `(x, y, z)` metres and map to Blender `(x, -z, y)`.
Evaluated export copies receive bevels and weighted normals, then join into one
mesh and one material. Palette colours become linear opaque vertex colours.
No images, textures, UVs, noise, grain or continuous AO are exported. Fixed
triangle diagonals and sorted opaque index triples make repeated GLB builds
byte-identical; triangle winding and normals are retained.

The neutral vertex-colour material inside each GLB is only a standalone preview
fallback. Runtime instances use the existing `FarmArt.material()` singleton,
including `vertex_color_is_srgb = false`, roughness 0.9 and specular 0.18.
No new game shader, material implementation or integration code is introduced.

See [delivery and integration notes](../../../../docs/design/decor-290-2026-10-10/README.md)
for dimensions, sockets, clearances and actual Godot captures.
