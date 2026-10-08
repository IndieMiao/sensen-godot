#!/usr/bin/env bash
set -euo pipefail
exec "${BASIC_ROOM_SDK:-$HOME/Android/Sdk}/platform-tools/adb" -P "${BASIC_ROOM_ADB_PORT:-5061}" "$@"
