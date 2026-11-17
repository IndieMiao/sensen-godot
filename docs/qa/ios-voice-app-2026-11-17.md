# SGODOT-387 iOS voice App integration — 2026-11-17

Author: 亚瑟 / virtual_user_id 0c011aa8-80fc-456a-835a-b5afc9f3ea72

## Scope

PR #1084 extends the reviewed 076537f90 media implementation with G3Spike → VoiceIOS → VoiceBridge startup, using the existing NativeBridgeKey. The Godot export injector snapshots the fixed LiveKit 2.19.0 Swift package and registers its product in the copied app project. Voice capability remains false.

The exact q319 microphone purpose is installed in the app plist and English/Simplified Chinese localization. Store configuration preserves those keys and any explicit encryption Boolean. The submission owner still needs to confirm third-party WebRTC export classification, country availability and any App Store Connect documents; the isolated QA false is not a submission approval.

## Validation ledger

- Python injector tests: 11 passed; exact package snapshot, idempotence, shared key, localization and explicit-encryption preservation, invalid input rejection.
- Actual copied Xcode project: Python injection and byte idempotence passed.
- Actual Release app build passed with Xcode 26.5 SDK, deployment target iOS 15, x86_64; runtime iOS 18.6. Godot reports 4.7.2 stable, release=true/debug=false.
- The final probe passed 20 assertions (including preflight and plist checks, not 20 separate UDP scenarios): production GDScript receives all-disabled iOS CAPS; missing/empty/wrong/non-final key and invalid UTF-8 get no reply; the valid key receives disabled CAPS; terminating the app frees 46467; relaunch rotates the key, rejects the old key and accepts the new one. No unsolicited media event was seen.
- Exact source snapshot, app bundle/version, English/Simplified Chinese microphone/localization, explicit encryption Boolean, dynamic frameworks, architecture and executable/dSYM UUID were read back. The actual copied project's final injection remains byte-idempotent.
- Screenshot reviewed: native bridge responded, voice capability disabled. This is not a microphone permission dialog.
- Previous media/controller/retirement/library checks are retained from 387/6e0e6675 and not rerun.

## Runtime scope and limitations

The completed test used app.gensen.voiceqa, a copied Xcode app with the actual native bootstrap and pinned SDKs, and a minimal offline PCK containing the production VoiceBackendIOS and AppleSignIn bridge-key reader. It does not contain the complete Gensen game or account flow. The existing engine simulator archive is x86_64; only its incorrect architecture metadata is corrected in the QA copy. One iOS 18.6 simulator, no physical device, LiveKit room, media transmission or store upload.

## Remaining before the 11-21 decision

1. Cross review the new App integration/export injector changes; actual isolated Release/UDP is now passed.
2. Signed Release/TestFlight/device candidate, microphone purpose dialogs in both languages, deny/settings recovery, audio route/headphones/speaker/interruption/game-audio checks.
3. Real SFU two-client iOS↔Android tests: bidirectional Block/Mute/publish permissions, reconnection and no leaked audio after lease expiry/background/fault.
4. q319 visual evidence to SGODOT-302, privacy/audio and export-classification review.
5. Final release gate decision stays with 奕星. Keep releaseValidated=false until the required evidence exists; passing an unsupported-CAPS probe cannot justify enabling voice.

The iOS account-flow plan is already on SGODOT-488 (8ac5f8ae); account candidate execution remains separate, pending the merged PR-A iOS candidate and approved controlled inputs/real provider accounts.

## Actual artifacts

- Bundle: app.gensen.voiceqa / 0.3.11 (1117), unsigned simulator QA only.
- Executable SHA-256: d1422cfff452709a210a41d5cd14750d2351e75dcfc29a95a50586681f20683d.
- Executable and dSYM UUID: 7C50F352-C26B-3579-BF58-436F675580DF (x86_64).
- Probe PCK SHA-256: 8ec7744862ea600bfa84be40497414b9da820da1c338e2c3a31de80228a39293.
- Embedded SensenVoiceApple SHA-256: 2acabac6a899dead6c1d7cb3143acef11e7d07dd9000957ba8156f059dc5672a. LiveKitWebRTC and RustLiveKitFFI are also present; all hashes and SPM pins are in the evidence.
- First/second native CAPS observed after 763/805 ms of probe polling. These are startup observations, not a performance acceptance criterion.
- Full logs, scripts, exact source hashes and JSON: /Volumes/ACASIS/tmp/yase-ios-integration-1117/. Review evidence is attached to SGODOT-387, https://plane.sensenjoy.cn/zili/browse/SGODOT-387/.

## Failures retained and correction

1. Probe import passed, but the helper mistook TCP TIME_WAIT after private ADB shutdown for an active listener. No listener/PID remained. The helper now permits TIME_WAIT while still refusing an occupied listener; import was not repeated.
2. Xcode rejected an explicitly x86_64 device destination because its destination list only exposed arm64. Building the generic Simulator destination with ARCHS=x86_64 passed, retaining the existing engine library.
3. Actual app readback exposed a real injector defect: SensenVoiceApple was linked but not embedded. The injector now adds the dynamic product to Embed Frameworks with CodeSignOnCopy/RemoveHeadersOnCopy. Incremental Release build and final app readback passed. This fixes the export path, not just the QA app by hand.
4. The simulator was booted explicitly with --arch=x86_64. Launches with stdout/stderr redirection were still denied by SpringBoard; normal simctl launch of the same corrected app passed twice. No code signature or executable was changed to obtain the pass. The denial's deeper tool/runtime cause is not claimed to be resolved.

Earlier failures remain under attempt-1 through attempt-4 and are not counted as passed runs. The successful run reused the already built app and exported PCK.

## Resource release

Q1117-06 explicitly opened at 16:36 after GeoFarm smoke; all work finished and was reported released at 16:49. Own simulator was shutdown/deleted; 5085 and 46467 are free; recorded command PIDs and app PIDs 88423/88608 are absent. No room/audio/device/store upload/production operation occurred. No microphone prompt was requested. The resource permission is ended and cannot be reused.
