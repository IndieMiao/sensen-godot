# Apple voice bridge (SGODOT-387, implementation in progress)

## 2026-11-16: first native transport segment

`VoiceWire.swift`, `VoiceEventDelivery.swift` and `VoiceDatagramServer.swift` implement the control transport for
Godot's existing `VoiceBackendIOS` (loopback UDP 46467, protocol v1.2). The native app will pass the same 64-character
launch key produced by `NativeBridgeKey` into this transport; the transport never generates a second key.

- Decode every command only after checking the final `|key=` field; malformed/unauthenticated datagrams get no
  reply, no command and no event-client replacement. New untrusted connections are bounded and expire after 1 s.
- Keep one authenticated event client; retry failed listeners after 2 s, detach callbacks on stop/replacement, and
  report transport faults to the media owner. The owner must close its room/microphone on these faults.
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

This first segment is deliberately **not wired into G3Spike or an exported application**. The legacy media bridge
below still lacks the complete iOS Block/audio/packaging contract. Next: integrate the typed commands and event
delivery with LiveKit 2.19.0, default-off subscriptions and both Block directions; then add AVAudioSession,
permission/background handling and the launch-key/bootstrap/SPM/plist injection. Do not claim `supported=true` or
real iOS voice from this transport alone.

## Existing media prototype (not yet integrated with the transport)

`VoiceBridge.swift` implements the shared JSON command/event protocol using LiveKit Swift 2.17.0, with microphone permission, main-actor room lifecycle, serialized microphone changes, listening/speaker control and a native lease watchdog. Callback registration/unregistration is synchronous so a future Godot adapter can safely detach.

The C ABI exports `sensen_voice_command` and `sensen_voice_set_event_callback`. A Godot iOS adapter exposing `GodotVoice`, main-thread event draining, export packaging, microphone usage description and real audio/device testing are still required. This package alone does not make the game support iOS voice.

Build with `swift build --package-path native/voice/apple`. `SENSEN_LIVEKIT_SWIFT_SOURCE` optionally points to a local checkout. On 2026-09-16 macOS and arm64 iOS Simulator compilation passed using official SDK sources and XCFramework archives verified against upstream SHA-256 checksums. GitHub release download routing required fetching archives through the GitHub releases API and using local package dependencies for the build; those temporary dependency edits are under ignored output, not the shipped package.

No API secret belongs in this library. It accepts only short-lived per-player grants from the game backend. Future UI must call `capabilities()` and keep unsupported platforms disabled until the Godot adapter is installed and validated.
