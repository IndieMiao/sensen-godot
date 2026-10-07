# Basic Room: Godot and Android verification

Date: 2026-10-06. Scope: Blender reconstruction of the requested Figma room, reusable assets, offline movement, Android emulator checks and self-chat review. The user subsequently accepted the asset quality and requested a commit/push. This is not a Journey release, physical-device installation or save migration.

The [case README](../design/basic-room-2026-10-06/README.md) contains implementation/reproduction instructions. Other art agents should read the [production workflow](../design/mobile-3d-asset-workflow.md). The committed [verification summary](../design/basic-room-2026-10-06/verification-summary.json) and [comparison](../design/basic-room-2026-10-06/comparison.png) remain available without this workstation's ignored logs.

## Final assets

- Editable source: `tools/art/source/basic_room/basic_room.blend`.
- Reusable room: `scenes/basic_room/basic_room_art.tscn`.
- Character/movement benchmark: `tools/dev/basic_room/basic_room.tscn`.
- 22 reusable GLBs, 23 placed instances, 47,256 unique triangles / 48,552 placed room triangles.
- One 2048 × 2048 base-color/contact-AO atlas, mipmapped and VRAM-compressed. No direct sunlight baked into albedo.
- GLBs total 1,712,708 bytes; atlas PNG 3,397,744 bytes. File size is not GPU residency.
- 2048 directional shadows, MSAA 4×, one shadowed directional light and one unshadowed hearth light.

## Rendered desktop checks

Godot 4.7.2 / Vulkan Mobile on AMD Custom GPU 0405, RADV VANGOGH. All **16 behavioral checks passed**: avatar assembly, kit loading, floor height, displacement, release/idle, table/wall/edge blocking, diagonal sliding, run animation at the distant camera, focus-loss cancellation, reference-view switching, two-finger scaling and release cancellation.

The initial headless animation check failed because `VisibleOnScreenNotifier3D` reported the rig invisible and the existing `RigActivity` paused it. The rendered check passed without weakening shared animation throttling.

Local log: `output/basic-room-2026-10-06/native-rendered-tests-final.log`. A 1600 × 1600 SubViewport captures the same Godot Mobile world without desktop window-size clamping. Orthographic checks were rendered from the Blender geometry.

## Android input checks

| Item | Verified configuration |
|---|---|
| Package | `com.sensen.basicroomqa`, 0.1.0 / 2026100601, debug-signed, ARM64 + x86_64 |
| AVD | `Sensen_BasicRoom_API35`, Android 35 / x86_64 |
| Endpoint | `emulator-5588`, private ADB server 5061 |
| Correct final backend | `-gpu lavapipe -feature -VulkanNativeSwapchain` |
| Actual game renderer/device | Vulkan Mobile / `llvmpipe (LLVM 21.0.0, 256 bits)` |
| Session | `tools/android/run_test.sh`; stops the app on exit, retains emulator/install |
| Data scope | Fixture outfit and isolated user directory; no game login, farming, inventory or historical restore |

All **18 checks passed**, with actual Android MotionEvents for movement, release, buttons and symmetric pinches. Coverage includes character-on/off pixel comparison below the head, table/open-edge collisions, zoom without avatar movement, View button, same-process foreground recovery, three-size HUD containment/movement, and continuing idle animation.

Sizes: **720 × 1280, 780 × 1688, 1080 × 1920**, with cold starts after resizing and current-PID observation. Fixture commands only arrange starting states. Commands/state use atomic replacement and sequence acknowledgments to avoid partial JSON or gestures racing a reset. Tests plus recording used 13 touch operations.

Local evidence: `android/result.json`, per-step PNG/JSON and `android-suite.log` under `output/basic-room-2026-10-06/`. The installed APK was pulled back and compared byte-for-byte. Archive inspection confirmed 22 model imports and the ETC2 atlas. The committed summary retains the readback receipt.

## Failures and corrections

1. **Black output / Vulkan present error 5.** Several backends failed on the Swappy path. Checking the matching Godot source led to `display/window/frame_pacing/android/enable_frame_pacing=false` in the isolated QA project, restoring presentation on the same API 35 AVD. This is a scoped environment workaround.
2. **Missing skinned body under host GPU translation.** Room and rigid hair rendered, but the body did not. This backend briefly reported 60 FPS and later had graphics-context failures. Those images/numbers are failed evidence. Software Vulkan showed the complete character, outfit and animation.
3. **Symmetric pinch ignored.** Touch down/up arrived, but centered scaling did not generate the expected drags with native Android scale gestures disabled. Enabling `input_devices/pointing/android/enable_pan_and_scale_gestures` and handling `InputEventMagnifyGesture` fixed the actual-input case. Native/raw paths are deduplicated. The tested pinch changed camera size from 10.75 to about 6.03 without moving the avatar.
4. **Geometry/shading defects.** Corrected custom-mesh normals and window/firebox booleans, sink lining, chair/runner orientation and bevel shading. The external garden card does not block sunlight through the aperture.

An API 36.1 image was downloaded during diagnosis, but it was not the final passing environment and is not counted as a completed platform test.

## Performance limits

At 1080 × 1920 the final **software Vulkan** emulator produced 24 samples: median/minimum **7 / 7 FPS**, median **59 draw calls**, maximum reported rendering memory **181,613,824 bytes (about 173.2 MiB)**. This includes targets, shadows, caches and the avatar, not just room assets.

The separate desktop live recording reported median **60 FPS**, minimum **53 FPS** and median **59 draw calls**. Neither desktop nor software-emulator timing establishes phone GPU performance. Physical-device GPU time, power, temperature and sustained frame rates remain untested. The asset budget is approximately 48.5k placed triangles, 23 static surfaces and one shared 2K atlas.

## Review artifacts and delivery

Committed examples are under `docs/design/basic-room-2026-10-06/`; bulk artifacts remain local under `output/basic-room-2026-10-06/`:

| Artifact | Content |
|---|---|
| `godot-beauty-final.png` | Complete room in Godot |
| `comparison.png` | Reference / Godot / Android; Android center crop retains the whole room |
| `orthographic-sheet.png` | Blender front, side and top views |
| `android/05-final-gameplay.png` | Android image with the existing character |
| `android-review.mp4` | Actual 1080 × 1920 Android recording, about 32 seconds; software Vulkan, not sped up |
| `desktop-review.mp4` | Separately labeled 28-second live desktop recording; window decoration cropped |

The user authorized Lark CLI as the Slack alternative. OAuth and self-conversation readback verified the recipient. **One report, four PNGs and two MP4s were sent**; all seven messages were read back, and all six downloaded attachments were byte-identical. Local `delivery/verified-media.json` holds full receipts; the committed summary retains the outcome without private chat identifiers.

The app was stopped, the emulator retained, and temporary device touch/recording files removed after local copies were saved. No public release or physical phone update was performed.
