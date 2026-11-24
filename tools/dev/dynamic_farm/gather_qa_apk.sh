#!/usr/bin/env bash
# Emulator QA package for one's own parcel on the device save (C-60 outer gathering).
# One ABI, signed with a throwaway debug key made here, package com.sensen.dynamicfarm.gatherqa,
# main scene tools/dev/dynamic_farm/own_parcel_qa.tscn. No map, Mapbox, plugin, account or server:
# Net stays off (online_qa) and both Journey URLs point at a closed local port. Never deliver it.
#
#   [GATHER_QA_ABI=x86_64|arm64-v8a] tools/dev/dynamic_farm/gather_qa_apk.sh NEW_OUTPUT_DIR [PARCEL] [IMPORTED_CHECKOUT]
#
# PARCEL is an r4 fixture name (default p-3139010). IMPORTED_CHECKOUT, a checkout of the same
# commit already imported headless, lends its .godot cache so the import only checks changes.
# GATHER_QA_ABI follows the emulator image; by default it is the host's own architecture
# (x86_64 on x86_64 hosts such as cardigan-ci, arm64-v8a on Apple silicon such as mac-mini).
# On macOS the copied editor is re-signed ad hoc (the copy's signature is otherwise invalid and
# the system kills it) and templates default to ~/Library/Application Support/Godot.
# Staging is a disposable copy under $TMPDIR (committed sources at HEAD); nothing in the
# checkout, the editor settings or ~/.android is touched.
set -euo pipefail
fail() { echo "gather QA APK: $*" >&2; exit 1; }
(($# >= 1)) || fail 'usage: gather_qa_apk.sh NEW_OUTPUT_DIR [PARCEL] [IMPORTED_CHECKOUT]'
out=$1 parcel=${2:-p-3139010} cache=${3:-}
[[ $out == /* && ! -e $out ]] || fail 'output directory must be a new absolute path'
[[ $parcel =~ ^p-[A-Za-z0-9*-]+$ ]] || fail 'parcel must be an r4 fixture name'
root=$(cd "$(dirname "$0")/../../.." && pwd)
cd "$root"
[[ -f tests/dynamic_farm/fixtures/r4/$parcel.json ]] || fail "no fixture $parcel"
os=$(uname -s)
case $(uname -m) in arm64 | aarch64) host_abi=arm64-v8a ;; *) host_abi=x86_64 ;; esac
abi=${GATHER_QA_ABI:-$host_abi}
case $abi in
x86_64) x86_64=true arm64=false ;;
arm64-v8a) x86_64=false arm64=true ;;
*) fail 'GATHER_QA_ABI must be x86_64 or arm64-v8a' ;;
esac
godot=$(command -v "${GODOT_BIN:-godot}") || fail 'Godot required'
[[ $("$godot" --version) == 4.7.2.stable.* ]] || fail 'Godot 4.7.2 stable required'
sdk=${ANDROID_HOME:?Android SDK required}
java=${JAVA_HOME:?JDK required}
if [[ $os == Darwin ]]; then
    templates=${GODOT_TEMPLATES_DIR:-$HOME/Library/Application Support/Godot/export_templates/4.7.2.stable}
else
    templates=${GODOT_TEMPLATES_DIR:-$HOME/.local/share/godot/export_templates/4.7.2.stable}
fi
[[ -r $templates/android_debug.apk ]] || fail 'missing 4.7.2.stable android_debug.apk template'
rev=$(git rev-parse HEAD)
work=$(mktemp -d "${TMPDIR:?private TMPDIR required}/gather-qa.XXXXXX")
trap 'rm -rf "$work"' EXIT
p=$work/project editor=$work/editor home=$work/home
mkdir -p "$p" "$editor/editor_data/export_templates" "$home"
git archive "$rev" -- project.godot icon.svg icon.svg.import assets modules scenes addons \
    tools/dev/dynamic_farm tests/dynamic_farm/fixtures/r4 | tar -xf - -C "$p"
if [[ -n $cache ]]; then
    [[ -d $cache/.godot/imported ]] || fail 'IMPORTED_CHECKOUT has no .godot/imported'
    cp -a "$cache/.godot" "$p/.godot"
    rm -f "$p/.godot/export_credentials.cfg"
fi
python3 -I - "$p/project.godot" "$parcel" <<'PY'
import re, sys
from pathlib import Path
path, parcel = Path(sys.argv[1]), sys.argv[2]
text = path.read_text()
def one(pattern, repl):
    global text
    text, n = re.subn(pattern, repl, text, flags=re.M)
    if n != 1: sys.exit('gather QA APK: unexpected project setting ' + pattern)
one(r'^run/main_scene="[^"]+"$', 'run/main_scene="res://tools/dev/dynamic_farm/own_parcel_qa.tscn"')
one(r'^\[application\]$', '[application]\nconfig/use_custom_user_dir=true\nconfig/custom_user_dir_name="DynamicFarmGatherQa"')
one(r'^\[sensen\]$', '[sensen]\nnetwork/online_qa=true\ndynamic_farm/local_farm_save=true\n'
    f'dynamic_farm/qa_parcel="res://tests/dynamic_farm/fixtures/r4/{parcel}.json"')
for key in ('network/base_url', 'network/mobile_base_url'):
    one(rf'^{key}="[^"]+"$', f'{key}="http://127.0.0.1:9"')
path.write_text(text)
PY
cat > "$p/export_presets.cfg" <<CFG
[preset.0]

name="Android QA"
platform="Android"
runnable=true
advanced_options=false
dedicated_server=false
custom_features=""
export_filter="all_resources"
include_filter="assets/farm/data/*.json,assets/p0/*.json,assets/dynamic_farm/*.json,assets/avatar/*.json,modules/dynamic_farm/map/config.json,tests/dynamic_farm/fixtures/r4/*.json,assets/localization/*.json,assets/ui/fonts/*.txt"
exclude_filter="addons/gdUnit4/*,assets/avatar/source/*.fbx"
export_path=""
patches=PackedStringArray()
encryption_include_filters=""
encryption_exclude_filters=""
seed=0
encrypt_pck=false
encrypt_directory=false
script_export_mode=2

[preset.0.options]

custom_template/debug=""
custom_template/release=""
gradle_build/use_gradle_build=false
architectures/armeabi-v7a=false
architectures/arm64-v8a=$arm64
architectures/x86=false
architectures/x86_64=$x86_64
version/code=1
version/name="gather-qa"
package/unique_name="com.sensen.dynamicfarm.gatherqa"
package/name="Gather QA"
package/signed=true
package/retain_data_on_uninstall=false
screen/immersive_mode=true
permissions/internet=false
CFG
PATH="$java/bin:$PATH" keytool -genkeypair -keystore "$work/qa.keystore" -alias gatherqa -storepass android -keypass android \
    -dname CN=GatherQA -keyalg RSA -keysize 2048 -validity 30 >/dev/null 2>&1 || fail 'keytool failed'
# Portable editor: its own settings, never the account's.
cp "$(python3 -c 'import os,sys;print(os.path.realpath(sys.argv[1]))' "$godot")" "$editor/Godot"
[[ $os != Darwin ]] || codesign --force --sign - "$editor/Godot" >/dev/null 2>&1 || fail 'codesign of the editor copy failed'
touch "$editor/._sc_"
ln -s "$templates" "$editor/editor_data/export_templates/4.7.2.stable"
cat > "$editor/editor_data/editor_settings-4.7.tres" <<TRES
[gd_resource type="EditorSettings" format=3]

[resource]
export/android/android_sdk_path = "$sdk"
export/android/java_sdk_path = "$java"
export/android/shutdown_adb_on_exit = false
TRES
run() {
    env -i "PATH=$java/bin:$PATH" "HOME=$home" "TMPDIR=$work" LANG=en_US.UTF-8 "ANDROID_HOME=$sdk" \
        "JAVA_HOME=$java" "ANDROID_ADB_SERVER_PORT=${ANDROID_ADB_SERVER_PORT:-5137}" \
        GODOT_ANDROID_KEYSTORE_DEBUG_PATH="$work/qa.keystore" GODOT_ANDROID_KEYSTORE_DEBUG_USER=gatherqa \
        GODOT_ANDROID_KEYSTORE_DEBUG_PASSWORD=android "$editor/Godot" --headless --path "$p" "$@" >>"$work/editor.log" 2>&1
}
run --import || { tail -20 "$work/editor.log" >&2; fail 'import failed'; }
run --export-debug "Android QA" "$work/gather-qa.apk" || { tail -30 "$work/editor.log" >&2; fail 'export failed'; }
grep -q 'SCRIPT ERROR' "$work/editor.log" && { grep 'SCRIPT ERROR' -A2 "$work/editor.log" >&2; fail 'script errors'; }
mkdir "$out"
mv "$work/gather-qa.apk" "$out/"
printf '%s\n' "$rev" > "$out/source-commit.txt"
if command -v sha256sum >/dev/null; then sha=(sha256sum); else sha=(shasum -a 256); fi
(cd "$out" && "${sha[@]}" gather-qa.apk > gather-qa.apk.sha256)
echo "gather QA APK: ABI $abi" >&2
cat "$out/gather-qa.apk.sha256"
