#!/usr/bin/env bash
# Decodes a generated dataset with the client's manifest, parcel-index, parcel-tile and farm
# parsers. Once C-43 has lifted the 760–840 core range, only the checkout's client runs and must
# pass. On an older checkout that still enforces it, it runs twice:
#   current  – the file as it is in this checkout (760–840 core cells still enforced);
#   relaxed  – the same file with only that core range check removed, i.e. the C-43 client.
# Usage: tools/dynamic_farm_gen/godot/check_client_decode.sh <dataset dir> [work dir]
set -euo pipefail
dataset=$(cd "${1:?dataset dir}" && pwd)
root=$(cd "$(dirname "$0")/../../.." && pwd)
work=${2:-$(mktemp -d "${TMPDIR:-/tmp}/farm-decode.XXXXXX")}
godot=${GODOT_BIN:-$(command -v godot)}
src="$root/modules/dynamic_farm/farm_data.gd"
range='if counts.core < 760 or counts.core > 840:'
meta_range='raw.core_cell_count<760 or raw.core_cell_count>840 or '
labels=(current)
if grep -qF "$range" "$src"; then
  grep -qF "$meta_range" "$root/modules/dynamic_farm/map/parcel_metadata.gd" || { echo "core range check not found in parcel_metadata.gd" >&2; exit 2; }
  labels=(current relaxed)
fi
# check_decode.gd copies the native map's property whitelist; fail as soon as the client's list changes.
"$(dirname "$0")/check_public_keys.sh" "$root/tools/android/overlay/ParcelPayload.kt" "$(dirname "$0")/check_decode.gd"

# GDScript cannot decode MVT: decode every parcel tile here (independent decoder, cli check-tiles)
# and hand the maximum-zoom feature properties to the client's parser below.
properties="$work/tile-properties.json"
mkdir -p "$work"
pnpm --silent --dir "$root/tools/dynamic_farm_gen" cli check-tiles --dataset "$dataset" --properties "$properties" > "$work/tiles.log" 2>&1 || {
  cat "$work/tiles.log" >&2; echo "tile check failed" >&2; exit 1; }
tail -n 1 "$work/tiles.log"

status=0
for label in "${labels[@]}"; do
  project="$work/$label"
  mkdir -p "$project/modules/dynamic_farm/map"
  for file in geo_api.gd geo_contract.gd geo_math.gd; do cp "$root/modules/dynamic_farm/map/$file" "$project/modules/dynamic_farm/map/"; done
  printf 'config_version=5\n[application]\nconfig/name="farm-decode-%s"\n' "$label" > "$project/project.godot"
  cp "$(dirname "$0")/check_decode.gd" "$project/check_decode.gd"
  if [[ $label == relaxed ]]; then
    sed "s/$range/if counts.core < 1:/" "$src" > "$project/modules/dynamic_farm/farm_data.gd"
    sed "s/$meta_range/raw.core_cell_count<1 or /" "$root/modules/dynamic_farm/map/parcel_metadata.gd" > "$project/modules/dynamic_farm/map/parcel_metadata.gd"
  else
    cp "$src" "$project/modules/dynamic_farm/farm_data.gd"
    cp "$root/modules/dynamic_farm/map/parcel_metadata.gd" "$project/modules/dynamic_farm/map/"
  fi
  cp "$root/modules/dynamic_farm/map/geo_map_config.gd" "$project/modules/dynamic_farm/map/"
  code=0
  "$godot" --headless --path "$project" --script res://check_decode.gd -- "$dataset" "$label" "$properties" > "$work/$label.log" 2>&1 || code=$?
  grep -E '^CLIENT_DECODE|SCRIPT ERROR' "$work/$label.log" || echo "CLIENT_DECODE $label produced no summary (exit $code)"
  # The C-43 client must pass: relaxed on an old checkout (current rejects counts outside 760–840), else current.
  if [[ $code -ne 0 && ( $label == relaxed || ${#labels[@]} == 1 ) ]]; then status=1; fi
done
exit $status
