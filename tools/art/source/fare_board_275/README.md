# SGODOT-275 Fare Board editable source

Authority: [spec-v1.1.md](spec-v1.1.md), commissioned by 上官婉儿 and reviewed
by 不知火舞. [reference.png](reference.png) supplies shape/color direction;
dimensions and the seven rows follow the specification. Author: 刘备.

`fare_board.blend` retains named frame, recessed board, thin cornice, seven
blank bars, seven colored dots and two brass fixing heads. The `fare_board`
collection also contains `board_center` and `mark`. Geometry helpers accept
Godot metres (Y up, +Z front) and convert to Blender `(x,-z,y)`.

From the repository root, with Blender 5.2.2:

```sh
blender --background --factory-startup --python "$PWD/tools/art/build_fare_board.py"
```

This rebuilds the named source and `assets/rooms/post_office/fare_board.glb`.
The source contains six editable atlas-swatch materials; export merges them
into one `RoomKit_SharedAtlas` surface, with one UV channel. Every face samples
one existing atlas pixel centre, preventing texture grain or island bleeding.
The atlas remains external, as in `scene_room_pipeline.py`. Bind the room's
actual shared material after instantiating the GLB in Godot.

[atlas-swatches.json](atlas-swatches.json) pins source asset hashes, UV sample
points, atlas hash, RGB values and checked 7×7 neighborhoods. It is a build
input, not regenerated or automatically resampled. Source Blender materials
reference the existing atlas using a relative path. No new texture is included.

[asset-contract.json](asset-contract.json) records bounds, row lengths, sockets
and approved placement. Pivot is back centre at zero; full size is
0.90 × 0.65 × 0.07 m. `board_center=(0,0,0.05)`, `mark=(0,0.45,0)`;
the latter follows v1.1's explicit local coordinate. The runtime GLB has 674
triangles, one mesh, one surface and identity node bases.

See [review and validation](../../../../docs/design/fare-board-275-2026-10-14/README.md)
for commands, the three actual Godot captures, collision evidence, color-source
choices and integration instructions. This generator does not modify the
room atlas, room layout or other assets.
