#!/usr/bin/env bash
# Offline review project; uses fixture appearance and never starts game networking.
set -euo pipefail
ROOM_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOM_ROOT"
ROOM_GODOT="${GODOT:-godot}"
python3 -I tools/godot_keep_adb_settings.py "$ROOM_GODOT"  # editor imports below keep the shared adb server (C-210)
if [[ ! -f output/basic-room-2026-10-06/avatar-dependencies.json ]]; then
  mkdir -p output/basic-room-2026-10-06
  touch output/.gdignore
  "$ROOM_GODOT" --headless --editor --path . --import --quit
  "$ROOM_GODOT" --headless --path . --script res://tools/dev/basic_room/collect_avatar_deps.gd
fi
python3 tools/dev/basic_room/prepare_basic_room.py
ROOM_QA="output/basic-room-2026-10-06/qa-project"
"$ROOM_GODOT" --headless --editor --path "$ROOM_QA" --import --quit
"$ROOM_GODOT" --headless --path "$ROOM_QA" --script res://tools/dev/basic_room/configure_imports.gd
"$ROOM_GODOT" --headless --editor --path "$ROOM_QA" --import --quit
exec "$ROOM_GODOT" --path "$ROOM_QA" --resolution 700x700 "$@"
