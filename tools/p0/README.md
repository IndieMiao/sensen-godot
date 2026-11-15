# P0 release tools

## Play AAB: local build, inspect, copy to Downloads

`build_play_aab.sh` exports the existing **Android Play** preset with the approved
upload certificate. It never uploads, installs an app, changes a server or accesses
a Play service account. Play uploads remain manual while the current organization
policy prevents creating the upload credentials. An AAB passing these checks is
not evidence that store forms, real sign-in, device tests or submission prerequisites
have passed.

Before a **submission** build, the approved accounts backend including q(320) must
be live, `https://gensen.app/terms` must be live, and the `TERMS_LIVE` change must be
merged. Until those conditions are met, store artifacts are for **internal testing**.
See the release checklist for the actual approved source and deployment evidence.

### Build host preparation

- Reserve the Mac build window and check that no USB installation session is active.
  The script additionally checks USB for vivo/V2509/Android before starting Godot,
  requires its private ADB port to be free, uses port 5071 by default with
  `ADB_LOCAL_TRANSPORT_MAX_PORT=5553`, and stops that private ADB server afterwards.
- Use a committed, clean source tree. Untracked export inputs other than generated
  `.uid` files are refused; the Play preset's exclusion filters apply. Do not use a
  QA bootstrap or project with `accounts_ui_qa` enabled.
- Install the normal Godot Android template and refresh the native plugins:

  ```sh
  tools/android/setup_android_build.sh
  python3 tools/android/prepare_voice_plugin.py
  python3 tools/android/prepare_webview_plugin.py
  python3 tools/android/prepare_notify_plugin.py
  python3 tools/android/prepare_google_signin_plugin.py
  ```

  Build inputs must match the tracked Mapbox/voice/WebView/permission/notification/
  Google sources and current Mapbox dependency. The final merged manifest is checked
  again, so stale template permissions cannot silently enter a new AAB.
- Supply the existing `mapbox_token.txt`; never print it or commit it.
- Install bundletool locally from its official release and set `BUNDLETOOL_JAR`.
  The script does not download tools. A JDK providing `java`, `jarsigner` and
  `keytool` is required. macOS defaults to Android Studio's bundled JDK;
  other hosts set `JAVA_HOME` and `ANDROID_HOME`.
- The default keystore is `~/.config/sensen/gensen-play-upload.keystore`, alias
  `upload`, with private file permissions. On macOS its password comes from the
  existing login keychain item `sensen.android.play-upload-keystore`; no keychain
  setup or backup is performed. A configured `GODOT_ANDROID_KEYSTORE_RELEASE_PASSWORD`
  environment value can be used instead, including on Linux. Never put passwords
  on the command line. The public upload certificate SHA-256 is pinned in the checker;
  `--expected-signer` is only for an explicitly approved certificate rotation.
- The baked game key comes from `P0_KEY`, or `--key-file` (default
  `output/p0-deploy/key`). No key is generated. It is compared on readback without
  printing it. This key is necessarily embedded in the client artifact, as in the
  existing preview export; it is not the signing password.

### Build r2 or a later revision

```sh
export BUNDLETOOL_JAR=/path/to/bundletool.jar
tools/p0/build_play_aab.sh \
  --server https://farm.sensenjoy.cn/preview/p0/v1 \
  --name 0.3.11 --revision r2 --code 2026111501
```

Choose the actual date/sequence for `--code`; the example is not a reserved number.
New builds must exceed r1's **2026111401** and every locally reserved code in
`output/p0-play/versions.json`. A failed export still reserves its code, so the
next attempt increments it. `--code` is explicit, never guessed from a preset.
The local ledger cannot know which codes another build host or Play Console has
already used: reconcile those before choosing the number. `NN=00` is not accepted.

The build gets an immutable output directory such as
`output/p0-play/0.3.11-r2-2026111501/`; its preset/config changes are temporary.
Both the original bytes and permissions of `export_presets.cfg` and an existing
`assets/p0/demo_server.json` are restored on success, failure or interruption.
No APK code path or existing `build_demo_apk.sh` behavior is changed.

Only after verification does the AAB appear as
`~/Downloads/gensen-0.3.11-play-r2.aab`. This preserves the first
`gensen-0.3.11-play.aab` and refuses to overwrite any earlier revision. Copying uses
a hidden partial file, a full checksum, then an exclusive atomic link. A failed or
interrupted copy does not leave a partial file under the uploadable `.aab` name.

The final message gives path, bytes, SHA-256, versionCode and report path. `build.json`
contains the source commit, verifier/tool hashes and check results. Logs redact the
keystore password, game key and Mapbox token. Each subprocess group is created for
this run and its leader PID is recorded; only that recorded group is stopped on
interruption, never a process-name pattern. A `.build-lock` prevents simultaneous
Play builds in this worktree. If a machine crash leaves it behind, inspect the owner
PID before removing the lock; do not delete another active build's lock.

### Checks performed

- bundletool validates the AAB structure; only the reviewed base and optional
  install-time Godot asset module are accepted.
- Read actual package/version, non-debuggable status, target SDK, required native
  plugins and merged permissions. Unexpected permissions, Advertising ID,
  screen-capture service and development network overrides fail the build.
- Verify the JAR signature and its exact upload-certificate SHA-256, refusing an
  unsigned bundle, unsigned entries or the debug/another certificate.
- Inspect **every** native ELF `PT_LOAD` segment for power-of-two alignment at least
  16384 and 16KB-congruent offset/address, then check AAB config requests
  `PAGE_ALIGNMENT_16K` and uncompressed native libraries. Native inputs must be the
  reviewed AArch64 ELF64 ABI. This is artifact validation, not physical 16KB-device
  runtime acceptance or Play Console processing evidence.
- Check ZIP CRC/duplicate entries, required Mapbox/LiveKit/Godot libraries and Mapbox
  token presence, baked endpoint/key/version, license index and all referenced texts.
  Assets can reside in base or `assetPackInstallTime`, but not both under the same
  logical name. Account legal-version presence is reported separately: historical
  r1 predates the accounts branch and has no `legal/versions.json`; that absence
  must not be described as submission readiness.

### Inspect an existing artifact without rebuilding

```sh
tools/p0/build_play_aab.sh --check-only ~/Downloads/gensen-0.3.11-play.aab \
  --server https://farm.sensenjoy.cn/preview/p0/v1 \
  --name 0.3.11 --code 2026111401 --bundletool /path/to/bundletool.jar \
  --report /private/evidence/r1-verification.json
```

This mode performs no Godot import/export, private signing-key access, ADB operation,
Downloads copy or version reservation. Its report has `source_commit: null`: the
current checkout is not proof of an existing artifact's source. An explicit report
path must not already exist. The report confirms only the submitted expected
identity and artifact checks, not a new build or user upload.

Focused verification for changes to these tools:

```sh
bash -n tools/p0/build_play_aab.sh
python3 tools/p0/test_play_aab.py -v
```

The tests use synthetic archives/ELF, mocked Java output and temporary export files;
they do not start Godot/ADB, read signing keys or upload anything. Existing real AAB
readback is recorded separately from a newly exported and smoke-tested release.
