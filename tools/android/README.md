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

## In-app WebView (voice-match H5)

After `setup_android_build.sh` (and `prepare_voice_plugin.py`), run
`python3 tools/android/prepare_webview_plugin.py` to install `GodotWebView`
from `native/webview/android/`. Godot 4.7 ignores `onMainBackPressed()` return
values, so GDScript must swallow the back press that closed the page
(`VoiceMatchLink.blocks_back_navigation()`).

Debug builds can point the page at a local dev server:
`adb reverse tcp:5173 tcp:5173`, then write `http://localhost:5173/` into the
app's `files/voice_match_base_url.txt` via `run-as`. Delete it afterwards.
