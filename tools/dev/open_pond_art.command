#!/usr/bin/env bash
set -euo pipefail
pond_root="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$pond_root"
mkdir -p output/pond-pitch-2026-09-25
tools/dev/pond_art_godot.sh --headless --editor --path . --import > output/pond-pitch-2026-09-25/import.log 2>&1
tools/dev/pond_art_godot.sh --headless --path . --script tools/dev/prepare_pond_pitch.gd
exec tools/dev/pond_art_godot.sh --path output/pond-pitch-2026-09-25/project --resolution 1280x800 -- --motion
