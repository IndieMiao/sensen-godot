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

## In-app WebView (voice-match H5)

After `setup_android_build.sh` (and `prepare_voice_plugin.py`), run
`python3 tools/android/prepare_webview_plugin.py` to install `GodotWebView`
from `native/webview/android/`. Godot 4.7 ignores `onMainBackPressed()` return
values, so GDScript must swallow the back press that closed the page
(`VoiceMatchLink.blocks_back_navigation()`).

Debug builds can point the page at a local dev server:
`adb reverse tcp:5173 tcp:5173`, then write `http://localhost:5173/` into the
app's `files/voice_match_base_url.txt` via `run-as`. Delete it afterwards.
