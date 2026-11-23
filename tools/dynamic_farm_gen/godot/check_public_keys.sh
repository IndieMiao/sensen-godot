#!/usr/bin/env bash
# Asserts that check_decode.gd's PUBLIC_KEYS lists exactly the feature properties the native map
# hands to GDScript (ParcelPayload.propertyKeys). check_client_decode.sh runs it before decoding.
# Usage: check_public_keys.sh [ParcelPayload.kt] [check_decode.gd]
set -euo pipefail
here=$(cd "$(dirname "$0")" && pwd)
kt=${1:-$here/../../android/overlay/ParcelPayload.kt}
gd=${2:-$here/check_decode.gd}
# keys <file> <pattern of the one line that declares the list>
keys() {
  local n
  n=$(grep -cE "$2" "$1" || true)
  [[ $n -eq 1 ]] || { echo "expected one line matching '$2' in $1, found $n" >&2; return 2; }
  grep -E "$2" "$1" | sed -E 's/^[^([]*[([]//; s/[])].*$//' | grep -oE '"[^"]*"' | tr -d '"' | sort
}
client=$(keys "$kt" '^[[:space:]]*val propertyKeys = setOf\(') || exit 2
script=$(keys "$gd" '^const PUBLIC_KEYS := \[') || exit 2
[[ -n $client ]] || { echo "no keys read from $kt" >&2; exit 2; }
if [[ $client != "$script" ]]; then
  echo "PUBLIC_KEYS in $gd differs from ParcelPayload.propertyKeys in $kt (< client, > script):" >&2
  diff <(echo "$client") <(echo "$script") | grep -E '^[<>]' >&2 || true
  exit 1
fi
echo "public keys ok: $(echo "$client" | wc -l | tr -d ' ') keys match ParcelPayload.propertyKeys"
