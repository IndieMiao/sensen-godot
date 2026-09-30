#!/usr/bin/env bash
set -euo pipefail
pond_root="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$pond_root"
export POND_ADB_PORT="${POND_ADB_PORT:-5053}"
mkdir -p output/pond-reference-2026-09-29
touch output/.gdignore
tools/dev/pond_art_godot.sh --headless --editor --path . --import > output/pond-reference-2026-09-29/import.log 2>&1
tools/dev/pond_art_godot.sh --headless --path . --script tools/dev/prepare_pond_pitch.gd
exec tools/dev/pond_art_godot.sh --path output/pond-reference-2026-09-29/project --resolution 1280x800 -- --shot=reference --motion
