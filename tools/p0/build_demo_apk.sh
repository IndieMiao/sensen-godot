#!/usr/bin/env bash
# P0 internal demo APK (SGODOT-232 D2). Preset "Android P0": feature p0 (opens straight into P0, no adb marker),
# package com.sensen.p0demo (never the Journey package, never the user's com.sensen.p0proto), its own version.
#   tools/p0/build_demo_apk.sh --server https://host/preview/p0/v1 [--key DEMO_KEY] [--code N] [--name p0-0.1.N]
#                              [--out build/p0-demo.apk]
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
export ADB_SERVER_SOCKET="tcp:localhost:${P0_ADB_PORT:-5071}" ANDROID_ADB_SERVER_PORT="${P0_ADB_PORT:-5071}"
GODOT="${GODOT_BIN:-godot}"
SDK="${ANDROID_HOME:-$HOME/Library/Android/sdk}"
# apksigner needs a JDK; use the one the Godot editor exports with (Android Studio's) unless JAVA_HOME is set.
export JAVA_HOME="${JAVA_HOME:-/Applications/Android Studio.app/Contents/jbr/Contents/Home}"
LOGS=output/p0-demo
CFG=assets/p0/demo_server.json
BACKUP="$(mktemp -t p0demo_presets)"
cp export_presets.cfg "$BACKUP"
restore() { cp "$BACKUP" export_presets.cfg; rm -f "$BACKUP" "$CFG"; }
trap restore EXIT
mkdir -p "$(dirname "$OUT")" "$LOGS"

python3 - "$SERVER" "$KEY" "$CODE" "$NAME" <<'PY'
import json, re, sys
url, key, code, name = sys.argv[1:5]
json.dump({"url": url.rstrip("/"), "key": key}, open("assets/p0/demo_server.json", "w"))
p = "export_presets.cfg"; s = open(p).read()
i = s.index('name="Android P0"'); head, seg = s[:i], s[i:]
if code: seg = re.sub(r"version/code=\d+", f"version/code={int(code)}", seg, count=1)
if name: seg = re.sub(r'version/name="[^"]*"', f'version/name="{name}"', seg, count=1)
open(p, "w").write(head + seg)
PY

TEMPLATE=()
[[ -d android/build ]] || TEMPLATE=(--install-android-build-template)
"$GODOT" --headless --path . --import > "$LOGS/import.log" 2>&1 || true
"$GODOT" --headless --path . ${TEMPLATE[@]+"${TEMPLATE[@]}"} --export-debug "Android P0" "$OUT" > "$LOGS/export.log" 2>&1 \
  || { echo "export failed, see $LOGS/export.log" >&2; exit 1; }

# Read back what was built: package, version, signer, the baked server (never print the key), checksum.
BT="$(ls -d "$SDK"/build-tools/* | sort -V | tail -1)"
"$BT/aapt" dump badging "$OUT" > "$LOGS/badging.txt"
"$BT/apksigner" verify --print-certs "$OUT" > "$LOGS/signer.txt"
python3 - "$OUT" "$SERVER" "$KEY" "$LOGS" <<'PY'
import hashlib, json, re, sys, zipfile
apk, server, key, logs = sys.argv[1:5]
badging = open(f"{logs}/badging.txt").read()
pkg = re.search(r"package: name='([^']+)' versionCode='(\d+)' versionName='([^']*)'", badging)
label = re.search(r"application-label:'([^']*)'", badging)
signer = re.search(r"SHA-256 digest: ([0-9a-f]+)", open(f"{logs}/signer.txt").read())
with zipfile.ZipFile(apk) as z:
    names = [n for n in z.namelist() if n.endswith("p0/demo_server.json")]
    baked = json.loads(z.read(names[0])) if names else None
result = {
    "apk": apk, "sha256": hashlib.sha256(open(apk, "rb").read()).hexdigest(),
    "package": pkg.group(1) if pkg else None, "version_code": int(pkg.group(2)) if pkg else None,
    "version_name": pkg.group(3) if pkg else None, "label": label.group(1) if label else None,
    "signer_sha256": signer.group(1) if signer else None,
    "server": baked.get("url") if baked else None, "server_matches": bool(baked) and baked.get("url") == server.rstrip("/"),
    "key_baked": bool(baked) and baked.get("key") == key and key != "",
}
json.dump(result, open(f"{logs}/build.json", "w"), indent=2)
print(json.dumps(result, indent=2))
ok = result["package"] == "com.sensen.p0demo" and result["server_matches"]
sys.exit(0 if ok else 1)
PY
