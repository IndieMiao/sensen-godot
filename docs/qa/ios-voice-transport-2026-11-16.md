# iOS voice native transport, first segment (2026-11-16)

SGODOT-387. Base `99a853f7c` (`farm-dev`); isolated branch `feat/387-ios-voice-native`.
This segment implements the native control transport. It does not enable iOS voice in an exported app.

## Implemented

- `VoiceWire`: all protocol-v1.2 commands, final launch-key authentication before dispatch, strict field counts,
  32 KiB input bound, UTF-8/control-character checks, finite fractional volume clamped to 0–1 and leases to 0–20s.
  It accepts `ws` for isolated development grants and `wss` for live grants, never credentials in the URL authority.
- `VoiceEventDelivery`: snapshots with ID 0; reliable events with process-wide monotonic IDs; exact-packet retries
  every 250ms (initial send plus at most 20 retries); ACK/deduplication-compatible IDs, 64-event bound, explicit
  expiry/overflow fault, no burst after a suspended timer. Clearing/recreating a room queue does not reset IDs.
- `VoiceDatagramServer`: loopback-only 46467 listener, bounded unauthenticated peers with a 1s timeout, authenticated
  event-destination selection, silent invalid-packet drop, listener retry, stop/deinit cleanup and typed fault
  callbacks for the media owner. An invalid packet from the current socket neither executes a command nor
  disconnects its room. Capabilities default to unsupported; media commands/events require the explicit readiness gate.

The existing `VoiceBridge.swift` media prototype and LiveKit 2.17.0 package pin are **not** claimed as complete or
upgraded by this patch. The new transport is not instantiated by G3Spike or the app yet. Its fault callback will need
to close the media session; the transport alone cannot close a microphone it does not own.

## Verification actually performed

Resource window: 大乔 Q1116-11, 15:39–15:50 CST, compiler-only scope. Final run ended before 15:47:08.
Command: `bash tools/ios/check_voice_transport.sh` (macOS, Xcode SDKs installed locally).

- Standalone protocol/delivery checks: **90 passed, 0 failed**, exit 0. No sockets, audio, SDK login or devices opened.
- Swift 5 language mode, warnings as errors: host Network adapter typecheck passed.
- Same transport files typechecked against `iphonesimulator`, target `arm64-apple-ios15.0-simulator`: passed.
- Same transport files typechecked against `iphoneos`, target `arm64-apple-ios15.0`: passed.
- `git diff --check`: passed. Test output binaries are in a per-run temporary directory removed by the shell trap.

Checks cover missing/wrong/empty/trailing keys, malformed UTF-8/commands/booleans, size/number bounds, all command
shapes, fractional volume, exact retry bytes/timing, duplicate/unknown ACKs, snapshot JSON containing `|`, event
number continuity across queue recreation, retry exhaustion, queue overflow, suspension and unsupported capabilities.
The Network adapter is **typechecked only**: real UDP bind/reconnect/authenticated destination and lifecycle tests
remain pending an isolated runtime window; do not infer them from decoder unit checks.

The first successful host-only run and final SDK-inclusive run are not added together: the final count is 90.
Runner PIDs 29665 and 30257 exited; no compiler/check process remains. No Godot, Xcode build, emulator, phone,
test service, LiveKit connection, production setting or deployment was used.

## Next segment and release gate

1. Resolve/pin and compile LiveKit Swift 2.19.0 in the isolated build; implement typed command integration,
   `autoSubscribe=false`, per-identity volume/subscription and publication permissions, including reconnect/block races.
2. Serial microphone intent, permission generation/late callbacks, monotonic lease watchdog and session replacement;
   AVAudioSession enter/leave, interruption and background disconnect. Events must match the Android publication-based
   microphone/audibility semantics and limit participant display names to 32 characters.
3. G3Spike/NativeBridgeKey integration, idempotent SPM/source injection, microphone localization and the encryption
   declaration audit. Only expose supported capabilities after the full backend contract is implemented and validated.
4. Real Release app/UDP tests, Android–iOS audio/block tests and TestFlight/device evidence are separate gates.

No runtime voice acceptance, Release executable build, SDK integration, device performance or release is claimed.
The 11-21 first-release decision remains with the project director; normal 0.3.11 release remains paused.
