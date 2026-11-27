#!/usr/bin/env bash
# Local: tools/run_tests.sh [res://tests/subdir]
# CI:    --ci-import once, then --ci-headless res://tests/subdir per suite.
set -eo pipefail
cd "$(dirname "$0")/.."
export GODOT_BIN="${GODOT_BIN:-$(command -v godot)}"
# Historical text assertions use English; localization suites exercise both locales.
export SENSEN_LANGUAGE=en
# An editor run (the imports below) must not stop the shared adb server under a private HOME (C-210).
keep_adb() { python3 -I tools/godot_keep_adb_settings.py "$GODOT_BIN"; }

if [[ ${1:-} == --ci-import || ${1:-} == --ci-headless ]]; then
  log=$(mktemp)
  trap 'rm -f "$log"' EXIT
fi
# Editor import and game startup use different diagnostics for the same broken
# project singleton. Godot can print either and still return 0.
check_autoloads() {
  if grep -E 'ERROR: Failed to (create|instantiate) an autoload' "$log" >&2; then
    echo "Godot could not start a project autoload ($1)" >&2
    exit 1
  fi
}
if [[ ${1:-} == --ci-import ]]; then
  keep_adb
  "$GODOT_BIN" --headless --path . --import 2>&1 | tee "$log"
  check_autoloads import
  # Godot 4.7.2 exits 0 even for a corrupt image. Match terminal import/script
  # failures, not every ERROR (legacy FBX optional source textures are absent).
  if grep -E "SCRIPT ERROR:|ERROR: (Error importing|Failed to import)" "$log"; then
    echo "Godot reported an import or script failure" >&2
    exit 1
  fi
  exit 0
fi
if [[ ${1:-} == --ci-headless ]]; then
  suite=${2:?expected a res://tests suite after --ci-headless}
  # The stock runtest.sh starts a window even if the editor import was headless.
  # Keep its noninteractive debugger, and import just once in the caller.
  # -c: the CI runner otherwise skips a suite's remaining cases after its first failure, which hides them and
  # shrinks the case count (C-50: 2238 instead of 2242).
  "$GODOT_BIN" --headless --path . -d --remote-debug tcp://127.0.0.1:0 \
    --script res://addons/gdUnit4/bin/GdUnitCmdTool.gd -a "$suite" -c --ignoreHeadlessMode 2>&1 | tee "$log"
  check_autoloads "$suite"
  # gdUnit can exit 0 with no tests. Require its final (not per-suite) summary.
  # There are no whole-case skips in these two suites' headless inventory.
  if ! LC_ALL=C sed -E $'s/\033\\[[0-9;]*m//g' "$log" | grep -E \
      '^Overall Summary: [1-9][0-9]* test cases \| 0 errors \| 0 failures \| [0-9]+ flaky \| 0 skipped \| 0 orphans \|$'; then
    echo "Missing or non-passing gdUnit Overall Summary for $suite" >&2
    exit 1
  fi
  exit 0
fi

keep_adb
"$GODOT_BIN" --headless --path . --import > /dev/null 2>&1 || true
exec ./addons/gdUnit4/runtest.sh -a "${1:-res://tests}"
