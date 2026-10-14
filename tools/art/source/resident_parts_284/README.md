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

`geometry-validation.json` records exact non-geometry FBX preservation and the
beard's 1/3 vertical extent; `texture-validation.json` records the luminance
curves and unchanged alpha. The generator derives all edits from unchanged base
assets; do not manually edit a blend without transferring the change to it.

[Build, append, validation and review instructions](../../../../assets/avatar/source/README_284.md).
