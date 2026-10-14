# Notice Board editable source · SGODOT-284

刘备 · specification v1.1 · target after 0.2.6.

`reference.png` is the supplied SGODOT-284 design sheet. `spec-v1.1.md` sets the
actual dimensions and includes 不知火舞's review. The concept's scale and edge
noise are not geometry or materials.

`notice_board.blend` retains named, separate editable post, foot, low rail,
frame, plain cork face, four blank papers, four small round pin heads, two roof
slopes and dark ridge-cap objects, plus `board_center` and `mark` empties.
All parts stay at their actual local positions; the origin is the ground
midpoint between the two posts. Model front is +Z in Godot; helper coordinates
map to Blender `(x,-z,y)` before the Y-up GLB export.

Rebuild from the repository root:

```sh
blender --background --factory-startup --python "$PWD/tools/art/build_notice_board.py"
blender --background --factory-startup --python "$PWD/tools/art/verify_notice_board.py"
```

The standalone generator reuses `build_decor_assets.py` export/modeling helpers
and the existing GLB reader. It only rebuilds `notice_board.glb` and its manifest
entry. It overwrites the generated `.blend`; incorporate manual changes in the
script before rebuilding.

`palette-provenance.json` records exact original vertex-color floats, source
vertex indices and hashes. Colors are copied from existing GLBs, including the
roof green shared with storage/well; no new color adjustment is applied.
The chef sign's actual gold is approximately #E6B954 and is used for the yellow
pin; the yellow paper uses the existing sign #F1CE58 sample. Three other sheets
use sign ivory (two) and chef sign milk (one).

Dimensions: mesh height 1.595 m; board 0.56 × 0.44 × 0.05 m, bottom 0.95 m;
post centres ±0.25 m and feet bounded by X ±0.30 / Z ±0.05 m. Sockets are
`board_center=(0,1.17,0.06)` and `mark=(0,1.75,0)`, both +Z identity basis.
The mark is an empty and does not count toward mesh height. Imported PackedScene
retains both empties. `FarmArt.instance()` extracts only the mesh, so reconstruct
sockets from the manifest when using it.

See the [review, validation and integration record](../../../../docs/design/notice-board-284-2026-10-13/README.md).
