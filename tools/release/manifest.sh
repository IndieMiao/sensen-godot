#!/usr/bin/env bash
# 客户端 release-manifest：tools/release/manifest.sh <apk|ipa|app...>
# 输出 JSON 到 stdout：git sha / tag、Godot 版本、两端预设的版本号与包名、每个产物的 sha256 与大小。
# 部署与回滚只认这份清单里的 sha256，不认文件名（文件名可以被覆盖，哈希不能）。
set -euo pipefail
cd "$(dirname "$0")/../.."

git_sha=$(git rev-parse HEAD)
git_tag=$(git describe --tags --exact-match 2>/dev/null || echo "")
branch=$(git rev-parse --abbrev-ref HEAD)
godot_version=$("${GODOT_BIN:-godot}" --version 2>/dev/null | tail -1 || echo "unknown")

preset_field() { # preset_field <preset name> <key>
  awk -v name="$1" -v key="$2" '
    /^\[preset\.[0-9]+\]$/ { in_preset = 0 }
    $0 == "name=\"" name "\"" { in_preset = 1 }
    in_preset && index($0, key "=") == 1 { sub("^" key "=", ""); gsub(/"/, ""); print; exit }
  ' export_presets.cfg
}

android_code=$(preset_field Android version/code)
android_name=$(preset_field Android version/name)
android_pkg=$(preset_field Android package/unique_name)
ios_bundle=$(preset_field iOS application/bundle_identifier)
ios_version=$(preset_field iOS application/short_version)
ios_build=$(preset_field iOS application/version)

sha256_of() {
  if command -v sha256sum >/dev/null 2>&1; then sha256sum "$1" | cut -d' ' -f1; else shasum -a 256 "$1" | cut -d' ' -f1; fi
}
size_of() { stat -f %z "$1" 2>/dev/null || stat -c %s "$1"; }

artifacts="[]"
for f in "$@"; do
  if [ -f "$f" ]; then
    entry=$(printf '{"path":"%s","sha256":"%s","bytes":%s}' "$f" "$(sha256_of "$f")" "$(size_of "$f")")
  elif [ -d "$f" ]; then
    # .app 目录：对目录里所有文件的哈希再哈希一次，得到一个稳定指纹。
    fp=$(cd "$f" && find . -type f -print0 | sort -z | xargs -0 shasum -a 256 2>/dev/null | shasum -a 256 | cut -d' ' -f1)
    entry=$(printf '{"path":"%s","tree_sha256":"%s"}' "$f" "$fp")
  else
    echo "manifest: no such artifact $f" >&2; exit 2
  fi
  artifacts=$(printf '%s' "$artifacts" | python3 -c 'import json,sys; a=json.load(sys.stdin); a.append(json.loads(sys.argv[1])); print(json.dumps(a))' "$entry")
done

python3 - "$git_sha" "$git_tag" "$branch" "$godot_version" "$android_code" "$android_name" "$android_pkg" "$ios_bundle" "$ios_version" "$ios_build" "$artifacts" <<'PY'
import json, sys, datetime
sha, tag, branch, godot, acode, aname, apkg, ibundle, iver, ibuild, artifacts = sys.argv[1:]
print(json.dumps({
    "kind": "client",
    "built_at": datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
    "git_sha": sha, "git_tag": tag or None, "branch": branch,
    "godot_version": godot,
    "android": {"package": apkg, "version_code": int(acode or 0), "version_name": aname},
    "ios": {"bundle_id": ibundle, "version": iver, "build": ibuild},
    "artifacts": json.loads(artifacts),
}, indent=2, ensure_ascii=False))
PY
