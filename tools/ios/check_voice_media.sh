#!/usr/bin/env bash
# Controller lifecycle regression only. No SDK download/build, sockets, permission prompt, or microphone.
set -euo pipefail
task_root="$(cd "$(dirname "$0")/../.." && pwd)"
task_out="$(mktemp -d "${TMPDIR:-/tmp}/sensen-voice-media.XXXXXX")"
trap 'rm -rf "$task_out"' EXIT
src="$task_root/native/voice/apple/Sources/SensenVoiceApple"
xcrun swiftc -swift-version 5 -warnings-as-errors \
  "$src/VoiceWire.swift" "$src/VoiceCaptureGate.swift" "$src/VoiceTransmitFence.swift" "$src/VoiceMediaController.swift" \
  "$task_root/native/voice/apple/Tests/VoiceMediaControllerChecks.swift" -o "$task_out/checks"
"$task_out/checks" "$@"
