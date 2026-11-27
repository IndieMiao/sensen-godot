#!/usr/bin/env bash
# Exercise the real headless runner without changing the game's autoloads or cache.
set -euo pipefail
cd "$(dirname "$0")/../.."
project=$(mktemp -d)
trap 'rm -rf "$project"' EXIT
mkdir -p "$project"/{tools,addons,tests/{p0,ui_kit}}
cp tools/run_tests.sh tools/godot_keep_adb_settings.py "$project/tools/"
cp -R addons/gdUnit4 "$project/addons/"
cd "$project"
cat > project.godot <<'EOF'
config_version=5
[application]
config/name="CardiganAutoloadGateControl"
[autoload]
Service="*res://service.gd"
EOF
for suite in p0 ui_kit; do
  cat > "tests/$suite/test_$suite.gd" <<'EOF'
extends GdUnitTestSuite

func test_independent_of_service() -> void:
    assert_bool(true).is_true()
EOF
done

# A failure for an unrelated reason (e.g. no tests found) is not a pass.
expect_rejection() {
  local diagnostic=$1 rc=0
  shift
  tools/run_tests.sh "$@" >gate.log 2>&1 || rc=$?
  if [[ $rc != 1 ]] || ! grep -Fq 'Godot could not start a project autoload' gate.log ||
      ! grep -F "$diagnostic" gate.log | grep -F 'res://service.gd' >/dev/null; then
    cat gate.log >&2
    echo "Expected autoload rejection with service path for $*; exit=$rc" >&2
    exit 1
  fi
  echo "Confirmed rejection (exit $rc): $* — $diagnostic, res://service.gd"
}
expect_rejection 'ERROR: Failed to create an autoload' --ci-import
for suite in p0 ui_kit; do
  expect_rejection 'ERROR: Failed to instantiate an autoload' --ci-headless "res://tests/$suite"
done

# Same configuration and suites must pass when the singleton exists.
printf 'extends Node\n' > service.gd
tools/run_tests.sh --ci-import
for suite in p0 ui_kit; do
  tools/run_tests.sh --ci-headless "res://tests/$suite"
done

# C-50: a failing case fails the step with Godot's own status, and the rest of its suite still runs and counts.
cat > tests/p0/test_fails.gd <<'EOF'
extends GdUnitTestSuite

func test_a_fails() -> void:
    assert_bool(false).is_true()

func test_b_still_runs() -> void:
    assert_bool(true).is_true()
EOF
rc=0
tools/run_tests.sh --ci-headless res://tests/p0 >gate.log 2>&1 || rc=$?
if [[ $rc != 100 ]] || ! LC_ALL=C sed -E $'s/\033\\[[0-9;]*m//g' gate.log |
    grep -F 'Overall Summary: 3 test cases | 0 errors | 1 failures |' >/dev/null; then
  cat gate.log >&2
  echo "Expected a failing p0 to exit 100 with all 3 cases run; exit=$rc" >&2
  exit 1
fi
echo "Confirmed failure (exit $rc): 3 test cases, 1 failure"
