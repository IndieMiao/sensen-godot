#!/usr/bin/env bash
# Emit elapsed wall time even when the wrapped step fails; preserve its status.
set -eu
phase=$1
shift
start=$SECONDS
trap 'rc=$?; printf "%s: %ss (exit %s)\n" "$phase" "$((SECONDS-start))" "$rc" | tee -a "${GITHUB_STEP_SUMMARY:-/dev/null}"' EXIT
"$@"
