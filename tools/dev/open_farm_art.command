#!/bin/zsh
set -eu
cd "$(dirname "$0")/../.."
FARM_GODOT_BIN="${GODOT_BIN:-/Applications/Godot.app/Contents/MacOS/Godot}"
exec "$FARM_GODOT_BIN" --path . --resolution 480x900 tools/dev/farm_art_preview.tscn
