#!/usr/bin/env bash
# Run every tests/dynamic_farm/test_*.gd as a headless --script, each under its
# own timeout, against the repository's fixed r4 parcel fixtures. Needs an
# already imported project (CI: the build step's `run_tests.sh --ci-import`).
#
#   tools/ci/dynamic_farm_tests.sh            # all test files
#   tools/ci/dynamic_farm_tests.sh test_walk  # only the named files
#
# A file passes only if Godot exits 0 within the limit, prints no SCRIPT ERROR
# and its summary line reports a non-zero check count with no failures. A hang
# is killed and reported as TIMEOUT (a failure). Anything that cannot run here
# is reported in its own "Skipped" section and never counts as a pass.
#
# Env: GODOT_BIN (default: godot on PATH), DYNAMIC_FARM_TIMEOUT seconds per
# file (default 180), DYNAMIC_FARM_REPORT optional path for the Markdown report
# (it is also appended to $GITHUB_STEP_SUMMARY when set).
set -uo pipefail
cd "$(dirname "$0")/../.."
GODOT_BIN=${GODOT_BIN:-$(command -v godot || true)}
limit=${DYNAMIC_FARM_TIMEOUT:-180}
dir=tests/dynamic_farm
fixtures=$dir/fixtures/r4
# The same offline settings as tools/run_tests.sh; Net never boots headless anyway.
export SENSEN_LANGUAGE=en SENSEN_OFFLINE=1

work=$(mktemp -d)
fixture_pid=
cleanup() {
  if [[ -n $fixture_pid ]]; then kill "$fixture_pid" 2>/dev/null; wait "$fixture_pid" 2>/dev/null; fi
  rm -rf "$work"
}
trap cleanup EXIT

if [[ -z $GODOT_BIN || ! -x $GODOT_BIN ]]; then
  echo "dynamic_farm: GODOT_BIN is not an executable Godot" >&2
  exit 1
fi
# Pinned inputs: a changed or missing fixture is a failure, not a smaller run.
if ! (cd "$fixtures" && sha256sum --check --strict --quiet SHA256SUMS); then
  echo "dynamic_farm: fixture checksum mismatch in $fixtures" >&2
  exit 1
fi
parcels=()
while read -r _ name; do parcels+=("$fixtures/${name#\*}"); done < "$fixtures/SHA256SUMS"

rows=()      # | file | result | checks | seconds | note |
skipped=()   # | file or variant | reason |
failed=0
passed=0
total_checks=0

# Start the loopback TLS fixture for test_read_retries_https.gd. Prints its
# Godot user args (origin, trusted CA, unrelated CA) or returns 1.
start_https_fixture() {
  local tls=$work/tls port_file=$work/tls/port
  mkdir -p "$tls"
  local cert
  for cert in trusted other; do
    openssl req -x509 -newkey rsa:2048 -nodes -days 2 -subj "/CN=dynamic-farm-$cert" \
      -addext "subjectAltName=IP:127.0.0.1" -addext "basicConstraints=critical,CA:TRUE" \
      -keyout "$tls/$cert.key" -out "$tls/$cert.pem" >/dev/null 2>&1 || return 1
  done
  python3 -I "$dir/retry_https_fixture.py" --cert "$tls/trusted.pem" --key "$tls/trusted.key" \
    --port-file "$port_file" --journal "$tls/journal.jsonl" >"$tls/server.log" 2>&1 &
  fixture_pid=$!
  for _ in $(seq 50); do
    [[ -s $port_file ]] && break
    kill -0 "$fixture_pid" 2>/dev/null || return 1
    sleep 0.1
  done
  [[ -s $port_file ]] || return 1
  printf '%s\n' "https://127.0.0.1:$(cat "$port_file")" "$tls/trusted.pem" "$tls/other.pem"
}

run_one() {
  local name=$1 log=$work/$1.log args=() start rc summary checks failures note=
  if [[ $name == test_parcel_farming_server ]]; then
    # Its arguments are a running C-31 server and the parcel owner's token (file header).
    skipped+=("| $name.gd | needs a running C-31 server and the parcel owner's token; run by hand |")
    rows+=("| $name.gd | SKIPPED | – | – | see Skipped |")
    return
  fi
  if [[ $name == test_read_retries_https ]]; then
    # Not in a subshell: the fixture's PID must stay in fixture_pid for cleanup.
    if ! start_https_fixture >"$work/https_args"; then
      skipped+=("| $name.gd | loopback TLS fixture could not start (openssl/python3) |")
      rows+=("| $name.gd | SKIPPED | – | – | see Skipped |")
      return
    fi
    mapfile -t args <"$work/https_args"
  else
    args=("${parcels[@]}")
  fi
  start=$SECONDS
  timeout --kill-after=10 "$limit" "$GODOT_BIN" --headless --path . \
    --script "res://$dir/$name.gd" -- "${args[@]}" >"$log" 2>&1
  rc=$?
  local seconds=$((SECONDS - start))
  if [[ $name == test_read_retries_https && -n $fixture_pid ]]; then
    kill "$fixture_pid" 2>/dev/null; wait "$fixture_pid" 2>/dev/null; fixture_pid=
  fi
  echo "::group::$name.gd (exit $rc, ${seconds}s)"
  cat "$log"
  echo "::endgroup::"
  # Summary formats in use: "... checks=N failures=M" or "... passed/total".
  summary=$(LC_ALL=C sed -E $'s/\033\\[[0-9;]*m//g' "$log" | grep -E 'checks=[0-9]+ failures=[0-9]+|[0-9]+/[0-9]+[[:space:]]*$' | tail -1)
  checks=
  failures=
  if [[ $summary =~ checks=([0-9]+)\ failures=([0-9]+) ]]; then
    checks=${BASH_REMATCH[1]}; failures=${BASH_REMATCH[2]}
  elif [[ $summary =~ ([0-9]+)/([0-9]+)[[:space:]]*$ ]]; then
    checks=${BASH_REMATCH[2]}; failures=$((BASH_REMATCH[2] - BASH_REMATCH[1]))
  fi
  local result=PASS
  if [[ $rc == 124 || $rc == 137 ]]; then
    result=TIMEOUT; note="killed after ${limit}s"
  elif [[ $rc != 0 ]]; then
    result=FAIL; note="exit $rc"
  elif grep -q 'SCRIPT ERROR' "$log"; then
    result=FAIL; note="SCRIPT ERROR in log"
  elif [[ -z $checks ]]; then
    result=FAIL; note="no checks=/failures= summary line"
  elif [[ $checks == 0 ]]; then
    result=FAIL; note="0 checks ran"
  elif [[ $failures != 0 ]]; then
    result=FAIL; note="$failures failures"
  fi
  # A test that skips part of its cases (e.g. no real parcels) says SKIP.
  while IFS= read -r line; do
    skipped+=("| $name.gd (part) | ${line//|//} |")
    note="${note:+$note; }partial skip"
  done < <(grep -E '(^| )SKIP ' "$log")
  if [[ $result == PASS ]]; then
    passed=$((passed + 1)); total_checks=$((total_checks + checks))
  else
    failed=$((failed + 1))
  fi
  rows+=("| $name.gd | $result | ${checks:-?} | $seconds | $note |")
}

selected=("$@")
if [[ ${#selected[@]} == 0 ]]; then
  for path in "$dir"/test_*.gd; do selected+=("$(basename "$path" .gd)"); done
fi
for name in "${selected[@]}"; do
  name=${name%.gd}
  if [[ ! -f $dir/$name.gd ]]; then
    rows+=("| $name.gd | FAIL | – | – | file not found |"); failed=$((failed + 1)); continue
  fi
  run_one "$name"
done
# Variants that exist in the test code but have no input in the repository.
skipped+=("| test_mesh_edges.gd --legacy | compares against res://old_farm_mesh.gd, which is not in the repository; the default mode runs above |")

report=$work/report.md
{
  echo "## dynamic_farm tests"
  echo
  echo "Fixtures: ${#parcels[@]} r4 parcels in \`$fixtures\` (checksums verified). Timeout ${limit}s per file."
  echo
  echo "| file | result | checks | s | note |"
  echo "| --- | --- | --- | --- | --- |"
  printf '%s\n' "${rows[@]}"
  echo
  echo "### Skipped (not counted as passed)"
  echo
  echo "| file | reason |"
  echo "| --- | --- |"
  printf '%s\n' "${skipped[@]}"
  echo
  echo "dynamic_farm: $passed passed, $failed failed, $(( ${#rows[@]} - passed - failed )) skipped files; $total_checks checks in passing files"
} >"$report"
cat "$report"
[[ -n ${GITHUB_STEP_SUMMARY:-} ]] && cat "$report" >>"$GITHUB_STEP_SUMMARY"
[[ -n ${DYNAMIC_FARM_REPORT:-} ]] && cp "$report" "$DYNAMIC_FARM_REPORT"
[[ $failed == 0 && $passed -gt 0 ]]
