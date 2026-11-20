# Apple voice bridge (SGODOT-387, implementation in progress)

## 2026-11-16: first native transport segment

`VoiceWire.swift`, `VoiceEventDelivery.swift` and `VoiceDatagramServer.swift` implement the control transport for
Godot's existing `VoiceBackendIOS` (loopback UDP 46467, protocol v1.2). The native app will pass the same 64-character
launch key produced by `NativeBridgeKey` into this transport; the transport never generates a second key.

- Decode every command only after checking the final `|key=` field; malformed/unauthenticated datagrams get no
  reply, no command and no event-client replacement. New untrusted connections are bounded and expire after 1 s.
- Keep one authenticated event client; retry failed listeners after 2 s, detach callbacks on stop/replacement, and
  report transport faults to the media owner. The owner must close its room/microphone on these faults.
  The queued new-connection callback also checks its originating listener on MainActor; peers delivered after
  stop/start or during listener-retry wait are cancelled before registration, even when `running` is true.
- Snapshots use event ID 0. Permission/connected/reconnecting/disconnected/error use a process-lifetime counter,
  including across bridge/outbox recreation; ACK removes only that event. Retry exact bytes at 250 ms, at most 20
  retransmissions after the initial send. Bound pending events to 64, surface exhaustion/expiry as a fault, and do
  not emit a catch-up burst after suspension. Session teardown clears pending events, never the counter.
- Capabilities default to unsupported and media commands/events remain gated. `mediaReady` is an implementation
  readiness gate, not room connection state. It may be enabled only after per-participant subscription, volume,
  publication permissions and audio lifecycle are integrated and verified.

Run `bash tools/ios/check_voice_transport.sh` from the repository root. It compiles/runs standalone Foundation
protocol checks, then typechecks the Network adapter against host, iOS simulator and iOS device SDKs. It does **not**
start a listener, resolve LiveKit, open audio, build an app or use a device. Reserve compiler time with the resource
coordinator. The final 11-16 results and limitations are in `docs/qa/ios-voice-transport-2026-11-16.md`.
`--listener-only` runs just the delayed-listener handoff regression and SDK typechecks, without repeating the
unchanged 90 decoder/outbox checks.

The bridge is deliberately **not wired into G3Spike or an exported application**. `VoiceBridge.releaseValidated`
stays false. App integration must pass `NativeBridgeKey.value` to `VoiceBridge.shared.start(launchKey:)`, then
complete Release/UDP/audio/Block validation and the SPM/plist/permission injection before enabling capabilities.
Do not infer `supported=true` or real iOS voice from controller tests.

## 2026-11-17: media controller and LiveKit 2.19 integration

`VoiceMediaController` owns synchronous intent/session changes on MainActor. A replacement room waits for retired
connect/control tasks and SDK disconnect, preventing a late completion or audio-session teardown from affecting
the replacement. Leases use monotonic time. Background, interruption and transport faults retire the room; returning
to foreground or the end of an interruption never reuses an old grant. Pending permission replies are tied to a
request generation, and a valid result waits until foreground before delivery.

`LiveKitVoiceRoom` connects with `autoSubscribe=false`. Subscription and volume controls use the peer identity;
Swift's publication-permission API requires current participant SIDs, rebuilt from identity policies on membership
changes/reconnect. Policies are applied before microphone publication. Block updates silence existing playback
immediately, then reconcile SDK subscriptions; control errors terminate the room rather than silently keep media.
Track arrival/mute/subscription events update Android-shaped snapshots. Actual race-free silence/SFU behavior
still requires two-client real-audio validation; fake SDK tests are not media/SFU evidence.

Retirement closes a preinstalled capture-postprocessing gate synchronously, before waiting for any SDK operation.
It zeros subsequent outgoing microphone frames in place (no copy/retention/logging), and marks the driver retired.
An independent disconnect task starts immediately; full task/room reclamation is a separate barrier that a replacement
must await. The gate stays attached and closed while a late mic/connect operation drains, and driver guards reject
late operations/callbacks. This stops microphone content without relying on a potentially blocked SDK worker; it
does not claim to retract already-processed/network-buffered frames or to stop all silent transport packets instantly.
An unexpected capture-processor owner or an unconfirmed gate stop fails closed instead of reporting disconnect success.

`AppleVoiceAudio` uses iOS 17's permission API with an older-system fallback, PlayAndRecord/voiceChat/defaultToSpeaker
while joined, and Ambient on leave. It temporarily disables LiveKit's automatic audio-session configuration to
avoid two category owners. Route/accessory/interruption and Godot game-audio behavior need actual Release devices.

`bash tools/ios/check_voice_media.sh` runs deterministic controller tests with fake SDK/audio implementations and
explicitly suspended async operations. `--interruption-only` runs just the interruption follow-up cases. Neither opens
audio, sockets or devices. Build the actual SDK separately with `swift build --package-path native/voice/apple -j 2`;
`SENSEN_LIVEKIT_SWIFT_SOURCE` optionally points to a verified local SDK checkout. Public dependency-download failures
are not a reason to alter global proxy/TLS settings or to substitute unverified binaries.

The pinned 2.19.0 revision is `43c1c0870e51eedbfd95b20b1b5c43a767886786`. Its actual dependencies are WebRTC
150.7871.04 (SPM canonical version 150.7871.4) and LiveKit FFI 0.13.1; the old 2.17/uniffi 0.1.9 lock is replaced.
No API secret belongs in this library. Only short-lived backend grants remain in memory. The legacy callback ABI
remains for in-process consumers, but unvalidated legacy media commands do not bypass the UDP readiness gate.
