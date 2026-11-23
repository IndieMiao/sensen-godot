# Android Test Sessions

Run installed Sensen apps through `run_test.sh`. The script force-stops the
target before launch and on normal exit, test failure, Ctrl-C, SIGTERM or SIGHUP.
It stops the test command's process group too. It keeps the emulator and saves.

```sh
# Manual session: press Enter when finished.
tools/android/run_test.sh com.sensen.journeycombatqa

# Bounded launch smoke check.
tools/android/run_test.sh --wait 10 com.sensen.journeycombatqa

# Run a whole scenario, including all navigation, inside one session.
tools/android/run_test.sh com.sensen.journeycombatqa -- node path/to/scenario.mjs

# Stop only this project's apps, leaving the emulator running.
tools/android/run_test.sh --clean-all
```

The default target is `emulator-5560`; set `--serial`, `JOURNEY_SERIAL` or `DEV`
for another authorized device. `ADB` selects the adb executable. The scenario
inherits `JOURNEY_SERIAL` and `JOURNEY_PACKAGE`. Build and install the APK before
starting the session. Use one session for the entire multi-step test, rather
than restarting the app for individual taps.

`--clean-all` can also precede a package to clean old apps before a new session.
The script does not uninstall packages, clear data, stop adb, or close emulators.
Cleanup failure makes an otherwise successful run fail. SIGKILL and host failure
cannot run shell traps; the next session's pre-launch stop handles that residue.

Verify runner behavior with `node --test tools/android/run_test.test.mjs`.

Background CPU measurements and limitations are recorded in
[`docs/qa/android-background-cpu-2026-09-15.md`](../../docs/qa/android-background-cpu-2026-09-15.md).

## Test build version

Android test builds take `version/name` and `version/code` from the `Android`
preset (`com.sensen.journeypreview`) in `export_presets.cfg`; Cardigan's
test-build tooling swaps only the package and display name. Keep the name in
the 0.4.x series (started at 0.4.1 on 2026-11-23, q(337)); moving to 0.5.x
waits for the owner to ask. The previous 0.16.x line was this preset's own Journey numbering,
which had grown from the 0.4.0 local device builds of 2026-09-14.

`version/code` is `YYYYMMDDNN`: the date the version changes, `NN` from 01 and
+1 for another build that day. It must stay above 2026092405 (the 0.16.37
test build) so installed phones can upgrade in place.
`tests/journey/test_journey_export_preset.gd` checks both rules.

## Tailscale remote ADB

The user requested a stable remote connection on 2026-09-25. V2509A was verified
as serial `10AFAF162200319`; its current Tailscale endpoint is
`100.114.132.11:5555`. TCP mode was enabled through the already-authorized
connection using `adb -s "$PHONE_ADB_SERIAL" tcpip 5555`. Disconnect/reconnect
passed and `ro.adb.secure` remains `1`; existing ADB authorization is retained.

Check the live Tailscale peer before using a recorded address, then connect to
port 5555 and verify the physical serial. Do not select an emulator or shut down
other ADB servers while reconnecting.

```sh
adb connect 100.114.132.11:5555
adb -s 100.114.132.11:5555 shell getprop ro.serialno
```

Android's Wireless debugging page shows a separate automatically assigned TLS
port, which can change whenever that service restarts or the network changes.
It need not match 5555. The TCP setting is for the current boot and may need to
be enabled again after reboot or disabling debugging. If 5555 is unavailable,
discover the current TLS endpoint with `adb mdns services` on the same LAN or
the phone's current Wireless debugging page, connect through that authorized
endpoint, and enable TCP mode again. This does not configure persistent/root
settings or require changing the game or its data.

## Linux x86_64 emulator (gs66)

Verified on 2026-10-10 on gs66-ubuntu (SGODOT-276): Pixel_API_36, Android 16 x86_64, P0 QA package. Mapbox
(Core Maps 11.29) and LiveKit load from `lib/x86_64`, the map renders, and the app reaches a local P0 server.
This is an emulator for map and UI tests only. It never touches a USB or remote phone, and it does not replace
phone acceptance.

**Display and GPU.** A shell over SSH has no display: `-gpu host` fails with `Failed to get EGL display`, and
SwiftShader is too slow for P0. Someone must stay logged in to a desktop session on the machine
(`loginctl list-sessions` shows a `wayland` session on a seat). Borrow its display:

```sh
export DISPLAY=:0 WAYLAND_DISPLAY=wayland-0 XDG_RUNTIME_DIR=/run/user/$(id -u)
export XAUTHORITY="$(ls /run/user/$(id -u)/.mutter-Xwaylandauth.* | head -1)"   # without it -gpu host fails
```

**Guest Vulkan must be off.** With the guest's Vulkan on, Godot's render thread blocks in
`vkAcquireNextImageKHR` after a few `Couldn't present to Vulkan queue (VkResult error 5)`. The main loop stops,
so `HTTPRequest` connects and then never sends (`Can't reach the farm server`). A bare Godot 4.7.2 project
does the same, so this is not game code. `-feature -Vulkan` makes Godot fall back to GLES3 Compatibility on
the host GPU:

```sh
lsusb   # no phone may be plugged in: a newly started adb server takes over any USB phone it finds
export ANDROID_ADB_SERVER_PORT=5071   # a private adb server; leave 5037 and other sessions' servers alone
# Don't scan 5555+ for other people's emulators; an emulator started with the variable above registers itself.
export ADB_LOCAL_TRANSPORT_MAX_PORT=5553
nohup ~/Android/Sdk/emulator/emulator -avd Pixel_API_36 -port 5594 -no-window -no-audio -no-boot-anim \
  -no-snapshot-save -gpu host -feature -Vulkan -memory 4096 -cores 4 > /tmp/emu-5594.log 2>&1 &
adb -P 5071 start-server
adb -P 5071 -s emulator-5594 shell dumpsys SurfaceFlinger | grep -m1 GLES:   # expect the host GPU, not SwiftShader
adb -P 5071 -s emulator-5594 shell settings put secure immersive_mode_confirmations confirmed
```

Record the qemu PID. Stop the emulator with `adb -P 5071 -s emulator-5594 emu kill` (its data is kept), then
`adb -P 5071 kill-server`. Godot's Android export stops "its" adb server on exit, so restart the private one
after every export, with `ADB_LOCAL_TRANSPORT_MAX_PORT=5553` set again.

**QA package.** The P0 presets build arm64 only. For the emulator, export `Android P0` with `x86_64` turned on
in a temporary copy of `export_presets.cfg`, and restore the file afterwards, as `tools/p0/build_demo_apk.sh`
does. Use a package of its own, e.g. `com.sensen.p0demo.gs66qa`, never `com.sensen.p0demo` or the Journey
package. Sign it with the machine's own debug keystore (Godot editor settings), never the release certificate.
`mapbox_token.txt` must be in the repo root (git-ignored).

**Server address.** Run the local P0 server (`cd server && node --import tsx tools/p0_server.ts`, port 3110)
and point the app at the host through the emulator's NAT. `files/p0_scene` = `map` opens the map directly:

```sh
P=com.sensen.p0demo.gs66qa
adb -P 5071 -s emulator-5594 shell "run-as $P sh -c 'echo http://10.0.2.2:3110/v1 > files/p0_server.txt'"
adb -P 5071 -s emulator-5594 shell "run-as $P sh -c 'echo map > files/p0_scene'"
```

Delete both files afterwards. `adb reverse tcp:3110 tcp:3110` with `127.0.0.1` was unreliable here.

Known on this emulator: a cold start straight into the farm takes about 9 s to its first frame. That exceeds
the 8 s request timeout, so the app shows one `Can't reach`, then recovers on the next refresh (SGODOT-276).

## In-app WebView (voice-match H5)

After `setup_android_build.sh` (and `prepare_voice_plugin.py`), run
`python3 tools/android/prepare_webview_plugin.py` to install `GodotWebView`
from `native/webview/android/`. Godot 4.7 ignores `onMainBackPressed()` return
values, so GDScript must swallow the back press that closed the page
(`VoiceMatchLink.blocks_back_navigation()`).

Debug builds can point the page at a local dev server:
`adb reverse tcp:5173 tcp:5173`, then write `http://localhost:5173/` into the
app's `files/voice_match_base_url.txt` via `run-as`. Delete it afterwards.
