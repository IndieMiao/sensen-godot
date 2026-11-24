#!/usr/bin/env bash
# P0 prototype on an Android emulator/device, isolated from the Journey app:
#   tools/p0/android_p0.sh [SERIAL]        (default emulator-5570; build + install + launch)
#   SKIP_BUILD=1 tools/p0/android_p0.sh    (reinstall the last APK)
#   ADB_PORT=5039 tools/p0/android_p0.sh 10AFAF162200319   (the vivo phone sits on the 5039 adb server;
#                                          5037 gets restarted by other sessions)
# Exports preset "Android" with package com.sensen.p0proto (export_presets.cfg is restored afterwards),
# reverses tcp:3110 to the local P0 server (cd server && node --import tsx tools/p0_server.ts),
# drops the user://p0_boot marker so the app opens the P0 farm, then launches it.
# Godot runs from a copy whose editor settings keep the adb server up after the export (godot_keep_adb.sh, C-79),
# so the export does not drop emulators on a shared adb port.
set -euo pipefail
cd "$(dirname "$0")/../.."
SERIAL="${1:-${SERIAL:-emulator-5570}}"
adb() { command adb ${ADB_PORT:+-P "$ADB_PORT"} "$@"; }
PKG=com.sensen.p0proto
APK=build/p0-debug.apk
if [[ "${SKIP_BUILD:-0}" != 1 ]]; then
  cp export_presets.cfg /tmp/p0_export_presets.cfg.bak
  GODOT_DIR="$(mktemp -d "${TMPDIR:-/tmp}/p0_godot.XXXXXX")"
  trap 'cp /tmp/p0_export_presets.cfg.bak export_presets.cfg; rm -rf "$GODOT_DIR"' EXIT
  source tools/p0/godot_keep_adb.sh
  p0_godot_keep_adb "${GODOT_BIN:-godot}" "$GODOT_DIR"
  python3 - <<'PY'
import re
p = 'export_presets.cfg'; s = open(p).read()
i = s.index('name="Android"'); j = s.index('[preset.1]') if '[preset.1]' in s else len(s)
seg = s[i:j].replace('package/unique_name="com.sensen.journeypreview"', 'package/unique_name="com.sensen.p0proto"')
seg = re.sub(r'package/name="[^"]*"', 'package/name="P0 Proto"', seg)
open(p, 'w').write(s[:i] + seg + s[j:])
PY
  mkdir -p build
  "$P0_GODOT" --headless --path . --import > /tmp/p0_import.log 2>&1 || true
  "$P0_GODOT" --headless --path . --export-debug "Android" "$APK" > /tmp/p0_export.log 2>&1
  cp /tmp/p0_export_presets.cfg.bak export_presets.cfg; rm -rf "$GODOT_DIR"
  trap - EXIT
fi
adb start-server > /dev/null 2>&1 || true
if adb -s "$SERIAL" shell dumpsys SurfaceFlinger 2>/dev/null | grep -m1 "GLES:" | grep -qi "swiftshader"; then
  echo "WARNING: $SERIAL renders in software (SwiftShader). Restart it with tools/p0/start_emulator.sh (-gpu host):" >&2
  echo "         slow space loads and a white, untextured avatar are emulator artefacts in this mode." >&2
fi
adb -s "$SERIAL" install -r "$APK"
adb -s "$SERIAL" reverse tcp:3110 tcp:3110
adb -s "$SERIAL" shell monkey -p "$PKG" -c android.intent.category.LAUNCHER 1 > /dev/null 2>&1 || true
sleep 6
adb -s "$SERIAL" shell run-as "$PKG" mkdir -p files
adb -s "$SERIAL" shell run-as "$PKG" touch files/p0_boot
adb -s "$SERIAL" shell am force-stop "$PKG"
adb -s "$SERIAL" shell monkey -p "$PKG" -c android.intent.category.LAUNCHER 1 > /dev/null 2>&1
echo "P0 launched on $SERIAL ($PKG); server must be on host :3110"
