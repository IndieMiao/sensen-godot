#!/usr/bin/env bash
# Pure protocol checks + Network adapter typecheck; no SPM resolve, listener, microphone or device access.
set -euo pipefail
task_root="$(cd "$(dirname "$0")/../.." && pwd)"
task_out="$(mktemp -d "${TMPDIR:-/tmp}/sensen-voice-check.XXXXXX")"
trap 'rm -rf "$task_out"' EXIT
src="$task_root/native/voice/apple/Sources/SensenVoiceApple"
xcrun swiftc -swift-version 5 -warnings-as-errors \
  "$src/VoiceWire.swift" "$src/VoiceEventDelivery.swift" \
  "$task_root/native/voice/apple/Tests/VoiceTransportChecks.swift" -o "$task_out/checks"
"$task_out/checks"
xcrun swiftc -swift-version 5 -warnings-as-errors -typecheck \
  "$src/VoiceWire.swift" "$src/VoiceEventDelivery.swift" "$src/VoiceDatagramServer.swift"
echo "VOICE_NETWORK_ADAPTER_TYPECHECK passed (host SDK only; not an iOS/device or LiveKit test)"
# Typecheck Apple's actual SDK surfaces without building/linking an app, resolving LiveKit, or opening a device.
for task_sdk in iphonesimulator iphoneos; do
  task_sdk_path="$(xcrun --sdk "$task_sdk" --show-sdk-path)"
  task_target="arm64-apple-ios15.0"
  if [[ "$task_sdk" == iphonesimulator ]]; then task_target+="-simulator"; fi
  xcrun swiftc -swift-version 5 -warnings-as-errors -sdk "$task_sdk_path" -target "$task_target" -typecheck \
    "$src/VoiceWire.swift" "$src/VoiceEventDelivery.swift" "$src/VoiceDatagramServer.swift"
  echo "VOICE_NETWORK_ADAPTER_TYPECHECK passed ($task_sdk / $task_target; no linking or device execution)"
done
