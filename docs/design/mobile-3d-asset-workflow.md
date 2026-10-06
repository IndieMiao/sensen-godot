# Reference-led mobile 3D asset workflow

Use this guide when creating or refining rooms, props and small environments in Blender for this Godot project. It captures the practices and failures from the **Basic Room**, whose asset quality the user accepted on 2026-10-06. Follow the current user brief and gameplay baseline first; this guide describes production methods, not new gameplay rules or permission to release a build.

The working example is the [Basic Room implementation](basic-room-2026-10-06/README.md). Its [reference/runtime comparison](basic-room-2026-10-06/comparison.png), [orthographic views](basic-room-2026-10-06/orthographic-sheet.png) and [verification summary](basic-room-2026-10-06/verification-summary.json) are committed so another agent can inspect them without access to the original workstation's `output/` directory. Detailed results and limitations are in the [QA report](../qa/basic-room-2026-10-06.md).

## 1. Establish the reference and the working environment

Read the current design indexes and relevant gameplay sections before choosing scale, movement, camera or interaction behavior. Retrieve the **actual design image**, record its file/node identity, and save a local copy. A layer name, Figma tree screenshot or successful login does not establish that the artwork itself was inspected.

For Basic Room, the source is Figma file `OMLTC3yw3u2WDjOZhLnhaR`, node `545:2968`, `Scene_design → Basic Room-1 1`. The retained export is 2561 × 2561. Inspect the full image before subdividing the task into props.

Inspect installed tools rather than assuming historical workstation notes still describe the machine. Record the Blender and Godot versions, matching export templates, SDK/JDK locations, available emulator images, display access and actual rendering backend. This round used Blender 5.2 and Godot 4.7.2. The SDK image mentioned in an older note was unavailable; the successful run used API 35. Confirm an installation command has finished successfully before using its outputs.

### Decide whether another concept image is useful

One perspective reference was sufficient for this room: the silhouettes, furniture arrangement, color families and visible construction were clear. The unseen depth, backs and dimensions were modeled as reasonable inferences and documented as such.

Use additional image generation only when a particular unresolved design question needs it, such as an elaborate prop's hidden mechanism or decoration. Generated front/side views can disagree with each other and alter the approved design. They are design proposals, not measured geometry. Do not automatically spend generation budget on a complete three-view set for simple furniture.

Once the model exists, render orthographic views **from that model** to check proportions and alignment. This avoids inventing a second design authority. Basic Room did not use image-2; its front, side and top views come from Blender.

## 2. Match composition before adding detail

Start with a short visual inventory: architectural envelope, large furniture, openings, repeated objects, small props, materials, light direction and cast shadows. Lock the camera projection, yaw, pitch, target and framing early. Compare the whole room at the same presentation scale throughout the work.

Use this order:

1. Floor, wall heights, open sides and camera composition.
2. Doors, windows, hearth and large furniture placement.
3. Character scale, walking clearance and collision volumes.
4. Main color families, material response and broad lighting.
5. Rounded edges, planks, handles, cloth folds, plants and small decorations.

Spend geometry on readable silhouettes and important structural details. A window opening should be a real opening if sunlight is meant to pass through it. A sink should have a cavity and lining, not merely a white rim over a solid countertop. Check the room with the character before finalizing narrow gaps.

Avoid judging the result only through close-ups or a flattering crop. Show the complete room as well as details. Reference comparison images support visual review; they do not establish a numerical fidelity score when the geometry and camera are not registered.

## 3. Keep an editable model and reusable runtime parts

Maintain three complementary deliverables:

| Deliverable | Purpose | Basic Room example |
|---|---|---|
| Named Blender objects and collections | Edit individual construction details | `tools/art/source/basic_room/basic_room.blend` |
| Deterministic generator | Reproduce geometry, materials, bake and export | `tools/art/build_basic_room.py` |
| Runtime kit and placement manifest | Reuse modules and assemble a room cheaply | `assets/rooms/basic_room/*.glb`, `layout.json` |

Use meaningful module boundaries: a chair, table, kettle, shelf or window assembly should have its own pivot and asset. Keep finer construction pieces named inside the Blender source. Merge runtime meshes **within each module**, rather than exporting hundreds of source objects or flattening the entire room into one inseparable mesh. Repeated chairs should instance the same exported asset.

Choose a coordinate contract and state it explicitly. Basic Room modeling helpers accept Godot metres with Y up and front +Z, mapping to Blender as `(x, -z, y)`. Export glTF with Y up. Store placement and rotation in the manifest; export each module about its own floor or mounting pivot. Test an independently placed instance so the original room transform cannot conceal a pivot error.

The full Basic Room generator recreates and overwrites its source model. If making manual Blender edits, preserve them deliberately: update the generator or keep the edited `.blend` and use the bake/export-only path with the expected collection names. A script and a `.blend` that silently diverge are not a reproducible handoff.

### Geometry lessons from this build

- Recalculate custom-mesh face normals before applying booleans. An apparently valid arched cutter with inward normals produced a filled window and fireplace.
- Update Blender's evaluated transforms before boolean operations. Apply modifiers on export copies, preserving editable source objects.
- Use bevels and weighted/custom normals together. More polygons alone did not remove faceted-looking corners; preserving the intended shading normals improved the result.
- When joining, splitting and returning meshes to local pivots, copy UVs and transform corner normals correctly. Check the exported model in Godot, not only the Blender source.
- A single scenery card can be back-facing after normal recalculation. Give an intentional thin card the appropriate winding or a deliberate two-sided material; do not make every material two-sided to hide mesh errors.
- Disable shadow casting on a background card behind a window. Otherwise the card can block the very sunlight the real opening was built to admit.

## 4. Bake expensive surface detail, retain useful runtime lighting

Basic Room uses one shared 2048 × 2048 atlas for base color, procedural wood/plaster detail and static contact AO. The pipeline bakes an emission output containing `base color × softened AO`; it does **not** bake the final sun-lit beauty render into the albedo.

The tested pipeline is:

```text
Editable named objects
    → evaluated temporary mesh copies
    → per-face module IDs retained through joining
    → one packed atlas UV layer
    → base-color + contact-AO bake
    → split by module ID; restore local pivots and corner normals
    → GLBs + one external atlas + placement/collision JSON
    → shared materials assigned by the Godot room assembler
```

Keep a source texture's UV layer separate from the new bake UV layer. The painted window view uses its original UVs to sample the source image while the result is written into `RoomAtlas`. Explicitly select the active/render UV layer for baking and export; otherwise a model can sample the wrong part of the shared texture.

Pack islands with enough margin for the final resolution and mip chain. This implementation uses a 2048 atlas, Smart UV packing and an 8px bake margin; these are working settings for this kit, not universal values. Inspect thin trim, cloth edges and distant views for bleeding.

Do not embed the same atlas in every GLB. Basic Room exports geometry without embedded images and applies a shared Godot material in `basic_room_art.gd`. A consumer loading a raw GLB separately must also bind that atlas. Mipmaps and VRAM compression must be configured in the **actual target project**, then reimported; copying a PNG alone does not preserve import settings.

### Know what the AO is tied to

The current atlas includes contact AO from the assembled room. Large layout changes can leave old contact shading on the floor or walls, so rebake after moving major furniture. If a future kit must support arbitrary rearrangement without rebaking, bake module-local AO and keep room contact shadows separate. Reusable geometry and layout-independent baked lighting are different requirements.

Runtime lighting in this example uses one shadowed directional light, warm ambient color and a small unshadowed hearth light. Fire geometry varies slightly over time. No runtime SSAO, real-time GI, SSR, particle system or depth-of-field pass was needed. This is a suitable starting point for a small stylized room; choose features according to the new scene's visual needs and measured cost.

## 5. Budget more than triangles

Record unique mesh cost, instanced scene cost, surfaces/materials, textures, shadow passes and runtime rendering statistics separately. The accepted Basic Room is a reference point, **not a new global performance limit**:

| Metric | Recorded value | Interpretation |
|---|---:|---|
| Reusable GLBs / placed instances | 22 / 23 | The second chair is reused |
| Unique / placed room triangles | 47,256 / 48,552 | Excludes avatar and repeated shadow rendering |
| Static surfaces | 23 | Not the complete frame's draw count |
| Shared atlas | 2048 × 2048 | Mipmapped and VRAM-compressed at import |
| GLBs combined | 1,712,708 bytes | File size, not total GPU residency |
| Atlas PNG | 3,397,744 bytes | Compressed source file size |
| Final Android frame draw calls, median | 59 | Includes the full benchmark |

A small PNG can expand substantially in memory. Engine-reported rendering memory also includes render targets, MSAA, shadows, character resources and caches. Reducing mesh count will not necessarily fix a pixel-bound software renderer. Measure before changing the approved art.

Report renderer, backend, resolution, sample count and whether the device is physical. This room's desktop run had a median 60 FPS; the correctly rendered software Android emulator had a median 7 FPS. Neither is a phone GPU measurement. A faster image with missing geometry is a failed render, not an optimization.

## 6. Separate the reusable room from the benchmark

[The room scene](../../scenes/basic_room/basic_room_art.tscn) contains artwork and collisions. [The benchmark](../../tools/dev/basic_room/basic_room.tscn) adds lighting, the existing avatar, movement, camera controls, UI and observation hooks. Do not make reusable art depend on accounts, networking, inventory or a test runner.

Use an isolated Godot project, package name and user-data directory for validation. The Basic Room project enables only the required Avatar autoload and a fixed fixture outfit. It does not load the player's saved outfit or change the production entry scene/export preset.

Keep collision volumes simple and grounded in the intended movement. Check furniture blocking, diagonal sliding, wall/edge containment and spawn clearance. Touch input should move relative to the camera, stop on release/focus loss, and avoid moving the avatar during a pinch. Account for device safe areas when placing UI.

Protect the repository's global class scan: keep `output/.gdignore`, and keep the Blender source directory excluded from automatic runtime import. Generated QA projects under `output/` otherwise introduce duplicate global scripts into the parent project.

## 7. Validate progressively and diagnose from evidence

Run parsing/import checks first, then actual rendered desktop checks, then a small Android smoke check **before** a long test/recording pass. A useful smoke check shows the complete room and complete character, verifies animation movement, and exercises one drag, one symmetric pinch and one button.

Use headless mode for suitable structural or resource checks. Animation systems driven by `VisibleOnScreenNotifier3D` need a real rendered viewport for visibility-dependent tests. In this case a headless test paused the avatar through the existing `RigActivity`; the same test passed with rendering. Do not weaken shared animation throttling merely to make a headless test pass.

For Android, use real taps, held drags and two-pointer MotionEvents for behavior claims. Direct fixture commands may reset the initial position or camera, but those commands do not prove touch handling. Read control bounds from the running UI and verify observations belong to the current PID. Write commands/state atomically and wait for a command-sequence acknowledgment before injecting the next gesture.

### Symptom-driven diagnosis

| Observed failure | Evidence and effective action in this round | Limit of the lesson |
|---|---|---|
| Black output; Vulkan present error 5 | The failure path went through Android Swappy. Disabling `display/window/frame_pacing/android/enable_frame_pacing` in the isolated QA project restored presentation | A Godot 4.7.2 / emulator workaround; do not disable frame pacing globally without reproduction |
| Room and rigid hair visible, skinned body absent | Host GPU translation produced an incomplete image and later hung. Software Vulkan rendered the whole avatar | Verify pixels before trusting FPS; do not rewrite working shared avatar code to mask an emulator defect |
| Touch down/up received, symmetric pinch does nothing | With native Android scale gestures disabled, centered pinches did not deliver the expected drag events. Enabling native gestures and handling `InputEventMagnifyGesture` fixed the real-input test | Support native and raw gesture paths and deduplicate them; do not count a direct camera command as a pinch test |
| UI buttons need touch-to-mouse behavior | Enable mouse emulation for ordinary Godot buttons; the joystick ignores emulated mouse input on a touchscreen | Prevent duplicate movement/actions rather than disabling all GUI touch behavior |
| Intermittent JSON parse/reset failures | Replace temporary command/state files atomically and acknowledge the applied sequence | A stale observer file or delayed fixture reset is not evidence of a gameplay failure |
| Window, stove or sink looks filled | Inspect normals, real apertures, countertop cutout and inner lining in both renderers | A convincing outer silhouette can hide wrong interior geometry |
| High-resolution desktop screenshot is clipped | The window manager capped the window at the display size. Capture the same world with a sized SubViewport | Check the returned image dimensions, not just the requested CLI resolution |

Once a signature points to a common engine layer, inspect that layer and vary one setting. This round spent unnecessary time swapping image/backend combinations before isolating Swappy. Establish a small failure reproduction early, retain the failed evidence, and avoid changing many art and environment variables together.

Use a private ADB server and the repository's Android test runner. Set Godot's `export/android/shutdown_adb_on_exit=false`. Discover current devices and available ports; the case's port numbers are not reservations for another agent. Stop the test app after the scenario, preserve the emulator and its data, and remove only the temporary fixtures created by that task.

## 8. Capture a review package that can be trusted

Provide a whole-scene image, a clearly labeled reference/runtime comparison, useful detail or orthographic views, and a short movement video. Include the character in at least one runtime image. Visually inspect the full body: an animation timer and successful assembly callback did not catch the missing-body emulator failure.

Dismiss native fullscreen/resize education and check again after resizing or relaunching. Inspect the beginning, middle and end of recordings for dialogs, clipping, black frames and framing. A comparison crop must be identified and retain the promised scene content. Do not accelerate software-emulator footage and present it as real-time device performance.

Desktop footage and Android footage should be labeled separately. Keep camera/lighting consistent where comparing platforms. If the window manager adds decoration, capture the real client area or crop it deliberately and record that fact.

Verify the installed APK by reading it back and comparing it with the tested artifact. Inspect packaged models/textures as well as the local source directory. Where external delivery is authorized, verify the recipient, read back the messages, download the attachments and compare the delivered content. Existing session authorization remains valid; do not create an extra approval round for an already authorized self-review delivery. This case's chat authorization does not grant future or other-recipient delivery permission.

## 9. Reuse the working example

From the repository root, with the matching Godot installation available:

```sh
tools/dev/open_basic_room.sh
```

The launcher stages the isolated project, configures the atlas import and opens the benchmark. The first use may import the parent project to discover existing avatar dependencies. For a remote desktop session, supply that machine's actual display environment; do not copy an old Xauthority path.

Useful source entry points:

| Task | File |
|---|---|
| Modeling, named modules, normals, global atlas and local-pivot export | [build_basic_room.py](../../tools/art/build_basic_room.py) |
| Actual model orthographic renders | [render_basic_room_views.py](../../tools/art/render_basic_room_views.py) |
| Shared materials, placement and simple collisions | [basic_room_art.gd](../../scenes/basic_room/basic_room_art.gd) |
| Isolated project/export setup | [prepare_basic_room.py](../../tools/dev/basic_room/prepare_basic_room.py) |
| Atlas compression and mip settings | [configure_imports.gd](../../tools/dev/basic_room/configure_imports.gd) |
| Avatar, movement, camera and observation protocol | [basic_room.gd](../../tools/dev/basic_room/basic_room.gd) |
| Raw/native touch gesture handling | [room_controls.gd](../../tools/dev/basic_room/room_controls.gd) |
| Rendered desktop behavioral checks | [test_basic_room.gd](../../tools/dev/basic_room/test_basic_room.gd) |
| Android input checks and recording | [android_qa.py](../../tools/dev/basic_room/android_qa.py), [RoomTouch.java](../../tools/dev/basic_room/RoomTouch.java) |

To rebuild assets, run Blender with an **absolute** script path, particularly with Flatpak. The generator supports `--geometry-only`, `--bake-only` and `--render-only` after `--`. Running the full generator is a source rebuild, not a safe way to preserve unrecorded manual edits.

The Android harness requires Pillow/NumPy and a compiled/pushed `RoomTouch` dex, in addition to the installed isolated APK. The case README includes the concrete preparation commands. Do not assume ignored `output/` artifacts exist in another checkout.

## 10. Handoff for the next agent

Commit editable sources, the generator, exported assets, the placement/collision contract, required import configuration, reusable scene, benchmark, instructions and a small review/evidence snapshot. Keep SDK downloads, credentials, caches, APKs and bulk recordings out of the source commit unless explicitly requested.

State what the user accepted, what was tested, the hardware/backend and the remaining differences. Art acceptance does not establish true-device performance, a gameplay release or permission to alter saves. Preserve unrelated local edits when committing, fetch before pushing and verify the remote commit afterward.

For a new asset, the useful completion record is: reference identity; editable source and rebuild path; module boundaries and units; geometry/material/texture budgets; actual Godot captures; relevant rendered/input checks; actual mobile or emulator conditions; visual differences; and delivery status. Adapt the evidence to the task rather than copying Basic Room's numbers as targets.
