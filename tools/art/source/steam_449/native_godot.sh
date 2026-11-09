#!/usr/bin/env bash
# Wrap the supplied shoot449.sh GODOT entry; preserve wall-clock timing for video.
set -euo pipefail
steam_args=()
while (($#)); do
  if [[ ${STEAM_REALTIME:-0} == 1 && $1 == --fixed-fps ]]; then shift 2; else steam_args+=("$1"); shift; fi
done
exec flock "$HOME/gs66-render.lock" "${STEAM_ENGINE:-godot}" --rendering-method mobile --rendering-driver vulkan --display-driver x11 --disable-vsync --max-fps 30 "${steam_args[@]}"
