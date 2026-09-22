# Apple voice bridge (future iOS milestone)

`VoiceBridge.swift` implements the shared JSON command/event protocol using LiveKit Swift 2.17.0, with microphone permission, main-actor room lifecycle, serialized microphone changes, listening/speaker control and a native lease watchdog. Callback registration/unregistration is synchronous so a future Godot adapter can safely detach.

The C ABI exports `sensen_voice_command` and `sensen_voice_set_event_callback`. A Godot iOS adapter exposing `GodotVoice`, main-thread event draining, export packaging, microphone usage description and real audio/device testing are still required. This package alone does not make the game support iOS voice.

Build with `swift build --package-path native/voice/apple`. `SENSEN_LIVEKIT_SWIFT_SOURCE` optionally points to a local checkout. On 2026-09-16 macOS and arm64 iOS Simulator compilation passed using official SDK sources and XCFramework archives verified against upstream SHA-256 checksums. GitHub release download routing required fetching archives through the GitHub releases API and using local package dependencies for the build; those temporary dependency edits are under ignored output, not the shipped package.

No API secret belongs in this library. It accepts only short-lived per-player grants from the game backend. Future UI must call `capabilities()` and keep unsupported platforms disabled until the Godot adapter is installed and validated.
