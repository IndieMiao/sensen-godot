# SGODOT-236 — Basic Room particle fire

Based on origin/farm-dev e6520a3b. Basic Room-1 now renders the reviewed shared particle fire instead of fire.glb. The complete assets/rooms/_shared/fx/ directory was initially copied byte-for-byte from **d04ce72e** (178 R2.3 shared FX commit). The interface follow-up below adds `glow_boost` to the fire script and updates its README; fire textures/helpers remain unchanged from 5e5bf6af. No other wp-3d-scene files or runtime dependencies are required. The shared path remains identical for a later art-branch merge.

The public `basic_room_art.gd.fire: Node3D` still exists, named `fire`, at the unchanged layout.fire_position. The emitters use the existing fire asset pivot as their fuel-bed offset, keeping flames inside the original opening. Fire configuration: 16 flames + 4 sparks = **20**, half-extents (0.18, 0.005, 0.035), height 0.42 m; 30 Hz, no collision/shadows, explicit bounds inherited from the approved effect. Particle-local bounds move with their fuel offset.

The existing benchmark HearthGlow is borrowed with light_path; its position, colour, range, attenuation and shadow setting remain unchanged. Existing baseline brightness .72 and a bounded 4.86% flicker retain the old range; the effect is the only flicker writer. Static-fire scale wobble is removed. Hosts create their existing lamp before adding the room and may set `hearth_light_path`; standalone art creates one Basic Room-configured lamp only when no supplied/default lamp exists.

All **48 Basic Room asset files** are byte-identical, including every GLB, atlas/import metadata and the entire layout.json (top-level spawn, camera, placements and collision data). No model rebuild or bake. The old fire.glb remains in the kit for compatibility but is not instantiated for display. See preservation.json and the narrow assembler diff. Consumers: 哪吒 SGODOT-226 and 后裔 SGODOT-227.

## Validation

- `test_basic_room.gd`: **20/20 passed** on rendered Mobile/Vulkan, including all original 16 checks and four fire-integration checks. The public fire root, borrowed lamp identity, removal of the static mesh, total particles and no collision/shadows are checked.
- Android smoke: **9/9 passed**, 5 actual input operations: walking/release, table and boundary collisions, two-pointer pinch without avatar movement, View button; character-on/off pixels verify the complete skinned body. API 37 / 440 dpi required a wider real pinch (25%→92% display width, 1.5s): the first narrow gesture produced touch down/up but no native scale events. Only the QA gesture changed; camera/input/gameplay code did not.
- Installed APK downloaded and SHA-256 matched the tested after APK. Offline package com.sensen.basicroomqa, private ADB 5067, dedicated emulator-5584 / Liubei_BasicFire_API37.
- Whole-room image and **8s real-time desktop Mobile/Vulkan** fire closeup included. 130 wall-clock captures resampled to 30 FPS without acceleration; beginning/middle/end reviewed for motion, clipping and black frames. This clip is desktop evidence, not the Android performance capture.

## Android frame comparison

Same Godot 4.7.2 Mobile renderer, API 37 emulator, software Vulkan (`Goldfish GFXStream (llvmpipe LLVM 21)`), 2 CPU cores / 2 GB RAM, 720×1280 display, same 10.75 camera scale, avatar and HUD. 10s warm-up; each measurement requested 30s. No video/screenshot capture during the sample windows. The optional QA-only FrameProbe autoload is identical in both staged builds and measures monotonic frame-post-draw intervals.

| Build | Frame samples | Actual window | Median FPS | 1% low FPS | Draw calls |
|---|---:|---:|---:|---:|---:|
| Before static fire | 246 | 30.010s | 8.32 | 6.79 | 59 |
| After particle fire | 246 | 30.104s | 8.26 | 7.26 | 59 |

Median = 1000 / median frame interval (ms). 1% low = 1000 / mean of the slowest ceil(N×0.01) intervals, three frames in each run. Raw intervals are committed in before-/after-performance.json. The median is about 0.8% lower; this short pair does not establish a sustained performance improvement/regression. **模拟器帧率不代表真机性能。** These are application frame completion intervals, not GPU timestamps or physical-phone timing.

Reproduce: prepare_basic_room.py --output <stage> --frame-probe; import/configure atlas/import; export the isolated Android QA preset; set BASIC_ROOM_ADB_PORT to your private server and use tools/android/run_test.sh with android_qa.py --performance-only --seconds 30 --output <evidence>. Use --smoke-only for the short actual-input check. The existing full suite remains available. FrameProbe is only enabled by the explicit staging flag, never by production autoloads.

Desktop capture: run tools/dev/basic_room/record_fire.gd in the staged project with --disable-vsync --max-fps 60 and an absolute output directory. Its detail camera is only a review camera; the room's accepted main camera is unchanged.

PR targets farm-dev. Art-director review and user approval are required before merge; this work does not merge, deploy or mark the card Done.

Cleanup: only owned emulator PID 1192577 (ADB 5067 / emulator-5584) was stopped after the runner stopped its app; the touch fixture was removed. Existing emulators 5560/5570 were left running. No pkill or global adb shutdown was used.

Delivery: nine Plane attachments downloaded with matching hashes; three Lark messages with two byte-identical media downloads. PR #29 remains open. 奕星 received the notification in wt-p0-design-cd on the Mac mini and forwarded it to 哪吒/后裔 and the art reviewer; 后裔 acknowledged no 227 interface impact. See delivery-verification.json.

## Cooking brightness interface follow-up

`fx_hearth_fire.gd` now exports `glow_boost: float = 1.0` (editor range 0–4). External hosts tween it to 2.2 when cooking and back to 1.0 afterwards. The effect multiplies its existing base energy by this value before the unchanged flicker, and remains the sole writer of the borrowed `HearthGlow`. No particle/art defaults or textures change.

Rendered `test_basic_room.gd`: **22/22 passed**, including the two new requested brightness checks. Base .72 becomes **1.584** at boost 2.2; sampled boosted range **1.54965–1.65989**, within ±10%, then returns to .72. A negative control retaining the property but omitting its multiplier fails exactly the cooking-brightness check (21 others pass). An independent old/new-script comparison, loaded from pre-change commit 4b53ed0b, produces **3,600 exactly equal default-output samples**: 1,800 variable-delta steps each for Basic Room and the shared 3.1/.08 defaults, maximum difference 0.

`flame_strip.png`, `spark.png`, `particle_style.gd`, and every other FX resource except the fire script/README are byte-identical to each branch's baseline. `fx_hearth_fire.gd` only adds `glow_boost` and multiplies it into energy. The updated fire script and README are byte-identical on PR #29 and the art branches. The directory already differed in `fx_chimney_smoke.gd` / `smoke_strip.png` (PR R2.3 versus art R2.5); those differences are deliberately preserved under the instruction not to change art parameters or textures. The common README documents both versions.

[Interface test and preservation evidence](glow-boost-verification.json). Original Android measurements above remain the original particle-replacement run; this API-only follow-up does not claim a new emulator performance run. 172/173/175/178 recordings need not be repeated because default output is identical. Art-director recheck and user merge approval remain pending.
