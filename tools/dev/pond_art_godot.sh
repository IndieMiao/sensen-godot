#!/usr/bin/env bash
# Godot's Android exporter defaults to shutdown_adb_on_exit=true. Its ADB
# lifecycle must never stop another branch's device session on port 5037.
set -euo pipefail
export ADB_SERVER_SOCKET="tcp:localhost:${POND_ADB_PORT:-5041}"
export ANDROID_ADB_SERVER_PORT="${POND_ADB_PORT:-5041}"
exec "${GODOT_BIN:-godot}" "$@"
