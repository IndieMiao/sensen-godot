#!/usr/bin/env bash
# AVD state belongs to this worktree. Does not stop adb, apps or other emulators.
set -euo pipefail
pond_root="$(cd "$(dirname "$0")/../.." && pwd)"
pond_sdk="${ANDROID_SDK_ROOT:-$HOME/Library/Android/sdk}"
pond_avd_root="$pond_root/output/pond-pitch-2026-09-25/avd"
pond_port="${POND_AVD_PORT:-5580}"
pond_template="${POND_AVD_TEMPLATE:-$HOME/.android/avd/Pixel_9_Pro.avd/config.ini}"
# GPU mode for `emulator -gpu`; a machine binding may set SENSEN_EMULATOR_GPU (Steam Deck: host). Default unchanged.
pond_gpu="${SENSEN_EMULATOR_GPU:-host}"
export ADB_SERVER_SOCKET="tcp:localhost:${POND_ADB_PORT:-5041}"
export ANDROID_ADB_SERVER_PORT="${POND_ADB_PORT:-5041}"
[[ "$pond_port" =~ ^[0-9]+$ ]] && ((pond_port >= 5554 && pond_port <= 5682 && pond_port % 2 == 0)) || {
    echo 'POND_AVD_PORT must be an even number in 5554..5682.' >&2; exit 2;
}
[[ "$pond_gpu" =~ ^[A-Za-z0-9][A-Za-z0-9_-]*$ ]] || {
    echo 'SENSEN_EMULATOR_GPU must be one emulator -gpu mode starting with a letter or digit, e.g. host or swiftshader_indirect.' >&2; exit 2;
}
if "$pond_root/tools/android/pond_art_adb.sh" -s "emulator-$pond_port" get-state >/dev/null 2>&1; then
    echo "Port $pond_port is already in use; keeping that emulator intact."
    "$pond_sdk/platform-tools/adb" -s "emulator-$pond_port" emu avd name
    exit 0
fi
python3 - "$pond_template" "$pond_avd_root" <<'PY'
import re, sys
from pathlib import Path
source, root = map(Path, sys.argv[1:])
avd = root / 'Sensen_Pond_Art.avd'
avd.mkdir(parents=True, exist_ok=True)
if not (avd / 'config.ini').exists():
    config = source.read_text()
    settings = {
        'AvdId': 'Sensen_Pond_Art', 'avd.ini.displayname': 'Gensen Pond Art',
        'hw.lcd.width': '1280', 'hw.lcd.height': '800', 'hw.lcd.density': '160',
        'hw.initialOrientation': 'landscape', 'hw.cpu.ncore': '2',
        'hw.camera.back': 'none', 'hw.camera.front': 'none',
        'disk.dataPartition.size': '3G', 'hw.gpu.mode': 'host',
        'showDeviceFrame': 'no', 'skin.name': '1280x800', 'skin.path': '',
    }
    for key, value in settings.items():
        config = re.sub(r'^' + re.escape(key) + r'=.*$', lambda m: key + '=' + value, config, flags=re.M)
    (avd / 'config.ini').write_text(config)
    (root / 'Sensen_Pond_Art.ini').write_text('avd.ini.encoding=UTF-8\npath=' + str(avd) + '\ntarget=android-37.0\n')
PY
exec env ANDROID_AVD_HOME="$pond_avd_root" "$pond_sdk/emulator/emulator" \
    -avd Sensen_Pond_Art -port "$pond_port" -no-window -no-snapshot -no-audio \
    -no-boot-anim -gpu "$pond_gpu" -memory 2048 -cores 2
