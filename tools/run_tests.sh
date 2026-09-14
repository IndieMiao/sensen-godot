#!/usr/bin/env bash
# 用法: tools/run_tests.sh [res://tests/子目录]
set -e
cd "$(dirname "$0")/.."
export GODOT_BIN="${GODOT_BIN:-$(command -v godot)}"
"$GODOT_BIN" --headless --path . --import > /dev/null 2>&1 || true
# Historical text assertions use English; localization suites exercise both locales.
export SENSEN_LANGUAGE=en
exec ./addons/gdUnit4/runtest.sh -a "${1:-res://tests}"
