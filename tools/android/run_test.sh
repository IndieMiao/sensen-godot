#!/usr/bin/env bash
set -euo pipefail

usage() {
    printf '%s\n' \
        'Usage: tools/android/run_test.sh [--serial SERIAL] [--clean-all] [--wait SECONDS] PACKAGE [-- COMMAND ...]' \
        'Runs an installed com.sensen.* app; stops it before launch and on exit.' \
        'Without COMMAND or --wait, press Enter to finish a manual test.' \
        '--clean-all alone stops all com.sensen.* apps on the selected device.'
}

adb_bin="${ADB:-adb}"
serial="${JOURNEY_SERIAL:-${DEV:-emulator-5560}}"
package=''
duration=''
clean_all=false
command_args=()
while (($#)); do
    case "$1" in
        --help|-h) usage; exit 0 ;;
        --serial|--wait)
            (($# >= 2)) || { usage >&2; exit 2; }
            if [[ "$1" == --serial ]]; then serial="$2"; else duration="$2"; fi
            shift 2 ;;
        --clean-all) clean_all=true; shift ;;
        --) shift; command_args=("$@"); break ;;
        -*) printf 'Unknown option: %s\n' "$1" >&2; exit 2 ;;
        *)
            [[ -z "$package" ]] || { printf 'Separate the test command with --\n' >&2; exit 2; }
            package="$1"; shift ;;
    esac
done
[[ -n "$serial" ]] || { printf 'A device serial is required.\n' >&2; exit 2; }
if [[ -n "$package" && ! "$package" =~ ^com\.sensen\.[a-zA-Z0-9_]+(\.[a-zA-Z0-9_]+)*$ ]]; then
    printf 'Expected a com.sensen.* package.\n' >&2; exit 2
fi
if [[ -n "$duration" ]]; then
    [[ "$duration" =~ ^[0-9]{1,4}$ ]] && ((10#$duration >= 1 && 10#$duration <= 3600)) || {
        printf '%s\n' '--wait must be 1..3600 seconds.' >&2; exit 2;
    }
    ((${#command_args[@]} == 0)) || { printf 'Use --wait or a test command.\n' >&2; exit 2; }
fi
if [[ -z "$package" ]]; then
    $clean_all && [[ -z "$duration" ]] && ((${#command_args[@]} == 0)) || { usage >&2; exit 2; }
elif [[ -z "$duration" ]] && ((${#command_args[@]} == 0)) && [[ ! -t 0 ]]; then
    printf 'Noninteractive runs need --wait or a test command.\n' >&2; exit 2
fi

"$adb_bin" -s "$serial" get-state >/dev/null
if $clean_all; then
    packages=$("$adb_bin" -s "$serial" shell pm list packages com.sensen.)
    while IFS= read -r line; do
        candidate="${line#package:}"
        candidate="${candidate%$'\r'}"
        if [[ "$candidate" =~ ^com\.sensen\.[a-zA-Z0-9_]+(\.[a-zA-Z0-9_]+)*$ ]]; then
            "$adb_bin" -s "$serial" shell am force-stop "$candidate"
        fi
    done <<< "$packages"
fi
[[ -n "$package" ]] || exit 0

test_pid=''
cleanup() {
    result=$?
    trap - EXIT INT TERM HUP
    # Monitor mode gives the test command its own process group, including helpers.
    if [[ -n "$test_pid" ]]; then
        kill -TERM -- "-$test_pid" 2>/dev/null || true
        for attempt in 1 2 3 4 5 6 7 8 9 10; do
            kill -0 -- "-$test_pid" 2>/dev/null || break
            sleep 0.1
        done
        kill -KILL -- "-$test_pid" 2>/dev/null || true
        wait "$test_pid" 2>/dev/null || true
    fi
    if ! "$adb_bin" -s "$serial" shell am force-stop "$package"; then
        printf 'Cleanup failed for %s on %s.\n' "$package" "$serial" >&2
        if ((result == 0)); then result=1; fi
    fi
    exit "$result"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
trap 'exit 129' HUP

"$adb_bin" -s "$serial" shell am force-stop "$package"
component=$("$adb_bin" -s "$serial" shell cmd package resolve-activity --brief "$package" | tr -d '\r' | tail -n 1)
[[ "$component" == "$package/"* ]] || { printf 'No launcher for %s.\n' "$package" >&2; exit 1; }
launch=$("$adb_bin" -s "$serial" shell am start -W -n "$component")
printf '%s\n' "$launch"
[[ "$launch" == *'Status: ok'* ]] || { printf 'App launch did not succeed.\n' >&2; exit 1; }
export JOURNEY_SERIAL="$serial" JOURNEY_PACKAGE="$package"
if ((${#command_args[@]})); then
    set -m
    "${command_args[@]}" &
    test_pid=$!
    wait "$test_pid"
elif [[ -n "$duration" ]]; then
    set -m
    sleep "$duration" &
    test_pid=$!
    wait "$test_pid"
else
    printf 'Testing %s on %s. Press Enter to finish.\n' "$package" "$serial"
    read -r finish || true
fi
