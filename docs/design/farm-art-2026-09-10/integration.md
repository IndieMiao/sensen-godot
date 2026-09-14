# Farm Art App Integration, 2026-09-10

The subsequent public release is documented in
[`docs/qa/farm-public-release-2026-09-10.md`](../../qa/farm-public-release-2026-09-10.md).
Use its public APK links for partner sharing. The earlier local/USB packages
below are retained as integration evidence.

The accepted farm art is enabled in the full game's shared farm scene. Both app
variants include all 24 Blender meshes, seven house styles, meadow texture,
terrain shaders, scenery batching and fitted orthographic camera clipping.
The initial house style is cottage. Packaging adds no gameplay or save migration.

## Deliverables

All files are under `output/farm-app-2026-09-10/`:

| Entry | Artifact | Android package |
| --- | --- | --- |
| Workshop09-09 | `sensen-workshop-farm-art-2026-09-10.apk` | `com.sensen.workshoppreview0909` |
| Default Android | `sensen-android-farm-art-2026-09-10.apk` | `com.sensen.avatarphase1` |
| Workshop desktop | `Open-Workshop0909.command` | Runs the extracted Workshop APK resources |

Both APKs are debug signed, ARM64, minimum SDK 29, target SDK 36, about 127 MiB.
Version code: `2026091001`; version name: `0.2.0-farm-art.20260910`.
Signatures were verified with Android `apksigner`.

- Default APK SHA-256: `efc84d4e564fa5250af5ae7a28e2d1ced8b8aab664288f168ad4d772534fdb27`
- Workshop APK SHA-256: `5cd4e146631d788fb5f29671945b498235cc414c3256db95f5e559478f17572c`

Workshop retains its existing `sensen-workshop-preview-20260909` desktop user
directory and preview database on port 3134. The Android preview uses
`http://10.0.2.2:3134/v1`; desktop uses `http://127.0.0.1:3134/v1`.
The launcher starts or reuses the existing preview service, then opens the full
game. Its APK is configured for Android Emulator loopback, as the prior preview
was; it is not a standalone online service for physical phones.

The default app retains the root main scene, user directory, autoloads and
`https://farm.sensenjoy.cn/v1` endpoint, including support for an existing
`user://server.txt` override. It includes no QA bootstrap or custom QA feature.

## Verification

- 41 native Godot/Metal regression tests passed across router navigation,
  visitor farms, farm interior/server-cell mapping and map home anchoring.
  Report: `reports/report_887/results.xml`.
- The headless attempt cannot read MultiMesh transforms accurately with Godot's
  dummy renderer. The actual-renderer rerun passes all visitor crop-height checks.
- Both APK resource checks load all 24 meshes, both terrain shaders and the
  meadow texture; verify light and camera scene settings; and exclude Blender
  source, the art-preview scene and tests. Farm bytecode is identical across
  default, Workshop and the isolated QA APK.
- Workshop APK installed and launched on `emulator-5560`. Normal city selection,
  placement and creation entered the accepted farm at state version 0. Actual
  screenshot: `evidence/workshop-farm.png`.
- The independent `com.sensen.journeyfarmartqa` package exercised city selection,
  farm creation, walking, panning, two-finger zoom, return to the native map,
  re-entry and cold restart. Inputs were derived from live Godot control/world
  rectangles. State after creation equals state after navigation and restart.
  Screenshots, touch receipts and before/after snapshots are in `evidence/`.
- The default APK successfully updated the existing app on `emulator-5554`
  using `adb install -r`. Its first-install timestamp remains 2026-09-04.
  SHA-256 checks of installation identity, city choice, farm choice and UI state
  were identical before installation, after installation and after launch.
  The prior private app data was backed up locally before updating.
- Default launcher and native map were visually checked. Its map displayed the
  offline sample-farm fallback in this emulator. Full default-package online
  farming/touch navigation was not verified: Godot buttons are absent from the
  Android accessibility tree and do not accept keyboard focus on the map.
  A temporary local inspection attempt was rejected by Android activity isolation;
  its files were removed. No instrumentation entered either deliverable.
- The Workshop desktop launcher ran the extracted APK with Metal Mobile and the
  existing preview service, without script or resource errors.

Emulator farm snapshots reported 58-60 FPS; these are spot readings, not a device
performance benchmark. No physical phone was connected during that initial check. The existing Godot/Mapbox
native libraries still produce Android's 16 KB page-size compatibility dialog on
the 16 KB emulator; the game runs after dismissal. This packaging task did not
upgrade those native dependencies.

## Physical Device Installation

Both apps were subsequently installed on the connected V2509A (ARM64), Android
user 0, at the user's request. Both report version code `2026091001` and version
name `0.2.0-farm-art.20260910` and successfully cold launched to the city screen.
Neither process logged script loading errors, shader errors or fatal exceptions
during the launch check. Screenshots are `evidence/phone-default-start.png` and
`evidence/phone-workshop-start.png`. This is an installation/startup check, not a
physical-device gameplay or performance benchmark.

The default app was updated with `adb install --user 0 -r`. Its installation
identity, city/farm choices, UI state, authentication session, server override and
IM sync files had identical checksums immediately before and after installation.
Private application data was backed up locally before the update.

The phone's existing default-app server override points to port 3101 on loopback.
It was preserved; USB forwarding was restored for ports 3101 and 3134. Both local
services were healthy. Keep the USB connection and computer services running.

The Workshop phone APK is `sensen-workshop-farm-art-usb-2026-09-10.apk`. It uses
`http://127.0.0.1:3134/v1` through `adb reverse`, keeping the Workshop package ID,
signature and user-directory configuration. Its 24 models and seven initialized
farm styles passed the extracted-resource check (`usb-resources.json`). SHA-256:
`efb57c7402c8b45025332608563066722d4298282084a45be79d804d3a064944`.

Rebuild this variant using `--farm-app-usb` with the preparation script, then
export from `output/farm-app-2026-09-10/usb-project`. Restore USB forwarding after
reconnection with `adb -s DEVICE_SERIAL reverse tcp:3134 tcp:3134` for Workshop
and `adb -s DEVICE_SERIAL reverse tcp:3101 tcp:3101` for this phone's default app.

## Rebuild

From the repository root, using Godot 4.7.2, the configured Android SDK and Android
Studio's bundled JBR:

```sh
godot --headless --path . --script res://tools/dev/prepare_farm_app_export.gd
godot --headless --path output/farm-app-2026-09-10/project --export-debug 'Android Farm App'
godot --headless --path . --script res://tools/dev/prepare_farm_app_export.gd -- --farm-app-default
godot --headless --path output/farm-app-2026-09-10/default-project --export-debug 'Android Farm App'
```

The optional `--farm-app-qa` mode creates the independent QA package. Staging
shares only `.godot/imported`; its script-class cache and editor state are local,
so exporting cannot remove root-project test classes such as `FakeTransport`.
Extract each APK's `assets/*` before running
`tools/dev/verify_farm_app_resources.gd` with that extracted assets directory as
`--path`. Require a fresh JSON report with `passed: true`, not just Godot's exit
code. Exported scene binaries may carry different resource IDs; compare their
parsed scene properties instead of expecting binary-identical packed scenes.
