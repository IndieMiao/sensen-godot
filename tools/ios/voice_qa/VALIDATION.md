# Code-only validation — 2026-11-17

Production baseline: `0cce63969476315ef3ae8be80cb27c710fcfeb53`. The production package and `tools/ios/VoiceBootstrap.swift`
are unchanged relative to that head; the only release-path change is the separate exclusion check and its injector/CI hook.
No farm-dev, PR-A or #1084 branch was changed.

Actual results:

- Release exclusion tests: **7 passed**. Covers production constant flip, renamed QA source/bootstrap, binary sentinel
  crossing a stream chunk, QA app identity and missing inputs. Artifact fixtures are synthetic files, not signed IPAs.
- QA preparation/integration negatives: **9 passed**. The real preparation generates a temporary QA export; the actual
  release-check CLI exits 1 and the actual production injector raises before overwriting it. Removing manifest/plist
  labels still leaves source markers that are refused. Source preservation, unknown sources/symlinks, destinations,
  wrong environment/namespace/origin/issuer placeholder and time window are covered. No network/signing/device APIs run.
- Existing injector regression: **11 passed** after the new pre-injection guard. No repeated media/UDP suite.
- Swift Foundation/CryptoKit policy checks: **32 passed**, no socket/SDK/audio/permission execution. Deliberately fake
  signatures exercise only local restriction checks; this is not successful JWT authentication against a service.
- The actual patched Swift package sources plus new policy **emit a module for arm64-apple-ios15.0-simulator** using
  the previously verified LiveKit 2.19 modules and current simulator SDK. The QA UIKit bootstrap plus the unchanged
  real NativeBridgeKey provider typecheck against that module. This is not a linked/built/signed App or runtime test.
- The compiled source files match the final patch/template hashes; the generated fixture export is actually refused
  by release CLI, while the actual production repository source check passes.

First host compiler attempt could not load the standard library for its implicit macOS target; the failure log is
retained. Explicit macOS SDK plus arm64-macosx12.0 resolved the tool invocation; no Swift source change was needed.

大乔 Q1117-14 opened 20:20–20:30; checks completed and were reported released early. Recorded PIDs
14322/14721/14747/14748/14770/14773/14774 are all absent in ps. No App signing, provisioning, TestFlight, simulator,
Godot, microphone, endpoint, service or production operation occurred. No old resource permission was reused.

Evidence: `/Volumes/ACASIS/tmp/yase-ios-media-qa-evidence-1117/`, uploaded to SGODOT-387. A source-level review by 周瑜
is still required. All 21 real media/device acceptance cases remain NOT_RUN; a separately reviewed QA harness/PCK,
actual isolated endpoint/issuer scope, device/signing approval and resource window are prerequisites to execution.
