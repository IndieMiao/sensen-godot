# Standard Room-5 · art review candidate

Plane [SGODOT-172](https://plane.sensenjoy.cn/zili/browse/SGODOT-172), owner Zhao Yun / 赵云. Started 2026-10-07; **In Progress, awaiting user art review**. The user requested sequential overnight production with a Lark message after each scene. This supersedes the parent card's first-scene pause; acceptance remains separate.

Reference: Figma `OMLTC3yw3u2WDjOZhLnhaR`, `Scene_design / Standard Room-5 1`, node [545:2969](https://www.figma.com/design/OMLTC3yw3u2WDjOZhLnhaR/Gensen--US-?node-id=545-2969). [Original node export](reference.png), 3402×2561, retrieved and visually inspected on 2026-10-07.

![Reference and actual Godot render](comparison.png)

The expanded 8m × 6.4m cutaway includes the cream sofa with checked throw and pillows, circular woven rug, bookcase and baskets, stove and sage cooking pot, log niche, real apron-sink cavity, separate four-burner range, two-chair dining area, flowers, apples, cups, plants and boots. Architecture and kitchen source modules are appended read-only from the accepted Basic Room, then rebaked into this scene's own atlas. Basic Room files are unchanged.

## Deliverables and reproduction

- [Editable Blender source](../../../tools/art/source/standard_room_5/standard_room_5.blend): named objects and `KIT_` collections.
- [Scene generator](../../../tools/art/build_standard_room_5.py) and [room pipeline](../../../tools/art/scene_room_pipeline.py).
- [Runtime kit and manifest](../../../assets/rooms/standard_room_5/layout.json), with independent local pivots, reusable chair/cushion instances and box collisions.
- [Reusable art scene](../../../scenes/standard_room_5/standard_room_5_art.tscn): art and collisions only.
- [Godot whole scene](godot.png), [model orthographics](orthographic-sheet.png), [budget, hashes and rendered validation](verification-summary.json).

Coordinates are Godot metres, Y up and front +Z, converted to Blender `(x,-z,y)`. Module placement/yaw is stored separately in `layout.json`. The atlas is base color, procedural material detail and softened contact AO; direct light is supplied at runtime. Major layout edits require rebaking. Raw GLBs need the shared atlas bound by the assembler.

```sh
blender --background --factory-startup --python "$PWD/tools/art/build_standard_room_5.py" -- --views
python3 tools/art/prepare_room_review.py standard_room_5
godot --headless --editor --path output/standard_room_5-2026-10-07/godot-project --import --quit
godot --path output/standard_room_5-2026-10-07/godot-project \
  --script res://tools/art/review_room.gd -- standard_room_5 \
  "$PWD/output/standard_room_5-2026-10-07"
```

The last command requires a working display. The review project is only a capture harness, with no avatar, movement controls, gameplay, accounts or Android export preset. `--geometry-only` skips export. The source generator overwrites its own `.blend`; preserve manual changes deliberately.

## Validation and cost

Blender 5.2.0 LTS, Godot 4.7.2, Vulkan Mobile on AMD Custom GPU 0405 (RADV VANGOGH), 1440×1080 actual rendered capture. All 41 mesh instances load with atlas materials, finite nonempty bounds, 41 surfaces and 15 simple collision shapes. Export and runtime triangle totals agree.

- 39 unique GLBs, 41 placed instances.
- 92,322 unique / 93,726 placed triangles, excluding shadow repeats.
- One 2048² external atlas with mipmaps and VRAM compression; three material variants for ordinary surfaces, scenery and fire.
- Exact geometry/texture byte sizes are in the verification JSON; no physical-phone performance claim.

The first rendered check caught black seams on curved cloth, leaves and thin wicker. A shadow-off control and mesh-import controls did not remove them. Triangulating the evaluated mesh **before** UV packing/baking made the bake and exported surface interpolation agree; extending empty atlas gutters removed edge leakage. The reviewed version retains lighting and shadows. Import configs keep geometry uncompressed and automatic LOD generation disabled for these fine small modules.

## Differences and inferred structure

The reference is one stylized perspective without dimensions. Room depth, furniture backs, joinery and collision sizes are inferred. The kitchen and dining proportions follow the existing Basic Room module scale; the real-time version has simpler plants, less rounded cloth and flatter indirect lighting. The outdoor landscape is the existing painted scenery card, not the exact illustrated garden. Small door-side decoration is simplified. The review images support visual assessment, not pixel-registered fidelity or user acceptance.

This delivery is scene art only. No gameplay/map integration, Android QA, recording, production build, migration or release is included.
