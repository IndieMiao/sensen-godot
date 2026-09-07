#!/usr/bin/env bash
# gdUnit4 全量 / 单套件：tools/run_tests.sh [res://tests/xxx.gd]
# GODOT_BIN 指定二进制；GODOT_HEADLESS=1 时加 --headless（CI 没有显示器；本地默认开窗口，
# 因为 frame_post_draw 之类只在有窗口时才来）。
set -e
cd "$(dirname "$0")/.."
export GODOT_BIN="${GODOT_BIN:-$(command -v godot)}"
"$GODOT_BIN" --headless --path . --import > /dev/null 2>&1 || true
extra=()
if [ "${GODOT_HEADLESS:-0}" = "1" ]; then
  extra+=(--headless --ignoreHeadlessMode)
fi
exec ./addons/gdUnit4/runtest.sh "${extra[@]}" -a "${1:-res://tests}"
