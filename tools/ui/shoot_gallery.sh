#!/usr/bin/env bash
# PNG shots of the P0 UI kit gallery, one per section (SGODOT-211 / 212). Needs a desktop renderer.
# Usage: tools/ui/shoot_gallery.sh [out_dir]            (default: output/ui_kit/<timestamp>)
#        tools/ui/shoot_gallery.sh --update             refresh tests/ui_kit/snapshots/png
#        tools/ui/shoot_gallery.sh --check              shoot to a temp dir and compare with the goldens
set -euo pipefail
cd "$(dirname "$0")/../.."
GODOT_BIN="${GODOT_BIN:-$(command -v godot)}"
GOLDEN="$PWD/tests/ui_kit/snapshots/png"
mode="${1:-}"
case "$mode" in
  --update) out="$GOLDEN" ;;
  --check) out="$(mktemp -d)" ;;
  "") out="$PWD/output/ui_kit/$(date +%Y%m%d-%H%M%S)" ;;
  *) out="$(cd "$(dirname "$mode")" && pwd)/$(basename "$mode")" ;;
esac
mkdir -p "$out"
UI_KIT_SHOT="$out" "$GODOT_BIN" --path . --resolution 720x1280 res://scenes/ui_kit/gallery.tscn
if [ "$mode" = "--check" ]; then
  python3 tools/ui/compare_shots.py "$GOLDEN" "$out"
else
  echo "shots: $out"
fi
