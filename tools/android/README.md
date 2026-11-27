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

The target is `--serial`, else `JOURNEY_SERIAL`, `DEV`, then the Run's own device
(see below), else `emulator-5560`. `--device` picks the Run's physical device
(`CARDIGAN_DEVICE_SERIAL`). `ADB` selects the adb executable. The scenario
inherits `JOURNEY_SERIAL` and `JOURNEY_PACKAGE`. Build and install the APK before
starting the session. Use one session for the entire multi-step test, rather
than restarting the app for individual taps.

`--clean-all` can also precede a package to clean old apps before a new session.
The script does not uninstall packages, clear data, stop adb, or close emulators.
Cleanup failure makes an otherwise successful run fail. SIGKILL and host failure
cannot run shell traps; the next session's pre-launch stop handles that residue.

Verify runner behavior with `node --test tools/android/run_test.test.mjs`.

## adb port and device serial in a Cardigan Run (C-212)

A machine with per-Run adb slots gives each Run its own adb server and devices through these variables.
The scripts read them and fall back to the old defaults when they are not set, so manual runs are unchanged:

| Variable | Meaning |
| --- | --- |
| `ANDROID_ADB_SERVER_PORT` | the Run's adb server port (adb itself reads it too) |
| `ANDROID_SERIAL` | the Run's device (adb itself uses it when no `-s` is given) |
| `CARDIGAN_EMULATOR_SERIAL` | the Run's emulator, `emulator-<port>` |
| `CARDIGAN_EMULATOR_PORT` | the console port to start that emulator on (`emulator -port …`) |
| `CARDIGAN_DEVICE_SERIAL` | the physical device the Run holds |

- adb port: `build_worker_apk.sh` uses `ANDROID_ADB_SERVER_PORT`, else **5137** (until the slots are on, the
  workers' shared server); it refuses 5037 and anything that is not a port. `dynamic_farm/crash_repro.sh` takes
  it as the `--port` default. `gather_qa_apk.sh` already passed it on with the same fallback. The scripts below run `adb`
  without `-P` (`android_p0.sh` unless `ADB_PORT` is set), so adb uses the variable itself.
- Serial, any device (`run_test.sh`, `tools/dev/online_android_qa.mjs`, `tools/p0/android_p0.sh`,
  `--serial` default of `crash_repro.sh`): the script's own option or variable, then `ANDROID_SERIAL`,
  `CARDIGAN_EMULATOR_SERIAL`, `CARDIGAN_DEVICE_SERIAL`, then the old default (`emulator-5560`, `emulator-5570` in
  P0). `run_test.sh --device` takes `CARDIGAN_DEVICE_SERIAL` and fails when it is not set.
- Serial, emulator only (`tools/dev/combat_emulator_qa.mjs`, `combat_latency_emulator_qa.mjs`,
  `movement_emulator_qa.mjs`): `JOURNEY_SERIAL`, then `CARDIGAN_EMULATOR_SERIAL`, then `emulator-5560`.
  `farm_pond_removal_android_qa.py` accepts any `emulator-*` session, no longer only `emulator-5580`.
- Scenarios started by `run_test.sh` use the `JOURNEY_SERIAL` it exports, so they follow the same order.

Scripts with their own private adb server and SDK for a laptop or gs66 (`pond_art_adb.sh`,
`start_pond_art_emulator.sh`, `tools/dev/pond_art_godot.sh` on 5041; `tools/dev/basic_room/adb.sh` on 5061;
`tools/p0/build_demo_apk.sh`, `play_aab.py` and `start_emulator.sh`) keep their ports: they never use 5137, and
are not for Cardigan Runs. In a Run, start an emulator with `-port "$CARDIGAN_EMULATOR_PORT"` and never kill the
Run's adb server yourself; the host closes it when the Run ends.

Background CPU measurements and limitations are recorded in
[`docs/qa/android-background-cpu-2026-09-15.md`](../../docs/qa/android-background-cpu-2026-09-15.md).

## Godot editor runs and the shared adb server (C-210)

Godot's editor setting `export/android/shutdown_adb_on_exit` defaults to `true`. Every editor-mode
run (`--import`, `--export-*`, `--editor`; an iOS export too) of a project with a runnable Android
preset then ends with `adb kill-server`. Its adb is `$ANDROID_HOME/platform-tools/adb` unless the
settings name another SDK, and it honours `ANDROID_ADB_SERVER_PORT`, so on the Cardigan workers it
stops the shared server on **5137** (on mac-mini that drops the owner's tablet and every session's
emulator). The hosts set the key to `false` in the account's settings, but a run under a private
`HOME` reads other settings (on Linux also a private `XDG_CONFIG_HOME`; macOS reads
`$HOME/Library/Application Support/Godot` whatever `XDG_*` says), where the default applies.
Script-mode runs (`--script`, running a scene, gdUnit, `tools/ci/dynamic_farm_tests.sh`) open no
editor settings and never call adb.

The same runnable preset also makes the editor poll `adb devices` every few seconds, whatever the
key says. While the shared server is up that is only a client call; if it is down at that moment,
adb starts a new one under the run's `HOME`, with that `HOME`'s adb keys, and the devices show as
`unauthorized` (SEN-C-186#16). Presets a script generates for its own staging project are therefore
not runnable (a command-line export does not need it): then the editor makes no adb call at all.

Before an editor-mode run, with the same environment and Godot binary, run

```sh
python3 -I tools/godot_keep_adb_settings.py "$GODOT_BIN"   # default: $GODOT_BIN, else godot on PATH
```

It sets the key to `false` in the settings that Godot will read when they are private (creating
them if needed), and never writes the account's own settings or a self-contained Godot's; there it
only prints a note when the key is not `false`. Do this for any manual `HOME=... godot --import`
or export as well. Repository scripts already do it:

- `tools/run_tests.sh` (`--ci-import` and the local import), `tools/dev/pond_art_godot.sh` (so
  `open_pond_art.command`), `tools/dev/open_basic_room.sh`, `tools/dev/open_landmark_art.command`,
  `tools/dev/run_journey.mjs` (the `open_*.command` playtests), `tools/ios/setup_ios_g3.sh`;
- `tools/android/build_worker_apk.sh` and `tools/dev/dynamic_farm/gather_qa_apk.sh` run a portable
  editor copy whose own settings say `false`, with a generated non-runnable preset (so no adb call);
  `tools/dev/basic_room/prepare_basic_room.py` also generates a non-runnable preset;
  `tools/p0/build_demo_apk.sh`, `android_p0.sh` and `play_aab.py` use a portable copy whose settings
  say `false` through `tools/p0/godot_keep_adb.sh`.

The repository's own `export_presets.cfg` keeps its runnable presets, so an import or export of the
game project still polls `adb devices`, and if the shared server is down at that moment the editor's
adb starts one under the private `HOME` (C-213). adb takes its keys only from `$HOME/.android`
(`ANDROID_USER_HOME` is ignored, checked with platform-tools 37), so the same helper also makes
`$HOME/.android/adbkey` and `adbkey.pub` of a private `HOME` symlinks to the account's own
`~/.android` keys: a server restarted there offers the account's key and the devices stay
authorized. The account's `~/.android` is only read, and a `HOME` whose `.android` is the account's
is left alone. `SENSEN_ADB_KEY_DIR=<directory>` links another key pair instead and
`SENSEN_ADB_KEY_DIR=none` turns the links off.
Symlinks rather than `ADB_VENDOR_KEYS` because every caller already hands Godot the `HOME` it ran
the helper with, whereas an environment variable would have to be exported into each Godot process.

Tests: `python3 -m unittest tools/test_godot_keep_adb_settings.py` (its last case runs the real
Godot against a stub adb: without the helper the import calls `kill-server`, with it it does not).

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

A manual setup on gs66 with a fixed private port (5071) and emulator (`emulator-5594`); a Cardigan Run uses its own
adb port and emulator instead (see "adb port and device serial" above).

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
`adb -P 5071 kill-server`. Godot's Android export stops "its" adb server on exit unless its editor settings say
otherwise (see "Godot editor runs and the shared adb server" above); if it did, restart the private one with
`ADB_LOCAL_TRANSPORT_MAX_PORT=5553` set again.

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

## Cardigan worker: unsigned standalone APK (not Play)

Use `build_worker_apk.sh` for the tracked **Android** APK preset, not the demo
publisher or Play AAB scripts. It uses the package, version name and version code
from the selected commit unchanged in the default mode. `--dynamic-farm` instead
selects the isolated preview package `com.gensen.mapfarm` (same version).
This does not allocate a release version,
choose a production signing identity, install an app or authorize publication.

1. Have the host owner provision and register Godot **4.7.2 stable** export
   templates (including `android_source.zip`) and a shared Android SDK. Use
   `GODOT_TEMPLATES_DIR` for a non-default version directory, `ANDROID_HOME` for
   the SDK, `JAVA_HOME` for the JDK, and optionally `ANDROID_BUILD_TOOLS` for
   the build-tools directory (default `36.1.0`). Provision **only** the approved
   public runtime file via `CARDIGAN_MAPBOX_PUBLIC_FILE`: a worker-readable absolute
   path outside any repository. Do not put a copy, link or value in the checkout. Never copy an
   account's `.android`, Godot settings, Gradle home, keystore or passwords.
2. Confirm the **exclusive host Godot import/export window** with scheduling
   first. C-14 serializes with C-9: check ACASIS is mounted and at least 1.5 GB
   free+inactive+speculative memory is available before starting. In the worker Run, at the committed source
   revision, use an absolute path to a new output directory with an existing parent:

   ```sh
   tools/android/build_worker_apk.sh --dynamic-farm "$TMPDIR/candidate"
   ```

   The preview launches the existing parcel map, sets `online_qa` before autoload
   startup, isolates the user directory and disables Journey endpoints in staging only.
   It keeps the committed read-only dataset config and includes the raw map, scenery
   and avatar JSON needed for 3D preview. Do not change the production project/presets.

   **Internal test package (C-39).** Only when explicitly selected,
   `--dynamic-farm-internal TARGET` builds `com.gensen.mapfarm.internal` from the same
   staging, but points both Journey URLs at `TARGET` and sets
   `sensen/dynamic_farm/reselect`, `sensen/dynamic_farm/account_restore` (C-32) and
   `sensen/dynamic_farm/own_farm` (C-34: "Enter my farm" opens the farmable own parcel). `TARGET`
   must exactly equal an entry of `APPROVED_TARGETS` in `dynamic_farm_export.py`: today only
   the isolated C-38 test service `https://aliyun-sh-plane.taildf0ff5.ts.net:8443/v1`
   (tailnet only). Production, devserver, P0 and any other address are refused before staging.
   `online_qa` stays on, so `Net` never boots. The map reloads a token the tester saved by signing in
   on the device; without one it shows only the sign-in panel (no ✕) until the tester signs in or signs up:
   there is no guest entry in any package (C-146), and the readback refuses C-100's `guest_play`.
   No account or credential goes into the package. Use it for internal testing only: no signing or distribution.

   ```sh
   tools/android/build_worker_apk.sh --dynamic-farm-internal \
     https://aliyun-sh-plane.taildf0ff5.ts.net:8443/v1 "$TMPDIR/internal"
   ```

   **Release package (C-98, C-101).** `--dynamic-farm-release` builds the release of the
   dynamic farm from the same staging. It keeps the preview's package `com.gensen.mapfarm`,
   its user directory and the `Android` preset's version; only the display name becomes `Dynamic Farm`. It takes no target: both Journey URLs are always
   `RELEASE_TARGET` in `dynamic_farm_export.py`, the US West dynamic farm production service
   `https://farm.sensenjoy.cn/dynamicfarm/v1` (C-96 materials, C-97 entry). It sets
   `sensen/dynamic_farm/own_farm` and `sensen/dynamic_farm/account_restore`, never `reselect`, and adds
   `sensen/network/fixed_server`, which makes `Net` ignore `user://server.txt` (C-116): the release only
   ever connects to the address it was built with. Every other package still reads the override.
   Since C-101 the account panel offers email sign-in (which invite accounts use too), email sign-up
   and password reset. C-98's `sensen/account/invite_only` is refused in every package. C-101 hid Sign
   in with Google behind `sensen/account/google_off`; C-172 (owner C-101#206) removed that switch, so
   every dynamic farm package shows the Google button on a phone with Google Play services, and the
   readback refuses any `sensen/account/*` setting, `google_off` included.
   If the server still takes no new accounts (`ACCOUNT_SIGNUP=closed`), sign-up says so. Google
   sign-in needs an Android OAuth client for `com.gensen.mapfarm` (and one for
   `com.gensen.mapfarm.internal` with the certificate the internal package is signed with)
   and the signing certificate's SHA-1 in the same Google Cloud project as the web client id the
   package asks tokens for (`sensen/auth/google_web_client_id` in `project.godot`, the owner's
   production project starting 870347303349, not gensen-preview). The production compose's
   `GOOGLE_CLIENT_IDS` must contain that id; `test_worker_apk.py` and
   `server/test/ops/dynamicfarm.test.ts` check it.
   `online_qa` stays on, so `Net` never signs in anonymously; without an account the map does not open
   at all: only the sign-in panel (no ✕) shows until the player signs in or signs up (C-146).
   Building it does not sign or publish it: signing with the 0.4.1 certificate and distribution are C-99.

   ```sh
   tools/android/build_worker_apk.sh --dynamic-farm-release "$TMPDIR/release"
   ```

   **No "sensen" for players (C-142).** The owner's rule (C-101#91) is that nothing players see carries
   "sensen". All dynamic farm packages therefore use the owner's package name `com.gensen.mapfarm`
   (`.internal` for the internal package; C-142#7, Q-171), which replaced `com.sensen.dynamicfarm.cardigan` /
   `com.sensen.dynamicfarm.internal`: a phone with a 0.4.x package must uninstall it once, its saved sign-in
   and local data do not carry over (accounts and farms on the server are unaffected), and the Google
   sign-in Android client must be registered for the new package. The staging also renames the project
   (`config/name`, otherwise `SensenAvatar`) to the display name and sets the launcher icon to farm-dev's
   P0 icon in `tools/app_icon/android` (from bcefa351, the Android P0 / Play presets' files). Deliver the
   APK under the name in `unsigned.json`'s `filename`
   (`mapfarm[-internal|-preview]-<version>-<code>-<commit 8>-unsigned.apk`; a signed copy ends
   `-signed.apk`). The domains, the `[sensen]` setting section and code identifiers (Kotlin packages
   `com.sensen.*` of the plugins) are internal and unchanged.

   Readback (`verify`, `check-unsigned`) parses the exported `assets/project.binary` and
   rejects a package whose Journey settings do not match its variant: internal settings or
   the internal target in any other package, a reachable Journey in the isolated preview,
   QA isolation in the release-configuration (default) package, or a dynamic farm release that
   is not exactly the production target with its three settings and no reselect, or whose user
   directory is no longer `DynamicFarmCardigan` (an in-place upgrade of 0.4.1 would leave its local
   data and sign-in behind; C-116), and invite-only sign-in or the production target anywhere
   else. `unsigned.json` records the
   result under `config`.

   The script stages committed game sources in a disposable project, generates
   one non-runnable, `package/signed=false` APK preset, prepares the Gradle template + native
   plugins, then imports and exports **release** serially in a fresh portable
   editor. It points ADB at `ANDROID_ADB_SERVER_PORT` (default 5137, see "adb port and device serial"
   above), disables editor ADB shutdown and needs no
   device or emulator. Gradle may need to download build dependencies; there
   is no artifact upload step in the build script.

   **Gradle distribution seed (C-64).** The Gradle home is disposable, so the wrapper
   would download its distribution on every build. If the host keeps the official zip in
   `$HOME/.local/share/sensen-godot/gradle-wrapper-dists` (override with
   `CARDIGAN_GRADLE_DIST_SEED`; layout as `~/.gradle/wrapper/dists`, e.g.
   `gradle-8.11.1-bin/bpt9gzteqjrbo1mjrsomdt32c/gradle-8.11.1-bin.zip`),
   `gradle_dist_seed.py` copies only that zip into the temporary Gradle home after its
   SHA-256 matches the official value (pinned in `OFFICIAL_SHA256`). A mismatched,
   missing or unverifiable seed is reported on stderr and the wrapper downloads as before;
   with no seed directory nothing changes. After export it reports whether the seeded zip
   was used. Dependency caches are never shared, and `gradle-wrapper.properties` is unchanged.
   When the Android template moves to another Gradle version, add that version's official
   digest to `OFFICIAL_SHA256`; until then builds fall back to downloading.

   Template and APK directory
   entries are screened for keystores and `export_credentials.cfg` before any
   member is opened for extraction or CRC checks. It refuses signing metadata
   **before** alignment as well as afterwards. Success produces `unsigned.apk`,
   `unsigned.json` (manifest identity, size, SHA-256; for a dynamic farm package also the delivered
   `filename`) and `source-commit.txt`.
3. For **C-496 only**, use the configured Card MCP `upload_attachment` large
   artifact flow (`artifact_size`, `sha256`, `kind=artifact`, no inline `file`).
   Stream only the verified APK to the one-use **internal** destination on the
   configured MCP endpoint. Do not log the ticket or follow off-origin redirects.
   Verify stored size/digest or download and re-hash. Record the attachment ID,
   unsigned SHA-256, source commit, card and Run. A locally computed hash or an
   issued upload ticket is **not** proof of storage.
4. Sign only when the **Android C-500** route and approved package/certificate
   identity are confirmed. Submit the stored unsigned artifact by ID/digest;
   never use local signing as a fallback. Obtain the signed artifact and audit
   receipt. Read back its manifest against the **original source revision** and
   verify it against the approved **public certificate** fingerprint (not a
   value inferred from the APK itself):

   ```sh
   python3 tools/android/worker_apk.py --variant dynamic-farm --presets export_presets.cfg verify \
     "$SIGNED_APK" --build-tools "$ANDROID_BUILD_TOOLS" --signer-sha256 "$APPROVED_CERT_SHA256"
   ```

   Match the unsigned input SHA-256, signed output SHA-256, signer, card, Run
   and audit ID to the service receipt before recording success. Do not realign
   or otherwise rewrite the signed APK. If provisioning, internal storage or
   signing is unavailable, report the missing step; no external mirrors, manual
   signing, installation or distribution.

Local checks: `python3 -m unittest discover -s tools/android -p test_worker_apk.py -v`.
With SDK platform 36 and its build-tools/JDK configured, the fixture test uses
real `aapt`, `zipalign` and `apksigner`. Fixture bytes are **not** a game export.
