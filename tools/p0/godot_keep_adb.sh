# Sourced by build_demo_apk.sh and android_p0.sh (C-79). Godot's editor setting export/android/shutdown_adb_on_exit
# defaults to true: an editor run that sees a runnable Android preset (an import or an export) ends with
# `adb kill-server`, and on a shared adb port (5137 on the Cardigan workers) that drops other sessions' emulators.
# As tools/android/build_worker_apk.sh does, run a self-contained copy of Godot whose own editor settings say false,
# so the export neither depends on nor writes this account's settings. Otherwise the copy starts from the account's
# editor settings (SDK, JDK, debug keystore) and uses its export templates and debug keystore directory, so the APK
# is built and signed as before.
#   p0_godot_keep_adb GODOT NEW_DIRECTORY   sets P0_GODOT to the copy to run; remove NEW_DIRECTORY afterwards.
p0_godot_keep_adb() {
  local bin dir="$2" exe version major minor config data
  bin="$(python3 -c 'import os, shutil, sys; p = shutil.which(sys.argv[1]); print(os.path.realpath(p)) if p else sys.exit(1)' "$1")" \
    || { echo "Godot not found: $1" >&2; return 1; }
  version="$("$bin" --version)"; IFS=. read -r major minor _ <<< "$version"
  [[ "$major" =~ ^[0-9]+$ && "$minor" =~ ^[0-9]+$ ]] || { echo "unexpected Godot version: $version" >&2; return 1; }
  # Where this Godot keeps its settings (Godot's EditorPaths): beside a self-contained binary (beside the .app on
  # macOS), else per user. On macOS Godot 4.7 reads ~/Library/Application Support/Godot even with XDG_* set.
  exe="$(dirname "$bin")"
  [[ "$(uname -s)" == Darwin && "$exe" == */Contents/MacOS ]] && exe="$(dirname "$(dirname "$(dirname "$exe")")")"
  if [[ -e "$exe/._sc_" || -e "$exe/_sc_" ]]; then
    config="$exe/editor_data" data="$exe/editor_data"
  elif [[ "$(uname -s)" == Darwin ]]; then
    config="$HOME/Library/Application Support/Godot" data="$config"
  else
    config="${XDG_CONFIG_HOME:-}" data="${XDG_DATA_HOME:-}"
    [[ "$config" == /* ]] || config="$HOME/.config"
    [[ "$data" == /* ]] || data="$HOME/.local/share"
    config="$config/godot" data="$data/godot"
  fi
  if [[ "$(uname -s)" == Darwin && "$bin" == *.app/Contents/MacOS/* ]]; then
    # A Mach-O copied out of its bundle loses the signed Info.plist and macOS kills it.
    ditto "${bin%/Contents/MacOS/*}" "$dir/Godot.app" || return 1
    P0_GODOT="$dir/Godot.app/Contents/MacOS/${bin##*/}"
  else
    cp "$bin" "$dir/godot" || return 1
    P0_GODOT="$dir/godot"
  fi
  touch "$dir/._sc_"
  mkdir -p "$dir/editor_data" "$data/keystores"
  [[ -d "$data/export_templates" ]] && ln -s "$data/export_templates" "$dir/editor_data/export_templates"
  # A debug keystore Godot generates on a first export lands where the account's Godot would put it, not in the copy.
  ln -s "$data/keystores" "$dir/editor_data/keystores"
  # The account's JDK setting wins; only an empty one takes the JAVA_HOME the caller exports (as build_demo_apk.sh
  # does: the JDK it signs with), where Godot would otherwise refuse to export.
  python3 - "$config/editor_settings-$major.$minor.tres" "$dir/editor_data/editor_settings-$major.$minor.tres" \
    "${JAVA_HOME:-}" <<'PY'
import json, sys
from pathlib import Path
source, target, java = Path(sys.argv[1]), Path(sys.argv[2]), sys.argv[3]
KEY, JAVA = "export/android/shutdown_adb_on_exit", "export/android/java_sdk_path"
text = source.read_text() if source.is_file() else '[gd_resource type="EditorSettings" format=3]\n\n[resource]\n'
lines = text.splitlines()
if "[resource]" not in lines:
    sys.exit(f"no [resource] section in {source}")
key = lambda l: l.split("=", 1)[0].strip()
added = [f"{KEY} = false"]
if java and not any(key(l) == JAVA and l.split("=", 1)[1].strip() not in ('""', "") for l in lines):
    lines = [l for l in lines if key(l) != JAVA]
    added.append(f"{JAVA} = {json.dumps(java)}")
lines = [l for l in lines if key(l) != KEY]
at = lines.index("[resource]") + 1
target.write_text("\n".join(lines[:at] + added + lines[at:]) + "\n")
PY
}
