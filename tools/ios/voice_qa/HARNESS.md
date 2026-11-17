# Frozen media harness and unsigned build chain (2026-11-18)

This extends the reviewed b8cf9035a native-only QA overlay. Production native sources and #1084 remain unchanged.
It is an isolated native voice test, not full P0 account/game acceptance. User instructions are in USER-STEPS-1118.md.

## Inputs

The operator-approved scope is supplied as a file, never fetched or guessed by the app. The current reviewed service
is devserver-isolated-387 / p0-ios-voice-qa-1118. The broker is HTTPS on the exact same authority as the scope's WSS
origin. A=ios-a/qa-ios-a, B=android-b/qa-android-b; C is disabled. JWT=60s, server lease=20000ms, heartbeat=4500ms.
Private role-bound test capability codes are typed at the device, held in memory and never placed in a PCK/report.

The seven-field scope is frozen separately from these sources. Its raw-file SHA and canonical content SHA are distinct;
the native export and harness compare the canonical content SHA. Changing origin/issuer/scope requires a new prepared
export/harness and review. TLS, no-redirect behavior and the isolated service/issuer are not established merely by an
origin string; operator evidence and device media reachability remain required.

## Harness

- No game autoloads or production API. The exact production VoiceBackendIOS and AppleSignIn key reader are copied into
  a minimal project; native UDP/controller/SDK behavior is preserved. This does not reuse the full PartyVoiceSession
  account/game glue, and does not count as that integration's acceptance.
- The QA G3Spike starts only VoiceIOS; no map/login/notification bridge is started. NativeBridgeKey is still the real
  provider, initialized by the explicit native Start action. A yellow native panel stays visible.
- The native panel writes a non-secret armed/expiry status to the QA app's Documents. This file only controls harness
  UI/readiness; the native permit remains authoritative even if the UI file is modified. Stop/expiry needs app restart.
- Join requests microphone permission before any broker grant. HTTP uses role-bound Bearer code, JSON <=16KiB,
  timeout8s and zero redirects. Late grants after Leave/background are released without native connect. There is no
  automatic rejoin after background; a paused/in-flight heartbeat cannot renew after Pause.
- Native participant events drive per-peer Mute/Block; both subscribe and publish-allowed are updated. Provider ids
  remain in memory. Controls are Join/Leave/Mic/Listen/selected-peer Mute and Block/settings/lease renewal.
- iOS uses the real UDP backend. The same source can use an explicitly prepared Android GodotVoice QA package with
  client android-b and its own manual Start; no Android counterpart package/device acceptance is claimed in this build.
- validation_only builds cannot request permission/grants. Tests use a fake backend/transport; their entry script is
  not copied into the export project. The main packaged scene was smoke-run on macOS with Dummy audio/no native backend.

## Native versus server expiry evidence

The team-only Test native expiry (5s) control first obtains a fresh server20s heartbeat, then stops renewal and sends
only a native5s lease. A failed/stale heartbeat does not start this case. This separates local expiry from the server's
normal20s removal; client Leave after native expiry is a later cleanup, not evidence that the server expired first.

The QA copy adds native uptime/wall timestamps to outgoing events. A VOICE_EXPIRED disconnected event is emitted
**after** the production controller's synchronous retirement barrier returned; its timestamp is an observation upper
bound, not a claim to measure the exact capture-frame stop instant. Server expiry/removal timestamps are recorded
separately. Compare causal order and clock uncertainty, not unrelated device monotonic clocks.

Harness evidence contains only allowlisted event names/codes, numeric clocks and microphone/listening booleans.
Frequent participants snapshots are not written. Each app run has its own bounded event file. No capability code,
JWT, launch key, raw event body, participant names or PCM is persisted. It does not prove acoustic silence, buffering
bounds or SFU behavior without the independent real peer observations in the21-case plan.

## Local-network purpose

Only the QA copy gains NSLocalNetworkUsageDescription in English and Simplified Chinese because its current media
path is devserver LAN TCP17981/UDP17982. No Bonjour discovery, multicast entitlement, location request, DNS/route/TLS
change is added. The production q319 microphone text and production plist remain unchanged. A public WSS tunnel
carries signalling, not media; being able to reach it does not establish LAN media connectivity.

## Prepare / verify / build

1. Run prepare.py into a new native QA export with the approved scope (still no game PCK or signing).
2. Run prepare_harness.py --qa-export <export> --output <new-harness> --broker-origin <same-HTTPS-authority>.
   Use --client android-b only for a separately prepared Android counterpart. --validation-only disables networking.
3. In an authorized resource window, import the small project using the private ADB procedure. Run the external
   harness/tests.gd with Godot -s (fake transport). Never copy that test entry into the App project.
4. export_pck.py --harness <harness> --qa-export <export> runs the fixed export-pack command and records a receipt
   binding the frozen source manifest, scope and PCK SHA. It rejects changed/extra source files.
5. build_unsigned.py --export <export> --harness <harness> --pck <export>/sensen.pck --derived <private-dd>
   --packages <verified-SPM-cache> --cache <verified-package-cache> prints a plan; --run executes it in a reserved window.
   It requires the PCK receipt, exact native bootstrap/policy and source hashes; a substituted game PCK is refused.

The build command always uses Release/iphoneos/arm64, CODE_SIGNING_ALLOWED=NO, CODE_SIGNING_REQUIRED=NO and empty
CODE_SIGN_IDENTITY. It has no provisioning/update, archive, export/upload or device-install argument. Build logs are
checked for signing commands and output for embedded.mobileprovision. No Apple registration is performed by this tool.
The copied SDK archives were referenced from previously verified local inputs; those library bytes were not edited.

Actual 00:17–00:41 Q1117-28 results: Python19/19; Godot18 final checks,0 failures (fake transport); actual QA PCK export;
actual arm64 iPhoneOS Release App build; packed main3-frame host smoke with Dummy audio and no backend, no script error.
App/PCK/scope/English+Chinese mic/local-network purpose/three voice frameworks were read back. codesign -dv reports
code object is not signed at all; no profile/signing command, no install, simulator, microphone or SFU session.

Executable SHA abe0af4f1e856a6ef9f625af341f406f467e98976883d05b222818942c6bd17d;
PCK SHA 085b49db261c4b88e4a634125847fbbf9aebefbcb1776338239a58b84bfd42bb;
executable/dSYM UUID BECB9F00-544D-3091-8338-9BEE30BEE67B (arm64).
Evidence: /Volumes/ACASIS/tmp/yase-ios-harness-1117. All recorded command/ADB PIDs exited;5085 is free.

All real media/device cases remain NOT_RUN. The user registration choice, signing/provisioning and device execution
are separate authorized steps and require their own resource window. GeoFarm native issues retain priority.

Final evidence-only follow-up: absent native error/reason fields are omitted rather than synthesized as REQUEST_FAILED,
and permission granted is retained as a Boolean. Two targeted checks brought the final harness run to18 (not added
to the initial16). Q1117-29 covered the re-export/unsigned resource rebuild. The final extra3-frame host/Dummy smoke
finished at00:58:37, about37 seconds after the00:58 deadline; this overrun was reported to大乔, not rewritten as
on-time. All PIDs exited. Native/SDK code and executable SHA/UUID remained unchanged; the final PCK SHA above changed.
