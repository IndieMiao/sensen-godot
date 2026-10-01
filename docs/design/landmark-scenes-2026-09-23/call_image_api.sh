#!/bin/bash
# Sensenjoy Image API caller — /images/edits with reference images.
# Usage: call_image_api.sh <out.png> <size> <prompt-file> <ref1> [ref2 ...]
set -euo pipefail
OUT="$1"; SIZE="$2"; PROMPT_FILE="$3"; shift 3
ARGS=(-s -X POST "https://sub.sensenjoy.cn/v1/images/edits"
  -H "Authorization: Bearer ${SENSENJOY_API_KEY}"
  -F "model=gpt-image-2" -F "quality=high" -F "size=${SIZE}"
  -F "prompt=<${PROMPT_FILE}")
for ref in "$@"; do ARGS+=(-F "image[]=@${ref}"); done
RESP="${OUT%.png}.response.json"
curl "${ARGS[@]}" -o "$RESP"
python3 - "$RESP" "$OUT" <<'PY'
import base64, json, sys
resp = json.load(open(sys.argv[1]))
if "data" not in resp:
    print("API error:", json.dumps(resp)[:500]); sys.exit(1)
item = resp["data"][0]
if item.get("b64_json"):
    open(sys.argv[2], "wb").write(base64.b64decode(item["b64_json"]))
elif item.get("url"):
    import urllib.request
    urllib.request.urlretrieve(item["url"], sys.argv[2])
print("saved", sys.argv[2])
PY
