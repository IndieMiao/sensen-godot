# Editable resident parts · SGODOT-284 / q(171)

[Specification](spec-v1.1.md) and [reference](reference.png) were supplied by
上官婉儿; the specification includes 不知火舞's final clothing/no-glasses decisions.
The reference's glasses and brown outfit are not additional modeling requests.

`ivo-helmet.blend` retains the source `hairHat` mesh and `Head_M` armature frame.
Named vertex groups identify the derived short hair, dome, brim, band, brass
housing and ivory lens; FBX node names remain original. `ivo-short-beard.blend`
retains `mask` and its original armature, with the shortened grey beard.
Textures use relative paths to the delivered avatar source directories.
Granny Wu's editable geometry is the byte-identical original `SM_hairHat80.fbx`.
Tomo also retains the byte-identical original `SM_hairHat0.fbx`; his texture-only
increment needs no Blender geometry export. `recolor_tomo_284.py` reproduces
the warm dark brown shading, with `tomo-texture-validation.json` recording its
palette, source luminance knots, alpha preservation and source hashes.

The later clothing correction (Plane comment `87e87ff2-ddef-4f65-b9bf-f2c309acda69`)
replaces Ivo's cloth42 with `cloth1_npc_ivo`: canvas tan shirt and charcoal shorts,
with the original light-grey details and buttons preserved. The original
`SK_dt_skin01.fbx` is byte-identical; no Blender export is needed for this
texture-only part. `recolor_ivo_cloth_284.py --runtime-root <runtime-checkout>`
reproduces the PNG; `ivo-cloth-texture-validation.json` records palette curves,
region masks and preservation. Granny Wu's accepted hair remains unchanged.
[Latest clothing review and commands](../../../../docs/design/resident-parts-284-2026-10-14/ivo-cloth/README.md).

`geometry-validation.json` records exact non-geometry FBX preservation and the
beard's 1/3 vertical extent; `texture-validation.json` records the luminance
curves and unchanged alpha. The generator derives all edits from unchanged base
assets; do not manually edit a blend without transferring the change to it.

[Runtime build and append instructions in #407](https://github.com/IndieMiao/sensen-godot/blob/feat/284-resident-parts/assets/avatar/source/README_284.md).
