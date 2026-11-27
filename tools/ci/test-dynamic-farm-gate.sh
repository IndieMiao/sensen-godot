#!/usr/bin/env bash
# Negative controls for tools/ci/dynamic_farm_tests.sh. Runs a copy of the script in a
# throwaway tree with a fake Godot whose "test files" are shell snippets, so no real
# Godot, import or repository test is involved. Each case checks the report row and
# the exit status the CI step would see.
set -euo pipefail
src=$(cd "$(dirname "$0")/../.." && pwd)
root=$(mktemp -d)
trap 'rm -rf "$root"' EXIT
dir=$root/tests/dynamic_farm
mkdir -p "$root/tools/ci" "$dir/fixtures/r4" "$root/bin" "$root/no-openssl"
cp "$src/tools/ci/dynamic_farm_tests.sh" "$root/tools/ci/"
cp "$src/tests/dynamic_farm/retry_https_fixture.py" "$dir/"
echo '{}' >"$dir/fixtures/r4/p-1.json"
(cd "$dir/fixtures/r4" && sha256sum p-1.json >SHA256SUMS)

# Fake Godot: run res://<file> (a shell snippet) with the arguments after "--".
cat >"$root/bin/godot" <<'EOF'
#!/usr/bin/env bash
script=
while (($#)); do
  case $1 in --script) script=${2#res://}; shift 2 ;; --) shift; break ;; *) shift ;; esac
done
exec bash "$script" "$@"
EOF
# An openssl that always fails, for the TLS fixture cases.
printf '#!/bin/sh\necho "fake openssl: unavailable" >&2\nexit 1\n' >"$root/no-openssl/openssl"
chmod +x "$root/bin/godot" "$root/no-openssl/openssl"

t() { printf '%s\n' "$2" >"$dir/$1.gd"; }
t test_ok 'echo "DYNAMIC_WALK_TESTS checks=3 failures=0"'
t test_ratio_ok 'echo "PREVIEW HOST 12/12"'
# C-63 #1: a zero-check summary followed by ordinary "a/b" or "checks=" output.
t test_zero_then_ratio 'echo "DYNAMIC_WALK_TESTS checks=0 failures=0"; echo "reachable 4/4"'
t test_zero_then_checks 'echo "DYNAMIC_PALETTE_TESTS checks=0 failures=0"; echo "OTHER checks=5 failures=0"'
t test_ratio_only_unknown 'echo "reachable 4/4"; echo "UNKNOWN_TESTS checks=4 failures=0"'
t test_two_summaries 'echo "DYNAMIC_WALK_TESTS checks=2 failures=0"; echo "PREVIEW HOST 2/2"'
t test_failures 'echo "DYNAMIC_EDGE_TESTS legacy=false checks=2 failures=1"'
t test_ratio_failures 'echo "DYNAMIC SELECTION 3/4"'
t test_ansi_ok 'printf "\033[1mDYNAMIC_CORE_GRASS_EDGE parcels=1 checks=5 failures=0\033[0m \n"'
# Gets the fixture's origin and two CA files; fails if they are not real.
t test_read_retries_https '[[ $1 == https://127.0.0.1:* && -s $2 && -s $3 ]] || exit 3
curl -sS --cacert "$2" "$1/parcel-catalog.json" -o /dev/null -w "%{http_code}\n" | grep -qx 404 || exit 4
echo "DYNAMIC HTTPS RETRIES 1/1"'
for name in hang_a hang_b hang_c; do t "test_$name" 'echo "started"; exec sleep 60'; done
# Ignores TERM (inherited by sleep): only the KILL kill_after later ends it.
t test_hang_stubborn 'trap "" TERM; echo "started"; exec sleep 60'
t test_exit3 'echo "DYNAMIC_WALK_TESTS checks=1 failures=0"; exit 3'

pass=0
# run <expected exit> <env assignments...> -- <test names...>
run() {
  local want=$1 rc=0 envs=()
  shift
  while [[ $1 != -- ]]; do envs+=("$1"); shift; done
  shift
  env -u CI -u GITHUB_STEP_SUMMARY GODOT_BIN="$root/bin/godot" DYNAMIC_FARM_REPORT="$root/report.md" \
    "${envs[@]}" "$root/tools/ci/dynamic_farm_tests.sh" "$@" >"$root/out.log" 2>&1 || rc=$?
  if [[ $rc != "$want" ]]; then
    cat "$root/out.log" >&2
    echo "FAIL: expected exit $want, got $rc for: ${envs[*]} $*" >&2
    exit 1
  fi
}
# row <file> <result> <note substring>
row() {
  if ! grep -F "| $1.gd | $2 |" "$root/report.md" | grep -Fq -- "$3"; then
    cat "$root/report.md" >&2
    echo "FAIL: expected row '$1.gd | $2' containing '$3'" >&2
    exit 1
  fi
  pass=$((pass + 1))
  echo "ok: $1.gd -> $2 ${3:+($3)}"
}

echo "== summary lines (known prefixes, exactly one)"
run 1 DYNAMIC_FARM_TIMEOUT=10 -- test_ok test_ratio_ok test_ansi_ok test_zero_then_ratio \
  test_zero_then_checks test_ratio_only_unknown test_two_summaries test_failures test_ratio_failures
row test_ok PASS ''
row test_ratio_ok PASS ''
row test_ansi_ok PASS ''
row test_zero_then_ratio FAIL '0 checks ran'
row test_zero_then_checks FAIL '0 checks ran'
row test_ratio_only_unknown FAIL 'no known summary line'
row test_two_summaries FAIL '2 summary lines'
row test_failures FAIL '1 failures'
row test_ratio_failures FAIL '1 failures'
run 0 DYNAMIC_FARM_TIMEOUT=10 -- test_ok test_ratio_ok
row test_ok PASS ''

echo "== loopback TLS fixture"
run 1 CI=1 PATH="$root/no-openssl:$PATH" -- test_ok test_read_retries_https
row test_read_retries_https FAIL 'required with CI=1'
run 1 CI=true PATH="$root/no-openssl:$PATH" -- test_ok test_read_retries_https
row test_read_retries_https FAIL 'required with CI=1'
run 0 PATH="$root/no-openssl:$PATH" -- test_ok test_read_retries_https
row test_read_retries_https SKIPPED 'see Skipped'
grep -Fq '| test_read_retries_https.gd | loopback TLS fixture could not start' "$root/report.md"
# Positive control: real openssl and fixture under CI=1.
run 0 CI=1 -- test_read_retries_https
row test_read_retries_https PASS ''

echo "== per-file and total time limits"
start=$SECONDS
run 1 DYNAMIC_FARM_TIMEOUT=3 DYNAMIC_FARM_TOTAL_TIMEOUT=8 -- test_hang_a test_hang_b test_hang_c test_ok
took=$((SECONDS - start))
row test_hang_a TIMEOUT 'killed after 3s'
row test_hang_b TIMEOUT 'killed after 3s'
row test_hang_c TIMEOUT '8s total budget'
row test_ok 'NOT RUN' 'total budget 8s used up'
grep -Fq 'dynamic_farm: 0 passed, 4 failed' "$root/report.md"
if ((took > 14)); then
  echo "FAIL: total budget 8s, run took ${took}s" >&2
  exit 1
fi
echo "ok: report written after ${took}s for an 8s budget"

# C-207: macOS has no GNU timeout (and mac-mini no gtimeout); the script falls back to
# perl. A PATH with every tool but those two runs the same limits through it.
echo "== time limits without timeout or gtimeout (the perl fallback, as on macOS)"
nt=$root/no-timeout
mkdir -p "$nt"
IFS=: read -ra path_dirs <<<"$PATH"
for d in "${path_dirs[@]}"; do
  for f in "$d"/*; do
    n=${f##*/}
    if [[ -f $f && -x $f && $n != timeout && $n != gtimeout && ! -e $nt/$n ]]; then ln -s "$f" "$nt/$n"; fi
  done
done
if PATH=$nt command -v timeout >/dev/null || PATH=$nt command -v gtimeout >/dev/null; then
  echo "FAIL: timeout still on the stripped PATH" >&2
  exit 1
fi
start=$SECONDS
run 1 PATH="$nt" DYNAMIC_FARM_TIMEOUT=3 DYNAMIC_FARM_TOTAL_TIMEOUT=60 -- test_ok test_exit3 test_hang_a test_hang_stubborn
took=$((SECONDS - start))
row test_ok PASS ''
row test_exit3 FAIL 'exit 3'
row test_hang_a TIMEOUT 'killed after 3s'
row test_hang_stubborn TIMEOUT 'killed after 3s'
if ((took > 24)); then
  echo "FAIL: 3s + (3s and 10s to KILL) took ${took}s" >&2
  exit 1
fi
run 0 PATH="$nt" DYNAMIC_FARM_TIMEOUT=10 -- test_ok test_ratio_ok
row test_ratio_ok PASS ''

echo "dynamic_farm gate controls: $pass rows as expected"
