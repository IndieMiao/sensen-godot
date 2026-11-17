# Isolated iOS media QA overlay (SGODOT-387)

This branch contains a native QA patch and release exclusion checks. It does not enable the production bridge,
register an Apple identifier, sign a package, start a service/device, or upload to TestFlight. Do not merge the QA
preparation/templates into farm-dev, PR-A or #1084. The reviewed production baseline is
`0cce63969476315ef3ae8be80cb27c710fcfeb53`; its native source and bootstrap stay byte-identical in the repository.

## Fixed environment and runtime scope

- Planned environment: **devserver-isolated-387**, a separate environment on devserver. No US production host,
  production LiveKit project/namespace or existing GeoFarm service is reused or modified.
- Namespace: **p0-ios-voice-qa-1118**. Use separately created test identities and a separate issuer secret held by
  the test-service operator. No issuer secret or JWT is embedded in the app or included in evidence.
- The actual self-hosted WSS origin, issuer's SHA256 and a maximum 24-hour scope must be frozen with the operator
  before execution. No origin is guessed here, no DNS/TLS settings are changed, and `*.livekit.cloud` is rejected. Hosts must use canonical ASCII DNS/IP names without a trailing dot or empty label; Unicode separators and literal IPv6 hosts are not accepted by this QA scope.
  The origin must terminate TLS normally and not redirect to another service. This preparation is not approval
  to create/start that environment; the current authorization is code/docs only.
- Scope JSON fields (no extra fields): `schema:1`, `environment`, `namespace`, `media_origin`, `issuer_digest`,
  `not_before` and `expires_at` (Unix seconds). `issuer_digest` is lowercase SHA256 of the isolated LiveKit issuer
  identifier, not its signing secret. Expiry must be at most 24 hours after not_before; no all-zero placeholder.
- Scope inputs must be reviewed against the actual isolated service by its operator. A string naming devserver
  does not prove host isolation. The runtime restrictions protect against accidental wrong grants/destinations;
  they are not a sandbox against an operator who rewrites the QA build or deliberately supplies false inputs.

## Preparation

First prepare a clean, copied Xcode export using the normal production injectors. This tool requires the exact
reviewed package and bootstrap snapshot; it refuses an already QA-marked/modified source or symlinked source.
Then, **after the source/endpoint scope is approved**, prepare a new destination:

```sh
python3 tools/ios/voice_qa/prepare.py \
  --source-project /absolute/clean-copy/sensen.xcodeproj \
  --output /absolute/new-native-qa-copy \
  --scope /absolute/reviewed-qa-scope.json
```

This is a source-preparation command only. It applies the patch to the copy, adds `VoiceQAPolicy.swift`, replaces
the copy's bootstrap, adds an explicit QA plist dictionary and marker manifest, and records hashes/patch text.
The production `releaseValidated = false` declaration is preserved even in the copy; QA readiness is a separate,
scoped in-memory permit. Source repository files are never patched by the preparation command.

The output deliberately **does not contain a game PCK**, provisioning files, entitlements or TestFlight export
options. Signing is disabled in its build settings. A separately reviewed QA harness/PCK and fresh identity/data
configuration are still required before an App build. Do not drop the normal game PCK into it: that would allow
unreviewed game/account endpoints before the QA banner appears. This patch does not bypass account/age/consent
validation, and a native QA harness is not complete-game acceptance. No executable QA App is claimed here.

## Runtime behavior of the QA copy

- `VoiceIOS.setup` only installs a persistent yellow QA panel. It does not start the UDP bridge, request permission,
  activate audio, fetch a grant or contact an endpoint. The explicit **Start media QA** button is one-shot per launch.
- Both the bootstrap and package require bundle `app.gensen.voiceqa`; package scope validation also checks the
  fixed environment/namespace, exact origin, issuer digest and wall-clock validity. A permit lasts at most ten
  minutes on a monotonic clock. An expired permit calls the existing stop/retirement path on the bridge watchdog.
- Once manually armed, the same production UDP decoder, media controller, driver and SDK are used. CONNECT must
  match the frozen WSS origin and a short-lived token whose issuer, room prefix and join claim match the scope.
  An out-of-scope CONNECT stops the QA bridge. The legacy in-process ABI stays closed.
- JWT payload checks are only additional restrictions; **they do not verify a signature or issue authorization**.
  The isolated SFU must verify the actual JWT signature with its own key. Policy test tokens intentionally have
  fake signatures and must never be presented as successful live authentication.
- **Stop QA**/expiry retires media and closes transport. The panel requires a restart for another run so launch
  key and Godot capability cache are fresh. Background/interruption still use the unchanged controller rules;
  foreground cannot reuse an old room/grant through the controller.
- No raw audio is copied/recorded, and neither token nor URL credentials are printed. Existing permission UI only
  appears after the approved QA harness sends the production permission command.

## Release exclusion: actual entry point and proof

The first commit is separable release-only protection: `check_voice_release.py`, its tests, the call at the start
of `inject_voice.py`, and CI. It does not depend on the QA template/preparer. It can be reviewed/taken separately
by release owners; **it has not been installed in farm-dev or shared release tools by this task**.

- CI checks the production source gate is literal false and rejects known QA source/bootstrap/package markers.
- The normal `inject_voice.py` entry checks a copied export **before overwriting any file**, so running normal
  preparation over a QA copy cannot silently scrub/re-sign it.
- Before archive, check the actual copied export; before distribution/upload, check the extracted actual app:

```sh
python3 tools/ios/check_voice_release.py --repo /absolute/repo
python3 tools/ios/check_voice_release.py --export /absolute/export-root
python3 tools/ios/check_voice_release.py --app /absolute/extracted/Payload/sensen.app
```

The artifact scan detects the runtime sentinel in binary content, QA bundle/plist/manifest and unaudited symlinks.
It is a known-overlay exclusion check, not a replacement for signing, IPA provenance, secret scanning or review
of arbitrary code. The artifact tests use synthetic app files; no signed QA IPA has been built/tested this round.

Python tests run actual preparation on temporary source fixtures, then verify the real release CLI and injector
refuse that output without modifying it. They also cover renamed QA source, removal of manifest/bundle labels,
flipped production gate, binary marker across read chunks, invalid scope, missing input and input preservation.

```sh
python3 -m unittest discover -s tools/ios -p 'test_voice_release.py' -v
python3 -m unittest discover -s tools/ios/voice_qa -p 'test_*.py' -v
```

`PolicyChecks.swift` exercises scope/grant/lifetime restrictions without a socket, audio, SDK or device. Any Swift
compiler/typecheck session still uses a new 大乔 resource window. Actual media cases remain NOT_RUN in the 21-case
ledger; this patch/its tests do not establish SFU, permission, route or signed-device acceptance.

## Review and later execution

Send this branch plus exact source hashes, source patch and test evidence to 周瑜. After review, report to 奕星.
Do not register `app.gensen.voiceqa`, create a profile/certificate, use a physical device, upload to TestFlight,
or touch any production service/LiveKit environment without the applicable explicit approval. 大乔 owns build,
Godot, simulator and device windows. GeoFarm native issues preempt this work. Its r1/r2 services remain untouched.

## 11-18 harness extension

A separately frozen minimal harness and unsigned build chain are now provided in [HARNESS.md](HARNESS.md).
The native preparation itself still never carries a game PCK; the following pack step binds only reviewed QA sources
to the same scope. The actual unsigned build does not establish media/device acceptance.
