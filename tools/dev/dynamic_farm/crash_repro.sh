#!/usr/bin/env bash
# C-111: drive the dynamic farm Android package through the paths suspected of the 0.4.2 crash and record
# memory, crash logs and the system's exit reasons. Needs an already running emulator (or a test device you own)
# with the package installed and an account that has a home; it does not start, stop or install anything else.
#
#   tools/dev/dynamic_farm/crash_repro.sh --port 5137 --serial emulator-5560 --out DIR [--package PKG] [--rounds N]
#
# In a Cardigan Run --port defaults to $ANDROID_ADB_SERVER_PORT and --serial to $ANDROID_SERIAL, else
# $CARDIGAN_EMULATOR_SERIAL, else $CARDIGAN_DEVICE_SERIAL (C-212); without them both stay required.
#
# Paths (each round): pan and double-tap zoom over the map while buildings load; open the selected parcel in 3D and
# go Back; Home then relaunch (background/foreground); screen off/on. Godot draws its own buttons, so taps use screen
# fractions: override BUILDING_AT / PREVIEW_AT / RESET_AT ("x,y" in 0..1) after checking a screenshot.
# PAN_PASSES (default 3) pan/zoom passes per round; 0 keeps the view on BUILDING_AT so every round enters 3D.
# Output in DIR: meminfo.csv (TOTAL PSS / RSS in KiB every SAMPLE_SECONDS), logcat.txt, exit-info-{before,after}.txt,
# pids.txt (one line per sample: the app pid; a change means the process died), events.txt and summary.txt.
set -euo pipefail

port=${ANDROID_ADB_SERVER_PORT:-} serial=${ANDROID_SERIAL:-${CARDIGAN_EMULATOR_SERIAL:-${CARDIGAN_DEVICE_SERIAL:-}}} out='' package='com.gensen.mapfarm.internal' rounds=10
while (($#)); do
  case "$1" in
    --port) port=$2; shift 2 ;;
    --serial) serial=$2; shift 2 ;;
    --out) out=$2; shift 2 ;;
    --package) package=$2; shift 2 ;;
    --rounds) rounds=$2; shift 2 ;;
    *) printf 'Unknown argument: %s\n' "$1" >&2; exit 2 ;;
  esac
done
# Project machine rule: never the default adb server (5037) and never an implicit device.
[[ $port =~ ^[0-9]+$ && $port != 5037 && -n $serial && -n $out ]] || {
  printf 'Required: --port (not 5037) --serial --out\n' >&2; exit 2; }
# This project's packages only: com.sensen.*, and the dynamic farm's com.gensen.mapfarm[.internal] (C-142, C-216).
[[ $package =~ ^(com\.sensen\.[a-zA-Z0-9_.]+|com\.gensen\.mapfarm(\.internal)?)$ && $rounds =~ ^[0-9]+$ ]] || {
  printf 'Bad --package or --rounds\n' >&2; exit 2; }
ADB=${ADB:-adb}
SAMPLE_SECONDS=${SAMPLE_SECONDS:-2}
BUILDING_AT=${BUILDING_AT:-0.5,0.45}
PREVIEW_AT=${PREVIEW_AT:-0.5,0.88}
RESET_AT=${RESET_AT:-0.5,0.12}
PAN_PASSES=${PAN_PASSES:-3}
mkdir -p "$out"
a() { "$ADB" -P "$port" -s "$serial" "$@"; }
log() { printf '%s %s\n' "$(date -u +%H:%M:%S)" "$*" | tee -a "$out/events.txt"; }

read -r W H < <(a shell wm size | awk -F'[ x]' '/Physical size/ {print $3, $4}')
at() { awk -v p="$1" -v w="$W" -v h="$H" 'BEGIN { split(p, f, ","); printf "%d %d", f[1] * w, f[2] * h }'; }
tap() { local xy; xy=$(at "$1"); a shell input tap $xy; }
# One shell for both taps: two adb round trips can exceed the double-tap window.
double_tap() { local xy; xy=$(at "$1"); a shell "input tap $xy; input tap $xy"; }
drag() { a shell input swipe $(at "$1") $(at "$2") "${3:-400}"; }
app_pid() { a shell pidof "$package" 2>/dev/null | tr -d '\r' || true; }

sampler() {
  printf 'utc,pid,total_pss_kb,total_rss_kb\n' > "$out/meminfo.csv"
  while :; do
    local pid pss rss
    pid=$(app_pid)
    if [[ -n $pid ]]; then
      pss='' rss=''
      read -r pss rss < <(a shell dumpsys meminfo "$package" | awk '/TOTAL PSS:/ {print $3, $6; exit} /^ *TOTAL / {print $2, $(NF-1); exit}') || true
      printf '%s,%s,%s,%s\n' "$(date -u +%H:%M:%S)" "$pid" "${pss:-}" "${rss:-}" >> "$out/meminfo.csv"
    else
      printf '%s,,,\n' "$(date -u +%H:%M:%S)" >> "$out/meminfo.csv"
    fi
    printf '%s\n' "${pid:-none}" >> "$out/pids.txt"
    sleep "$SAMPLE_SECONDS"
  done
}

a shell dumpsys activity exit-info "$package" > "$out/exit-info-before.txt" || true
a logcat -b all -c || true
# Started directly, not through a(): $! must be adb itself so cleanup can stop it.
"$ADB" -P "$port" -s "$serial" logcat -b all -v threadtime > "$out/logcat.txt" &
logcat_pid=$!
sampler &
sampler_pid=$!
cleanup() { kill "$sampler_pid" "$logcat_pid" 2>/dev/null || true; wait "$sampler_pid" "$logcat_pid" 2>/dev/null || true; }
trap cleanup EXIT

a shell monkey -p "$package" -c android.intent.category.LAUNCHER 1 > /dev/null
log "launched"; sleep 20
first_pid=$(app_pid); log "pid $first_pid"

for ((i = 1; i <= rounds; i++)); do
  log "round $i: pan and zoom while buildings load"
  for ((pass = 0; pass < PAN_PASSES; pass++)); do
    drag 0.3,0.5 0.7,0.4; drag 0.7,0.6 0.3,0.5; double_tap 0.5,0.5; sleep 1
  done
  tap "$RESET_AT"; sleep 3
  log "round $i: select and open 3D"
  tap "$BUILDING_AT"; sleep 3
  tap "$PREVIEW_AT"; sleep 12
  log "round $i: back to map"
  a shell input keyevent KEYCODE_BACK; sleep 8
  log "round $i: background and foreground"
  a shell input keyevent KEYCODE_HOME; sleep 5
  a shell monkey -p "$package" -c android.intent.category.LAUNCHER 1 > /dev/null; sleep 10
  log "round $i: screen off and on"
  a shell input keyevent KEYCODE_SLEEP; sleep 5
  a shell input keyevent KEYCODE_WAKEUP; a shell wm dismiss-keyguard 2>/dev/null || true; sleep 10
  pid=$(app_pid)
  if [[ $pid != "$first_pid" ]]; then log "round $i: app process changed ($first_pid -> ${pid:-none})"; break; fi
done
sleep "$SAMPLE_SECONDS"
cleanup; trap - EXIT
a shell dumpsys activity exit-info "$package" > "$out/exit-info-after.txt" || true
{
  printf 'package %s serial %s rounds %s screen %sx%s\n' "$package" "$serial" "$rounds" "$W" "$H"
  printf 'first pid %s, last pid %s\n' "$first_pid" "$(app_pid)"
  awk -F, 'NR > 1 && $3 != "" { if ($3 > m) { m = $3; t = $1 } } END { printf "peak TOTAL PSS %d KiB (%.0f MiB) at %s\n", m, m / 1024, t }' "$out/meminfo.csv"
  # Map setups: each accepted manifest sets up the parcel sources again (selection_controller.activate). Up to 0.4.2
  # every setup also added a fresh buildings.geojson source; since C-118 native logs whether it fetched or reused it.
  printf 'map source setups: %s\n' "$(grep -c 'DYNAMIC_LOAD.*client_manifest.*validation_accepted' "$out/logcat.txt" || true)"
  printf 'building file fetches (ADD/REPLACE): %s, reuses: %s, parses finished: %s\n' \
    "$(grep -cE 'DYNAMIC_BUILDINGS_SOURCE (ADD|REPLACE)' "$out/logcat.txt" || true)" \
    "$(grep -c 'DYNAMIC_BUILDINGS_SOURCE REUSE' "$out/logcat.txt" || true)" \
    "$(grep -c 'DYNAMIC_BUILDINGS_SOURCE LOADED' "$out/logcat.txt" || true)"
  # C-124: Retry or the building load timeout replaces a copy still loading (refetch=true); a replaced copy's late
  # events are logged STALE and change nothing.
  printf 'building refetches: %s, stale events ignored: %s\n' \
    "$(grep -c 'DYNAMIC_BUILDINGS_SOURCE REPLACE.*refetch=true' "$out/logcat.txt" || true)" \
    "$(grep -c 'DYNAMIC_BUILDINGS_SOURCE STALE' "$out/logcat.txt" || true)"
  # From setting the map's sources to its building layer loading: the wait before a building can be tapped.
  printf 'building layer waits (ms): %s\n' \
    "$(grep 'DYNAMIC_LOAD.*"resource":"buildings","stage":"ready"' "$out/logcat.txt" | grep -o '"elapsed_ms":[0-9]*' | sed 's/.*://' | tr '\n' ' ' || true)"
  printf -- '--- crash / kill lines\n'
  grep -E 'Fatal signal|FATAL EXCEPTION|lowmemorykiller|lmkd|Low on memory|ANR in|Process .*'"$package"'.* has died|vkAcquireNextImage|VK_ERROR' "$out/logcat.txt" | head -40 || true
} > "$out/summary.txt"
cat "$out/summary.txt"
