# iOS voice native media integration, initial review (2026-11-17)

SGODOT-387 / draft PR #1084, following reviewed transport head `0a648241f42dd0cab76ef9df1869fe19b156cd57`.
This is an implemented, compiled media initial version. It is **not** real-audio, SFU, exported-app or device acceptance.
`VoiceBridge.releaseValidated` remains false; no G3Spike/app integration is enabled by this change.

## Implementation

- Pin LiveKit Swift **2.19.0**, revision `43c1c0870e51eedbfd95b20b1b5c43a767886786`; actual dependencies are
  WebRTC **150.7871.04** (SPM canonical version 150.7871.4) and LiveKit FFI **0.13.1**. The old uniffi 0.1.9 lock
  is replaced. These are the resolved dependencies, not inferred from the earlier SDK evaluation notes.
- `VoiceMediaController` owns synchronous intent/session mutations on MainActor before SDK awaits. Connect, control
  and retired-room cleanup are tracked separately. A replacement waits for the previous room's tasks/disconnect;
  late old callbacks cannot mutate its state. Retired task chains are released after completion.
- `LiveKitVoiceRoom` uses `autoSubscribe=false`, records Block/Mute while connecting, applies publication permissions
  before microphone publication, updates per-identity volume/subscriptions and rebuilds the Swift API's **participant
  SID** allow list from current identities. Reconnect/member/track changes reconcile the current policy.
- Mute/listening/Block silence existing playback locally before async SDK changes. Control failure retires media;
  a missing permission update is not silently accepted. Actual no-leak timing and SFU enforcement still need two-client
  tests; the fake-room test does not establish those properties of LiveKit/WebRTC.
- Permission requests have their own generation; stale callbacks are ignored and background results wait for foreground.
  Monotonic lease expiry, background, active interruption and transport faults retire the room. End of interruption
  or foreground never automatically reuses a grant. A new bridge lifetime clears a stale interruption latch.
- `AppleVoiceAudio` selects PlayAndRecord/voiceChat/defaultToSpeaker/Bluetooth HFP while joined, restores Ambient on
  leave, and temporarily owns audio-session configuration instead of racing LiveKit's automatic category selection.
  iOS 17 permission API and older-system fallback compile against the real SDK. Audio routes, silent switch, game
  audio, echo, interruptions and Bluetooth quality remain device-validation items.
- The bridge connects typed control/event handling, lease timer, lifecycle notifications and transport faults.
  Notification/timer callbacks are generation-checked too. Participant names are capped at 32 characters; snapshots
  use publication mic state and hide speaking/mic indicators for unreceived or blocked remote audio.
- The in-process callback ABI remains. The old prototype JSON media command path is not a fallback around the readiness
  gate; the actual app adapter will use authenticated UDP with the app's existing NativeBridgeKey.

## Verification actually performed

Resource registrations: 大乔 Q1116-15 (through 12:00), Q1116-17 (light interruption regression, released 12:54),
Q1116-19 13:20–13:55 plus its explicitly approved 13:25 iOS-library cross-build extension. Final release before 13:33.

1. **40 controller checks passed** with fake SDK/audio, after an earlier 31-check iteration (not added together).
   Covers delayed connect, replacement teardown, wrong-session controls, lease renew/expiry, pending permission
   cancellation/foreground, per-person controls, policy changes during suspended SDK work, serialized mic intent,
   permission denial, control errors, transport loss and interruption retirement.
2. **3 interruption follow-up checks passed** after the final shutdown-latch fix: no new room during an active
   interruption, no automatic grant reuse at its end, and no stale interruption after bridge stop/start. Earlier
   2-check run is retained but not added. No sockets or audio opened. These are separate runs, not one 43-test run.
3. **Actual SDK host Release build and link passed**, `swift build -c release -j 2`, with the exact checked-in lock.
   First build exposed `Set.isEmpty()` misuse in our SID mapping; changed to the Swift property and rebuilt. Both
   failure and success logs are preserved. This was not a third-party SDK source modification.
4. **Actual SDK arm64 iOS simulator Release library build and link passed**, target `arm64-apple-ios15.0-simulator`
   against iPhoneSimulator26.5.sdk. It compiled the real iOS permission and AVAudioSession branches. No simulator was
   booted, app linked/exported or device installed. Initial link emitted a toolchain sysroot warning; the same link
   arguments with process-local `SDKROOT` set to that simulator SDK produced no warning and the identical library bytes.
5. Readback: iOS library `LC_BUILD_VERSION=IOSSIMULATOR`, min OS 15.0, UUID
   `473ED73E-AF07-38D4-815B-2E2169E31202`, SHA256
   `252e75b8a6f9f9adf8c888bc70c95682db804000d93ba377f62cac918af30bec`.
   Host arm64 library UUID `DD750306-3249-3DB0-8CD9-7B902E4494C0`, SHA256
   `f2513350f6234f492ebf6d4a84bafcad72bd113e39e09887343e74476a4e9a54`.
   Each dSYM UUID matches. These library identities do not identify a future signed iOS app.
6. `git diff --check` passed. Earlier 90 protocol / 11 listener tests were not rerun; their source paths did not change.

Test commands (reserve compiler/build time first):

```sh
bash tools/ios/check_voice_media.sh
bash tools/ios/check_voice_media.sh --interruption-only
swift build --package-path native/voice/apple --scratch-path <isolated-build> \
  --cache-path <verified-cache> --disable-automatic-resolution -c release -j 2
```

For a separately approved simulator-library cross-build, set process-local `SDKROOT` to
`xcrun --sdk iphonesimulator --show-sdk-path` and pass `--triple arm64-apple-ios15.0-simulator --sdk "$SDKROOT"`.
This is a library build, not the Gensen Xcode export or a device execution. The retained initial commands also contain
deprecated SwiftPM `--skip-update`; that warning is not an implementation failure and need not be carried forward.

## Public dependency acquisition

Initial SwiftPM fetch failed on Git HTTP/2/connection errors; a process-local HTTP/1.1 retry resolved source revisions.
FFI's official binary downloaded, while WebRTC's 686,369,195-byte zip timed out. A direct public release download also
timed out and remains a failed/partial acquisition, never used as a dependency.

The same official release asset was then fetched through GitHub's public release API in checked byte ranges (206,
exact Content-Range/length). After full assembly its SHA256 was verified against the dependency package's checksum:

| Artifact | Official checksum, independently verified |
| --- | --- |
| LiveKitWebRTC.xcframework.zip | `3b0aa4bee8d5596d6592b8d75bddc84391769849fd64c04b8e13c9e77ce6a82b` |
| RustLiveKitFFI.xcframework.zip | `9c6fca694df24f1206897c5787c001120c27e03a2b28688af76c83ea79a45805` |

Verified archives were placed in a task-local SwiftPM cache. The final build fetched WebRTC **from this cache**;
no SDK/dependency manifest or source patch was used, no TLS/global proxy setting changed, and no user password was
requested. Dependency download errors and final checksum records remain in the evidence archive. Both binaries
contain the needed simulator/device slices; slicing availability is not evidence of device audio working.

## Cleanup and next gates

Compiler/build processes exited; Q1116-19 PIDs 80839/82238/82974/83824/86204 are gone. Public downloads are finished.
No microphone, LiveKit room, UDP listener, Godot, simulator, test service or phone was opened. The isolated verified
SDK/cache and library artifacts remain for reproducibility. Logs contain no grants, user credentials or audio.

Next: review this head; integrate G3Spike/NativeBridgeKey/SPM sources and permission strings idempotently; build actual
iOS Release app, then verify UDP failure/reconnect/teardown and two-client SFU Block/Mute/audio across iOS/Android.
Verify audio interruptions/routes/speaker/headphones/silent switch and game audio on approved devices, and audit
microphone/privacy/encryption declarations before enabling supported capabilities. This initial code is not permission
to enable or ship voice. The first-release decision remains 11-21; 0.3.11 normal release stays paused.
