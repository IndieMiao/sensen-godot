#!/usr/bin/env bash
# Start the P0 AVD headless on the host GPU (Apple M-series via Metal).
# Without -gpu host a -no-window emulator falls back to SwiftShader/llvmpipe: Godot then renders on
# the CPU (spaces take 15-25 s to open) and can't create some textures (the avatar comes out white).
set -euo pipefail
PORT="${PORT:-5570}"
SERIAL="emulator-$PORT"
if adb devices | grep -q "^$SERIAL"; then echo "$SERIAL already running"; exit 0; fi
nohup "$HOME/Library/Android/sdk/emulator/emulator" -avd P0_Test -port "$PORT" -no-window -no-audio \
  -no-boot-anim -no-snapshot -gpu host -memory 4096 -cores 4 > /tmp/p0_emulator.log 2>&1 &
adb -s "$SERIAL" wait-for-device
until [ "$(adb -s "$SERIAL" shell getprop sys.boot_completed 2>/dev/null | tr -d '\r')" = "1" ]; do sleep 2; done
adb -s "$SERIAL" shell dumpsys SurfaceFlinger | grep -m1 "GLES:"
