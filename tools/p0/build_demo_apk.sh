#!/usr/bin/env bash
# P0 internal demo APK (SGODOT-232 D2). Preset "Android P0": feature p0 (opens straight into P0, no adb marker),
# package com.sensen.p0demo (never the Journey package, never the user's com.sensen.p0proto), its own version.
#   tools/p0/build_demo_apk.sh --server https://host/preview/p0/v1 [--key DEMO_KEY] [--code N] [--name 0.1.N]
#                              [--out build/p0-demo.apk]
# Versions (user, 2026-10-09): versionName from the preset (0.1.0); versionCode YYYYMMDDNN, by default the build
# day + 01. A second build the same day passes --code …02; …00 is for dry runs, which publish_demo_apk.mjs refuses.
# The server URL (and demo key) go into assets/p0/demo_server.json for this export only and are removed afterwards;
# export_presets.cfg is restored too. Godot's Android exporter stops "its" adb server when it exits, so this script
# points it at a private port (P0_ADB_PORT, default 5071) and never touches another session's adb (5037 and others).
# Internal demo only: giving this APK to anyone outside needs the user's approval (AGENTS.md: only Journey goes out).
set -euo pipefail
cd "$(dirname "$0")/../.."
SERVER="" KEY="" CODE="" NAME="" OUT="build/p0-demo.apk"
while [[ $# -gt 0 ]]; do
  case "$1" in
    --server) SERVER="$2"; shift 2 ;;
    --key) KEY="$2"; shift 2 ;;
    --code) CODE="$2"; shift 2 ;;
    --name) NAME="$2"; shift 2 ;;
    --out) OUT="$2"; shift 2 ;;
    *) echo "unknown option $1" >&2; exit 2 ;;
  esac
done
[[ "$SERVER" == http://* || "$SERVER" == https://* ]] || { echo "--server http(s)://…/v1 is required" >&2; exit 2; }
# The native side the demo needs, as in the int test packages (SGODOT-261: an APK exported from a bare template had
# no Mapbox and no LiveKit, so its map was black). android/ is not tracked: tools/android/setup_android_build.sh puts
# the Mapbox overlay on the 4.7.2 template and the three prepare_*_plugin.py add voice (LiveKit), WebView and Sign in
# with Google; mapbox_token.txt (ignored, never committed) goes in the repo root. Refuse to export without them.
missing=()
[[ -s mapbox_token.txt ]] || missing+=("mapbox_token.txt in the repo root")
B=android/build
grep -qs 'com.mapbox.maps:android' "$B/build.gradle" && [[ -f "$B/src/main/java/com/sensen/map/GodotMapPlugin.kt" ]] \
  || missing+=("the Mapbox overlay (tools/android/setup_android_build.sh)")
# A plugin source in the build must be the tracked one, not only there: a build machine whose android/build was
# prepared before a plugin changed would export the old code without a word (周瑜 on #519).
same() { cmp -s "native/$1" "$B/src/main/java/com/sensen/$2"; }
grep -qs 'io.livekit:livekit-android' "$B/build.gradle" && same voice/android/GodotVoicePlugin.kt voice/GodotVoicePlugin.kt \
  || missing+=("GodotVoice / LiveKit, current (python3 tools/android/prepare_voice_plugin.py)")
same webview/android/GodotWebViewPlugin.kt webview/GodotWebViewPlugin.kt || missing+=("GodotWebView, current (python3 tools/android/prepare_webview_plugin.py)")
# Both ask for the microphone through PermissionActivity, never GodotActivity (SGODOT-349): it must be in and declared.
same permission/android/PermissionActivity.kt permission/PermissionActivity.kt \
  && grep -qs 'com.sensen.permission.PermissionActivity' "$B/src/main/AndroidManifest.xml" \
  || missing+=("PermissionActivity, current and in the manifest (either prepare_voice_plugin.py or prepare_webview_plugin.py)")
same googleauth/android/GodotGoogleSignInPlugin.kt googleauth/GodotGoogleSignInPlugin.kt \
  || missing+=("GodotGoogleSignIn, current (python3 tools/android/prepare_google_signin_plugin.py)")
if (( ${#missing[@]} )); then
  printf 'not building: the Android build is missing\n' >&2; printf '  - %s\n' "${missing[@]}" >&2
  echo "run tools/android/setup_android_build.sh, then the three prepare_*_plugin.py, and put mapbox_token.txt in place" >&2
  exit 2
fi
CODE="${CODE:-$(date +%Y%m%d)01}"
[[ "$CODE" =~ ^20[0-9]{6}[0-9]{2}$ ]] || { echo "--code must be YYYYMMDDNN, got $CODE" >&2; exit 2; }
# What the APK is built from, read before this script touches export_presets.cfg (周瑜 on #163): tracked changes, and
# untracked files, since an all_resources export packs untracked scenes, scripts and json too (the preset's
# exclude_filter is applied to the list in build.json; publish_demo_apk.mjs refuses anything but .uid files). Files git
# ignores are not listed: mapbox_token.txt and this script's demo_server.json belong in the APK by design.
COMMIT="$(git rev-parse HEAD)"
DIRTY="$(git status --porcelain --untracked-files=no | head -1)"
export P0_UNTRACKED="$(git ls-files --others --exclude-standard)"
export ADB_SERVER_SOCKET="tcp:localhost:${P0_ADB_PORT:-5071}" ANDROID_ADB_SERVER_PORT="${P0_ADB_PORT:-5071}"
GODOT="${GODOT_BIN:-godot}"
# Defaults per OS when ANDROID_HOME / JAVA_HOME are not set. macOS: Android Studio's SDK and its bundled JDK (the one
# the Godot editor exports with). Linux: Android Studio's ~/Android/Sdk and the JDK that `java` on PATH belongs to.
if [[ "$(uname -s)" == Darwin ]]; then
  SDK="${ANDROID_HOME:-$HOME/Library/Android/sdk}"
  # apksigner needs a JDK.
  export JAVA_HOME="${JAVA_HOME:-/Applications/Android Studio.app/Contents/jbr/Contents/Home}"
else
  SDK="${ANDROID_HOME:-${ANDROID_SDK_ROOT:-$HOME/Android/Sdk}}"
  if [[ -z "${JAVA_HOME:-}" ]] && command -v java > /dev/null; then
    JAVA_HOME="$(dirname "$(dirname "$(readlink -f "$(command -v java)")")")"
  fi
  export JAVA_HOME="${JAVA_HOME:-}"
fi
[[ -d "$SDK/build-tools" ]] || { echo "no Android SDK at $SDK (set ANDROID_HOME)" >&2; exit 2; }
[[ -x "$JAVA_HOME/bin/java" ]] || { echo "no JDK at '$JAVA_HOME' (set JAVA_HOME)" >&2; exit 2; }
LOGS=output/p0-demo
CFG=assets/p0/demo_server.json
# A full template: BSD mktemp -t takes a prefix, GNU mktemp -t needs X's, so neither form of -t works on both.
BACKUP="$(mktemp "${TMPDIR:-/tmp}/p0demo_presets.XXXXXX")"
cp export_presets.cfg "$BACKUP"
restore() { cp "$BACKUP" export_presets.cfg; rm -f "$BACKUP" "$CFG"; }
trap restore EXIT
mkdir -p "$(dirname "$OUT")" "$LOGS"

python3 - "$SERVER" "$KEY" "$CODE" "$NAME" <<'PY'
import json, re, sys
url, key, code, name = sys.argv[1:5]
p = "export_presets.cfg"; s = open(p).read()
i = s.index('name="Android P0"'); head, seg = s[:i], s[i:]
if code: seg = re.sub(r"version/code=\d+", f"version/code={int(code)}", seg, count=1)
if name: seg = re.sub(r'version/name="[^"]*"', f'version/name="{name}"', seg, count=1)
open(p, "w").write(head + seg)
# SYS-UPDATE (SGODOT-232): the client sends this as x-p0-version, the APK's own versionCode, so the server can ask an
# old build to update (426). Always the code this export really uses: --code, else the preset's.
version = int(re.search(r"version/code=(\d+)", seg).group(1))
# Settings › Version (q(129)) shows the name too: `0.2.1 (2026101001)`.
named = re.search(r'version/name="([^"]*)"', seg)
if not named: sys.exit('build_demo_apk: the "Android P0" preset has no version/name (Settings › Version reads it)')
version_name = named.group(1)
json.dump({"url": url.rstrip("/"), "key": key, "version": version, "name": version_name}, open("assets/p0/demo_server.json", "w"))
PY

"$GODOT" --headless --path . --import > "$LOGS/import.log" 2>&1 || true
"$GODOT" --headless --path . --export-debug "Android P0" "$OUT" > "$LOGS/export.log" 2>&1 \
  || { echo "export failed, see $LOGS/export.log" >&2; exit 1; }

# Read back what was built: package, version, signer, the baked server (never print the key), checksum.
BT="$(ls -d "$SDK"/build-tools/* | sort -V | tail -1)"
"$BT/aapt" dump badging "$OUT" > "$LOGS/badging.txt"
"$BT/apksigner" verify --print-certs "$OUT" > "$LOGS/signer.txt"
python3 - "$OUT" "$SERVER" "$KEY" "$LOGS" "$COMMIT" "$DIRTY" <<'PY'
import fnmatch, hashlib, json, os, re, sys, zipfile
apk, server, key, logs, commit, dirty = sys.argv[1:7]
presets = open("export_presets.cfg").read()
seg = presets[presets.index('name="Android P0"'):]
excluded = [p.strip() for p in re.search(r'exclude_filter="([^"]*)"', seg).group(1).split(",") if p.strip()]
untracked = [f for f in os.environ.get("P0_UNTRACKED", "").splitlines()
             if f and not any(fnmatch.fnmatch(f, p) for p in excluded)]
badging = open(f"{logs}/badging.txt").read()
pkg = re.search(r"package: name='([^']+)' versionCode='(\d+)' versionName='([^']*)'", badging)
label = re.search(r"application-label:'([^']*)'", badging)
signer = re.search(r"SHA-256 digest: ([0-9a-f]+)", open(f"{logs}/signer.txt").read())
with zipfile.ZipFile(apk) as z:
    names = [n for n in z.namelist() if n.endswith("p0/demo_server.json")]
    baked = json.loads(z.read(names[0])) if names else None
    entries = set(z.namelist())
# What the map and voice need inside the APK (SGODOT-261): both Mapbox libraries, LiveKit's, the token.
NATIVE = ["lib/arm64-v8a/libmapbox-maps.so", "lib/arm64-v8a/libmapbox-common.so",
          "lib/arm64-v8a/liblkjingle_peerconnection_so.so", "assets/mapbox_token.txt"]
native_missing = [n for n in NATIVE if n not in entries]
# Settings › Legal › Licenses (q(129)): licenses.json and every file a row opens. They are plain files the export takes
# only through the preset's include_filter; one left out reads blank on the phone (a QA export, 10-11).
LEGAL = "assets/assets/p0/legal/licenses.json"
legal_missing = [] if LEGAL in entries else [LEGAL]
if LEGAL in entries:
    with zipfile.ZipFile(apk) as z:
        index = json.loads(z.read(LEGAL))
    texts = [str(r.get("text", "")) for g in index.get("groups", []) for r in g.get("rows", [])]
    legal_missing += ["assets/" + t[len("res://"):] for t in texts if t.startswith("res://") and "assets/" + t[len("res://"):] not in entries]
result = {
    "apk": apk, "sha256": hashlib.sha256(open(apk, "rb").read()).hexdigest(),
    "package": pkg.group(1) if pkg else None, "version_code": int(pkg.group(2)) if pkg else None,
    "version_name": pkg.group(3) if pkg else None, "label": label.group(1) if label else None,
    "signer_sha256": signer.group(1) if signer else None,
    "server": baked.get("url") if baked else None, "server_matches": bool(baked) and baked.get("url") == server.rstrip("/"),
    "key_baked": bool(baked) and baked.get("key") == key and key != "",
    "version_baked": baked.get("version") if baked else None,
    "source_commit": commit, "source_dirty": dirty != "",
    "native_ok": not native_missing, "native_missing": native_missing,
    "legal_ok": not legal_missing, "legal_missing": legal_missing,
    "untracked_exported": untracked[:200], "untracked_exported_count": len(untracked),
}
json.dump(result, open(f"{logs}/build.json", "w"), indent=2)
print(json.dumps(result, indent=2))
ok = result["package"] == "com.sensen.p0demo" and result["server_matches"] and result["version_baked"] == result["version_code"] \
    and result["native_ok"] and result["legal_ok"]
sys.exit(0 if ok else 1)
PY
