# Native voice retirement / transmit barrier (2026-11-17)

PR #1084, review 6939837339 / SGODOT-387 9a6a5545. Fixes the P1 in media head
`8b69c8bc06e3f78862bda4b9bd87a32696d5ee22`. Capability remains false; this is not an SFU/device audio acceptance.

## Defect and correction

Previously, `finish` cleared the local session, cancelled Tasks and muted remote playback, but did not call
`room.disconnect()` until all connect/control awaits completed. An already-published microphone could therefore
continue while a control await was stuck. Task cancellation and a `disconnected` event do not establish a media stop.

The fix separates three operations:

1. **Synchronous privacy barrier / permanent driver retirement.** `VoiceMediaRoom.retire()` closes the preinstalled
   capture frame gate, removes event delivery and retires the driver before any await. It does not call an SDK
   worker API or traverse remote tracks. `VoiceCaptureGate` uses a short in-memory lock shared with the capture
   processing callback; subsequent microphone frames are zeroed in place before encoding/network transmission.
2. **Immediate independent SDK disconnect.** Start room disconnect in a separate Task without waiting for the
   stuck connect/control Task. That task is allowed to clean up and cancel its own SDK internals.
3. **Full reclamation barrier.** Continue waiting for old connect/control/disconnect completion before opening a
   replacement or transferring audio-session ownership. Old post-await driver paths check permanent retirement;
   late connect/mic completion disconnects that old room and cannot reopen its capture gate. Old callbacks are ignored.

SDK basis: LiveKit 2.19.0's `AudioCustomProcessingDelegate` is explicitly the in-place processing path before network
send/playout. `AudioManager.capturePostProcessingDelegate` is installed before connecting/publishing; its target
remains attached and closed until old operations drain. `LiveKitCaptureGate` zeros `LKAudioBuffer`'s current channel
frames only. It does not copy, record, retain, log or send PCM anywhere else.

We did **not** use `AudioManager.setEngineAvailability` or `isMicrophoneMuted` as the urgent barrier: the SDK documents
that those synchronous APIs wait for WebRTC's worker and may themselves block if it stalls. The capture gate avoids
that dependency. It cannot retract frames already processed or in network buffers, nor claim that every silent
transport packet ceases instantly. Actual hardware/publication release is the independent disconnect's responsibility.

The app has one LiveKit voice owner. A new driver refuses to overwrite a foreign/live capture processor; only a
retired processor may be replaced after the reclamation barrier. If stop cannot be confirmed (including a replaced
processor), report `VOICE_STOP_FAILED`, do not report successful disconnected, and refuse replacement connections.
An old driver's repeated retirement does not mutate the new owner's gate.

## Verification actually performed

大乔 Q1116-20, explicitly advanced to 14:00–14:20; released at 14:07. No audio/socket/room/device was opened.

- New **32/32** retirement checks passed. Fakes use the same `VoiceTransmitFence` and `VoiceCaptureGate` as production.
  For each of lease expiry, background and transport failure: establish mic-on, suspend permissions/subscriptions,
  trigger finish, then **before resuming the old gate** assert outgoing content suppressed and driver retired.
  Verify independent disconnect begins while that gate is still held; then resume and verify no revival.
- Covers a mic-on await completing late after replacement, stale reconnect/lease/mic commands, new room waiting
  for complete old teardown, old repeat-retirement not stopping the new room, normal exactly-once room/audio cleanup,
  explicit stop failure/replacement refusal, and synthetic frame zeroing/default-closed/non-reopen behavior.
- Negative control: a temporary controller copy assumes stopped without calling `retire`. **9 of 32 assertions fail**,
  exit 1 expected. This tests the regression's sensitivity; it is not a real SFU reproduction or an old binary test.
- Related controller regression: **43/43** passed after the protocol/teardown changes. Do not add earlier 40/3 results
  to this new count. The independent 90 wire/11 listener suites were unchanged and not rerun.
- Real pinned SDK incremental **host Release** and **arm64 iOS simulator Release library** compilation/linking passed
  with `-j 2`, from the already verified local cache. No SDK source or dependency checksum changed.
- iOS library: `IOSSIMULATOR`, minimum 15.0, UUID `FAAE8929-BB8B-314F-B324-EE9473F99536`, SHA256
  `d8dce0a1c254ea4dc1ac10793e7dae73244a1e897b62eab684fb0397662b655b`.
  Host UUID `AA807D36-265B-3890-9F38-D4A112B9A6C8`, SHA256
  `2c62f87084e80962c3ec6a717ce8942f48b845944546d0aa3d5ec7bfa5a26443`. Matching dSYM UUIDs verified.
- The known SwiftPM simulator link sysroot warning was retained; same final link with explicit process-local SDKROOT
  emitted no warning. Initial negative-control compile used a constant true and hit warnings-as-errors dead-code
  diagnostics; the fixture was corrected to a runtime assumption, then the actual red/green runs were performed.
  That fixture setup failure is not counted as the intended negative test.
- All recorded PIDs exited (563/778/790/796/831/1398/2001/2751); temporary fixture/binaries removed. No new dependencies
  were downloaded, and no global proxy/TLS/device/runtime setting was changed. `git diff --check` passed.

Commands, after resource registration:

```sh
bash tools/ios/check_voice_media.sh --retirement-only
bash tools/ios/check_voice_media.sh
```

Remaining: real UDP/media integration, two-client SFU silence and Block tests (including timing during reconnect),
device audio/route/background/interruptions, G3Spike/SPM/plist injection and a signed Release app. Keep
`releaseValidated=false`, draft/hold status and the normal-release pause until those separate gates are met.
