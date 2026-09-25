#!/usr/bin/env bash
set -euo pipefail
pond_adb="${ANDROID_SDK_ROOT:-$HOME/Library/Android/sdk}/platform-tools/adb"
pond_port="${POND_ADB_PORT:-5041}"
export ADB_SERVER_SOCKET="tcp:localhost:$pond_port"
export ANDROID_ADB_SERVER_PORT="$pond_port"
# Do not acquire a connected physical phone through a second USB transport.
"$pond_adb" --one-device POND_EMULATOR_ONLY_NO_USB start-server >/dev/null
exec "$pond_adb" "$@"
