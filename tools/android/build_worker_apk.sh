#!/usr/bin/env bash
# Cardigan: non-store unsigned APK only. No device, signing, upload or publish command.
set -euo pipefail
umask 077
fail() { echo "worker APK: $*" >&2; exit 1; }
variant=android
if [[ ${1:-} == --dynamic-farm ]]; then variant=dynamic-farm; shift; fi
[[ $# == 1 ]] || fail 'usage: build_worker_apk.sh [--dynamic-farm] NEW_OUTPUT_DIRECTORY'
[[ $1 == /* ]] || fail 'output directory must be an absolute path'
root=$(cd "$(dirname "$0")/../.." && pwd)
cd "$root"
[[ ! -e "$1" && ! -L "$1" ]] || fail 'output directory must be new'
[[ "${ANDROID_ADB_SERVER_PORT:-5137}" == 5137 ]] || fail 'worker adb port must be 5137'
sdk=${ANDROID_HOME:?shared Android SDK required}
java=${JAVA_HOME:-/Applications/Android Studio.app/Contents/jbr/Contents/Home}
bt=${ANDROID_BUILD_TOOLS:-$sdk/build-tools/36.1.0}
[[ -x "$bt/zipalign" && -x "$bt/aapt" && -x "$java/bin/java" ]] || fail 'Android build-tools and JDK required'
templates=${GODOT_TEMPLATES_DIR:-$HOME/Library/Application Support/Godot/export_templates/4.7.2.stable}
[[ -r "$templates/android_source.zip" ]] || fail 'missing approved 4.7.2.stable android_source.zip'
templates=$(cd "$templates" && pwd)
# Inspect names only; never unpack a template carrying local signing credentials.
python3 "$root/tools/android/check_export_inputs.py" template "$templates/android_source.zip"
# Only a platform-supplied file outside source control. Never search for a token.
public_file=${CARDIGAN_MAPBOX_PUBLIC_FILE:-}
[[ $public_file == /* && -f $public_file && -r $public_file && ! -L $public_file ]] ||
    fail 'missing worker-readable managed file: CARDIGAN_MAPBOX_PUBLIC_FILE (res://mapbox_token.txt)'
# Reject the checkout (including alternative paths to it) and other Git worktrees.
for dir in "$(dirname "$public_file")" "${TMPDIR:?private TMPDIR required}" "$(dirname "$1")"; do
    [[ -d $dir ]] || fail 'existing parent directory required'
    if git -C "$(cd "$dir" && pwd -P)" rev-parse --git-dir >/dev/null 2>&1; then
        fail 'runtime input, staging and output must be outside any repository'
    fi
done
godot=$(command -v "${GODOT_BIN:-godot}") || fail 'Godot required'
[[ $("$godot" --version) == 4.7.2.stable.* ]] || fail 'Godot 4.7.2 stable required'
rev=$(git rev-parse HEAD)
# Use immutable source. Do not copy the checkout, .godot/export_credentials.cfg,
# android/build, ~/.android, existing editor settings, or Gradle signing properties.
project_files=(project.godot export_presets.cfg icon.svg icon.svg.import assets modules scenes addons native tools/android)
git ls-tree -rz --name-only "$rev" -- "${project_files[@]}" | python3 "$root/tools/android/check_export_inputs.py" tracked
work=$(mktemp -d "${TMPDIR:?private TMPDIR required}/worker-apk.XXXXXX")
trap 'rm -rf "$work"' EXIT
p=$work/project; home=$work/home; editor=$work/editor; data=$editor/editor_data
mkdir -p "$p" "$home" "$data/export_templates" "$work/tmp"
git archive "$rev" -- "${project_files[@]}" | tar -xf - -C "$p"
python3 - "$public_file" "$p/mapbox_token.txt" <<'PY'
from pathlib import Path
import re, sys
pk = Path(sys.argv[1]).read_bytes().strip()
if not re.fullmatch(rb'pk\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+', pk):
    sys.exit('worker APK: expected a public Mapbox pk token')
Path(sys.argv[2]).write_bytes(pk + b'\n')
PY
if [[ $variant == dynamic-farm ]]; then
    (cd "$p/tools/android" && python3 -B - "$p/project.godot" <<'PYPROJECT'
from pathlib import Path
import sys
from dynamic_farm_export import staged_project
p = Path(sys.argv[1]); p.write_text(staged_project(p.read_text()))
PYPROJECT
    )
fi
apk_tool=(python3 -B "$p/tools/android/worker_apk.py" --variant "$variant" --presets "$p/export_presets.cfg")
"${apk_tool[@]}" generate "$work/unsigned.cfg"
mv "$work/unsigned.cfg" "$p/export_presets.cfg"
# Portable Godot: no access needed to an account's existing editor or signing settings.
bin=$(python3 -c 'import os,sys;print(os.path.realpath(sys.argv[1]))' "$godot")
if [[ $(uname -s) == Darwin && $bin == *.app/Contents/MacOS/* ]]; then
    # A detached Mach-O loses the signed Info.plist and macOS kills it (137).
    bundle=${bin%/Contents/MacOS/*}
    ditto "$bundle" "$editor/Godot.app"
    portable="$editor/Godot.app/Contents/MacOS/${bin##*/}"
else
    portable="$editor/Godot"; cp "$bin" "$portable"
fi
touch "$editor/._sc_"
ln -s "$templates" "$data/export_templates/4.7.2.stable"
python3 - "$data/editor_settings-4.7.tres" "$sdk" "$java" <<'PY'
import json, sys
from pathlib import Path
Path(sys.argv[1]).write_text('[gd_resource type="EditorSettings" format=3]\n\n[resource]\n'
    + 'export/android/android_sdk_path = ' + json.dumps(sys.argv[2]) + '\n'
    + 'export/android/java_sdk_path = ' + json.dumps(sys.argv[3]) + '\n'
    + 'export/android/shutdown_adb_on_exit = false\n')
PY
clean=(env -i "PATH=$java/bin:$PATH" "HOME=$home" "CFFIXED_USER_HOME=$home" "TMPDIR=$work/tmp" LANG=en_US.UTF-8
    "ANDROID_HOME=$sdk" "ANDROID_SDK_ROOT=$sdk" "JAVA_HOME=$java" "GODOT_TEMPLATES_DIR=$templates"
    "ANDROID_USER_HOME=$home/.android" "GRADLE_USER_HOME=$home/.gradle" 'GRADLE_OPTS=-Dorg.gradle.daemon=false'
    "JAVA_TOOL_OPTIONS=-Duser.home=\"$home\"" ANDROID_ADB_SERVER_PORT=5137 ADB_SERVER_SOCKET=tcp:localhost:5137)
"${clean[@]}" bash "$p/tools/android/setup_android_build.sh"
for plugin in voice webview google_signin notify; do
    "${clean[@]}" python3 "$p/tools/android/prepare_${plugin}_plugin.py"
done
# No raw editor / Gradle logs in receipts or the worktree.
run_editor() {
    if ! "${clean[@]}" "$portable" --headless --path "$p" "$@" >"$work/editor.log" 2>&1 ||
       grep -Eq '^SCRIPT ERROR:|^ERROR:' "$work/editor.log"; then
        fail "Godot $1 failed"
    fi
}
run_editor --import
run_editor --export-release Android "$work/unaligned.apk"
"${clean[@]}" "${apk_tool[@]}" check-unsigned "$work/unaligned.apk"
"$bt/zipalign" -P 16 4 "$work/unaligned.apk" "$work/unsigned.apk"
"${clean[@]}" "${apk_tool[@]}" verify \
    --build-tools "$bt" "$work/unsigned.apk" > "$work/unsigned.json"
mkdir "$1" # Never replace an earlier candidate or receipt.
mv "$work/unsigned.apk" "$work/unsigned.json" "$1/"
printf '%s\n' "$rev" > "$1/source-commit.txt"
cat "$1/unsigned.json"
