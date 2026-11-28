#!/usr/bin/env bash
# Run every tests/dynamic_farm/test_*.gd as a headless --script, each under its
# own timeout, against the repository's fixed r4 parcel fixtures. Needs an
# already imported project (CI: the build step's `run_tests.sh --ci-import`).
#
#   tools/ci/dynamic_farm_tests.sh            # all test files
#   tools/ci/dynamic_farm_tests.sh test_walk  # only the named files
#
# A file passes only if Godot exits 0 within the limit, prints no SCRIPT ERROR
# and prints exactly one summary line with a known prefix (SUMMARY_* below)
# reporting a non-zero check count with no failures. A hang is killed and
# reported as TIMEOUT (a failure). Anything that cannot run here is reported in
# its own "Skipped" section and never counts as a pass. With CI=1 (or true) the
# loopback TLS fixture for test_read_retries_https.gd must start, otherwise
# that file FAILs; locally it is skipped.
#
# Env: GODOT_BIN (default: godot on PATH), DYNAMIC_FARM_TIMEOUT seconds per
# file (default 180), DYNAMIC_FARM_TOTAL_TIMEOUT seconds for all files (default
# 1080, below the CI step's 20 minutes): each file's limit is clipped to the
# remaining budget and files left when it runs out are NOT RUN failures, so the
# report is always written. DYNAMIC_FARM_REPORT optional path for the Markdown
# report (it is also appended to $GITHUB_STEP_SUMMARY when set).
# Negative controls for this script: tools/ci/test-dynamic-farm-gate.sh.
set -uo pipefail
cd "$(dirname "$0")/../.."
GODOT_BIN=${GODOT_BIN:-$(command -v godot || true)}
limit=${DYNAMIC_FARM_TIMEOUT:-180}
total_limit=${DYNAMIC_FARM_TOTAL_TIMEOUT:-1080}
run_start=$SECONDS
ci_mode=0
case ${CI:-} in 1 | true | TRUE | True) ci_mode=1 ;; esac
dir=tests/dynamic_farm
fixtures=$dir/fixtures/r4
# The same offline settings as tools/run_tests.sh; Net never boots headless anyway.
export SENSEN_LANGUAGE=en SENSEN_OFFLINE=1

# The only accepted summary lines, matched against the whole (ANSI-stripped) line.
# A new test file prints one of these forms; add its prefix here or it fails.
#   "<PREFIX>[ key=value...] checks=N failures=M"
SUMMARY_CHECKS=(ARRANGE_TESTS BLUEPRINT_BOOK_TESTS BUILDING_FIT_TESTS DYNAMIC_BANK_TESTS DYNAMIC_LOWER_BANK_TESTS DYNAMIC_CORE_GRASS_EDGE DYNAMIC_PATH_TESTS
  DYNAMIC_CORE_OBSTACLE_TESTS DYNAMIC_EDGE_DECOR_TESTS DYNAMIC_EDGE_TESTS ISLAND_EXTERIOR
  DYNAMIC_OUTER_GROVE_TESTS DYNAMIC_PALETTE_TESTS DYNAMIC_PROP_PROXY_TESTS
  DYNAMIC_SLOPE_MATERIAL_TESTS DYNAMIC_WALK_TESTS OUTER_GATHER OUTER_GATHER_SCENE PARCEL_FARMING
  PARCEL_FARMING_SCENE PARCEL_FARMING_SERVER PARCEL_TOWN PARCEL_OUTPOST DYNAMIC_HOUSE_TESTS COOP_TESTS BARN_TESTS SHEEP_PEN_TESTS PARCEL_PHONE PARCEL_BOARD
  PARCEL_FISHING PARCEL_PIER
  MAP_TRAVEL)
#   "<PREFIX> passed/total"
SUMMARY_RATIO=("DYNAMIC ENGLISH UI" "DYNAMIC MAP OCCLUSION" "DYNAMIC ROOT BACK" "PREVIEW HOST"
  "DYNAMIC READ RETRIES" "DYNAMIC HTTPS RETRIES" "DYNAMIC RETRY CANCEL REENTRY"
  "DYNAMIC HTTP PRECEDENCE" "DYNAMIC SELECTION" "DYNAMIC CLAIM" "DYNAMIC CORE SIZE" "DYNAMIC MAP CAMERA"
  "PARCEL PROFILE" "ACCOUNT DELETE")
summary_checks_re="^($(IFS='|'; echo "${SUMMARY_CHECKS[*]}"))( [a-z_]+=[^ ]*)* checks=([0-9]+) failures=([0-9]+)\$"
summary_ratio_re="^($(IFS='|'; echo "${SUMMARY_RATIO[*]}")) ([0-9]+)/([0-9]+)\$"

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
      -keyout "$tls/$cert.key" -out "$tls/$cert.pem" >>"$tls/openssl.log" 2>&1 || return 1
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

#   limited SECONDS COMMAND...: COMMAND under a time limit, as `timeout --kill-after=10`:
# TERM at the limit and exit 124, KILL 10 s later and exit 137. GNU timeout when
# there is one, else Homebrew's gtimeout, else perl (macOS ships neither timeout).
limited() {
  if command -v timeout >/dev/null; then timeout --kill-after=10 "$@"; return; fi
  if command -v gtimeout >/dev/null; then gtimeout --kill-after=10 "$@"; return; fi
  perl -MPOSIX=WNOHANG -MTime::HiRes=sleep,time -e '
    my ($limit, @cmd) = @ARGV;
    defined(my $pid = fork) or die "fork: $!\n";
    if (!$pid) { exec { $cmd[0] } @cmd; exit 127 }
    my ($end, $termed) = (time + $limit, 0);
    while (waitpid($pid, WNOHANG) == 0) {
      if (time >= $end) {
        if ($termed) { kill "KILL", $pid; waitpid($pid, 0); exit 137 }
        kill "TERM", $pid; $termed = 1; $end = time + 10;
      }
      sleep 0.1;
    }
    exit 124 if $termed;
    exit(($? & 127) ? 128 + ($? & 127) : $? >> 8);' "$@"
}

stop_https_fixture() {
  if [[ -n $fixture_pid ]]; then kill "$fixture_pid" 2>/dev/null; wait "$fixture_pid" 2>/dev/null; fixture_pid=; fi
}

run_one() {
  local name=$1 log=$work/$1.log args=() start rc summary checks failures note= file_limit
  if [[ $name == test_parcel_farming_server ]]; then
    # Its arguments are a running C-31 server and the parcel owner's token (file header).
    skipped+=("| $name.gd | needs a running C-31 server and the parcel owner's token; run by hand |")
    rows+=("| $name.gd | SKIPPED | – | – | see Skipped |")
    return
  fi
  local remaining=$((total_limit - (SECONDS - run_start)))
  if ((remaining < 1)); then
    rows+=("| $name.gd | NOT RUN | – | – | total budget ${total_limit}s used up |")
    failed=$((failed + 1))
    return
  fi
  if [[ $name == test_read_retries_https ]]; then
    # Not in a subshell: the fixture's PID must stay in fixture_pid for cleanup.
    if ! start_https_fixture >"$work/https_args"; then
      echo "::group::$name.gd (loopback TLS fixture did not start)"
      cat "$work/tls/openssl.log" "$work/tls/server.log" 2>/dev/null
      echo "::endgroup::"
      stop_https_fixture
      if ((ci_mode)); then
        rows+=("| $name.gd | FAIL | – | – | loopback TLS fixture could not start (openssl/python3); required with CI=1 |")
        failed=$((failed + 1))
      else
        skipped+=("| $name.gd | loopback TLS fixture could not start (openssl/python3) |")
        rows+=("| $name.gd | SKIPPED | – | – | see Skipped |")
      fi
      return
    fi
    while IFS= read -r line; do args+=("$line"); done <"$work/https_args" # no mapfile in macOS's bash 3.2
  else
    args=("${parcels[@]}")
  fi
  # Clip this file's limit to what is left of the total budget (at least 1 s).
  remaining=$((total_limit - (SECONDS - run_start)))
  file_limit=$((limit < remaining ? limit : remaining > 0 ? remaining : 1))
  start=$SECONDS
  limited "$file_limit" "$GODOT_BIN" --headless --path . \
    --script "res://$dir/$name.gd" -- "${args[@]}" >"$log" 2>&1
  rc=$?
  local seconds=$((SECONDS - start))
  [[ $name == test_read_retries_https ]] && stop_https_fixture
  echo "::group::$name.gd (exit $rc, ${seconds}s)"
  cat "$log"
  echo "::endgroup::"
  # Exactly one line in a known summary form (see SUMMARY_*); other "a/b" or
  # "checks=" output before or after it is never read as the summary.
  local count=0
  checks=
  failures=
  while IFS= read -r summary; do
    count=$((count + 1))
    if [[ $summary =~ checks=([0-9]+)\ failures=([0-9]+)$ ]]; then
      checks=${BASH_REMATCH[1]}; failures=${BASH_REMATCH[2]}
    elif [[ $summary =~ ([0-9]+)/([0-9]+)$ ]]; then
      checks=${BASH_REMATCH[2]}; failures=$((BASH_REMATCH[2] - BASH_REMATCH[1]))
    fi
  done < <(LC_ALL=C sed -E $'s/\033\\[[0-9;]*m//g; s/[[:space:]]+$//' "$log" |
    grep -E -e "$summary_checks_re" -e "$summary_ratio_re")
  local result=PASS
  if [[ $rc == 124 || $rc == 137 ]]; then
    result=TIMEOUT; note="killed after ${file_limit}s"
    ((file_limit < limit)) && note+=" (rest of the ${total_limit}s total budget)"
  elif [[ $rc != 0 ]]; then
    result=FAIL; note="exit $rc"
  elif grep -q 'SCRIPT ERROR' "$log"; then
    result=FAIL; note="SCRIPT ERROR in log"
  elif ((count == 0)); then
    result=FAIL; note="no known summary line (add a new test's prefix to SUMMARY_* in this script)"
  elif ((count > 1)); then
    result=FAIL; note="$count summary lines, expected exactly one"
  elif [[ $checks == 0 ]]; then
    result=FAIL; note="0 checks ran"
  elif ((failures < 0)); then
    result=FAIL; note="summary reports more passed than total"
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
  echo "Fixtures: ${#parcels[@]} r4 parcels in \`$fixtures\` (checksums verified). Timeout ${limit}s per file, ${total_limit}s in total; $((SECONDS - run_start))s used."
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
