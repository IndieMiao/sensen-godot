#!/usr/bin/env bash
# P0 prototype on an Android emulator/device, isolated from the Journey app:
#   tools/p0/android_p0.sh [SERIAL]        (default emulator-5570; build + install + launch)
#   SKIP_BUILD=1 tools/p0/android_p0.sh    (reinstall the last APK)
# Exports preset "Android" with package com.sensen.p0proto (export_presets.cfg is restored afterwards),
# reverses tcp:3110 to the local P0 server (cd server && node --import tsx tools/p0_server.ts),
# drops the user://p0_boot marker so the app opens the P0 farm, then launches it.
set -euo pipefail
cd "$(dirname "$0")/../.."
SERIAL="${1:-${SERIAL:-emulator-5570}}"
PKG=com.sensen.p0proto
APK=build/p0-debug.apk
if [[ "${SKIP_BUILD:-0}" != 1 ]]; then
  cp export_presets.cfg /tmp/p0_export_presets.cfg.bak
  trap 'cp /tmp/p0_export_presets.cfg.bak export_presets.cfg' EXIT
  python3 - <<'PY'
import re
p = 'export_presets.cfg'; s = open(p).read()
i = s.index('name="Android"'); j = s.index('[preset.1]') if '[preset.1]' in s else len(s)
seg = s[i:j].replace('package/unique_name="com.sensen.journeypreview"', 'package/unique_name="com.sensen.p0proto"')
seg = re.sub(r'package/name="[^"]*"', 'package/name="P0 Proto"', seg)
open(p, 'w').write(s[:i] + seg + s[j:])
PY
  mkdir -p build
  godot --headless --path . --import > /tmp/p0_import.log 2>&1 || true
  godot --headless --path . --export-debug "Android" "$APK" > /tmp/p0_export.log 2>&1
  cp /tmp/p0_export_presets.cfg.bak export_presets.cfg
  trap - EXIT
fi
adb start-server > /dev/null 2>&1 || true
adb -s "$SERIAL" install -r "$APK"
adb -s "$SERIAL" reverse tcp:3110 tcp:3110
adb -s "$SERIAL" shell monkey -p "$PKG" -c android.intent.category.LAUNCHER 1 > /dev/null 2>&1 || true
sleep 6
adb -s "$SERIAL" shell run-as "$PKG" mkdir -p files
adb -s "$SERIAL" shell run-as "$PKG" touch files/p0_boot
adb -s "$SERIAL" shell am force-stop "$PKG"
adb -s "$SERIAL" shell monkey -p "$PKG" -c android.intent.category.LAUNCHER 1 > /dev/null 2>&1
echo "P0 launched on $SERIAL ($PKG); server must be on host :3110"
