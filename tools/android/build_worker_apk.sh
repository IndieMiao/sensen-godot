#!/usr/bin/env bash
# Cardigan: non-store unsigned APK only. No device, signing, upload or publish command.
set -euo pipefail
umask 077
fail() { echo "worker APK: $*" >&2; exit 1; }
usage='usage: build_worker_apk.sh [--dynamic-farm | --dynamic-farm-internal APPROVED_TARGET | --dynamic-farm-release] NEW_OUTPUT_DIRECTORY'
variant=android target=
case ${1:-} in
    --dynamic-farm) variant=dynamic-farm; shift ;;
    # Internal test package only: Journey at an approved isolated test service (C-39).
    --dynamic-farm-internal) (($# >= 2)) || fail "$usage"; variant=dynamic-farm-internal target=$2; shift 2 ;;
    # Invite-only release package (C-98): the preview's package, Journey fixed to the production service.
    --dynamic-farm-release) variant=dynamic-farm-release; shift ;;
esac
[[ $# == 1 ]] || fail "$usage"
[[ $1 == /* ]] || fail 'output directory must be an absolute path'
root=$(cd "$(dirname "$0")/../.." && pwd)
cd "$root"
if [[ $variant == dynamic-farm-internal ]]; then
    # Refuse an unapproved target before any staging, tool or network use.
    python3 -B "$root/tools/android/dynamic_farm_export.py" check-target "$target" || exit 1
fi
[[ ! -e "$1" && ! -L "$1" ]] || fail 'output directory must be new'
# The Run's own adb port when the host assigns one (C-212), else the workers' shared 5137. Never 5037.
adb_port=${ANDROID_ADB_SERVER_PORT:-5137}
[[ $adb_port =~ ^[1-9][0-9]{3,4}$ ]] && ((adb_port <= 65535 && adb_port != 5037)) ||
    fail 'ANDROID_ADB_SERVER_PORT must be a private adb port (1000..65535, not 5037)'
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
# tools/app_icon/android: farm-dev's P0 launcher icon, used by the dynamic farm packages (C-142).
project_files=(project.godot export_presets.cfg icon.svg icon.svg.import assets modules scenes addons native tools/android
    tools/app_icon/android)
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
if [[ $variant == dynamic-farm* ]]; then
    (cd "$p/tools/android" && python3 -B - "$p/project.godot" "$target" "$variant" <<'PYPROJECT'
from pathlib import Path
import sys
from dynamic_farm_export import staged_project
p = Path(sys.argv[1])
p.write_text(staged_project(p.read_text(), sys.argv[2] or None, sys.argv[3] == 'dynamic-farm-release'))
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
    "JAVA_TOOL_OPTIONS=-Duser.home=\"$home\"" "ANDROID_ADB_SERVER_PORT=$adb_port" "ADB_SERVER_SOCKET=tcp:localhost:$adb_port")
"${clean[@]}" bash "$p/tools/android/setup_android_build.sh"
for plugin in voice webview google_signin notify; do
    "${clean[@]}" python3 "$p/tools/android/prepare_${plugin}_plugin.py"
done
# Reuse a host-provided, sha256-verified Gradle wrapper distribution (C-64); otherwise download as before.
seed_tool=(python3 -B "$p/tools/android/gradle_dist_seed.py")
"${seed_tool[@]}" seed "$p/android/build/gradle/wrapper/gradle-wrapper.properties" "$home/.gradle" "$work/gradle-seed.json"
# No raw editor / Gradle logs in receipts or the worktree.
run_editor() {
    local rc=0 pattern='^SCRIPT ERROR:|^ERROR:'
    # A cold scan opens the theme before its font has been imported and legacy
    # FBX assets can report missing optional textures. Use the reviewed CI
    # import gate for that phase; export still rejects every editor error.
    if [[ $1 == --import ]]; then
        pattern='SCRIPT ERROR:|ERROR: (Error importing|Failed to import|Failed to (create|instantiate) an autoload)'
    fi
    "${clean[@]}" "$portable" --headless --path "$p" "$@" >"$work/editor.log" 2>&1 || rc=$?
    if ((rc)) || grep -Eq "$pattern" "$work/editor.log"; then
        # Never echo Gradle / editor lines: they can contain runtime configuration.
        for diagnostic in 'Error importing' 'Failed to import' 'Failed to create an autoload' 'SCRIPT ERROR:' \
            'UnknownHostException' 'SSLHandshakeException' 'ConnectException' 'Could not resolve' \
            'Could not find' 'Could not download' 'Could not GET' 'Gradle build failed' 'Execution failed for task' \
            'Unresolved reference' 'Could not install Gradle distribution' 'No space left on device'; do
            if grep -Fq "$diagnostic" "$work/editor.log"; then echo "worker APK: diagnostic: $diagnostic" >&2; fi
        done
        fail "Godot $1 failed (editor exit=$rc)"
    fi
}
run_editor --import
run_editor --export-release Android "$work/unaligned.apk"
"${seed_tool[@]}" check "$work/gradle-seed.json"
"${clean[@]}" "${apk_tool[@]}" check-unsigned "$work/unaligned.apk"
"$bt/zipalign" -P 16 4 "$work/unaligned.apk" "$work/unsigned.apk"
"${clean[@]}" "${apk_tool[@]}" verify --source-commit "$rev" \
    --build-tools "$bt" "$work/unsigned.apk" > "$work/unsigned.json"
mkdir "$1" # Never replace an earlier candidate or receipt.
mv "$work/unsigned.apk" "$work/unsigned.json" "$1/"
printf '%s\n' "$rev" > "$1/source-commit.txt"
cat "$1/unsigned.json"
