#!/usr/bin/env bash
set -euo pipefail
exec "${BASIC_ROOM_SDK:-$HOME/Android/Sdk}/platform-tools/adb" -P 5061 "$@"
