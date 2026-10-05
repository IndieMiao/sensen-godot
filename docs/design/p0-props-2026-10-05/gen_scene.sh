#!/bin/bash
# gen_scene.sh <name> <prompt-file> <ref1> [ref2 ...]
# Wraps Sensenjoy /images/edits (gpt-image-2). Tries sizes 1024x1536 -> 1024x1792 -> auto;
# on "No available compatible accounts"-style errors waits 20 s and retries up to 3 times per size.
set -uo pipefail
NAME="$1"; PROMPT_FILE="$2"; shift 2
OUT="${NAME}.png"; LOG="${NAME}.log"
: > "$LOG"
for SIZE in ${SIZES:-1024x1536 1024x1792 auto}; do
  for ATTEMPT in 1 2 3; do
    RESP="${NAME}.${SIZE}.a${ATTEMPT}.response.json"
    echo "$(date '+%H:%M:%S') try size=${SIZE} attempt=${ATTEMPT}" | tee -a "$LOG"
    ARGS=(-s -X POST "https://sub.sensenjoy.cn/v1/images/edits"
      -H "Authorization: Bearer ${SENSENJOY_API_KEY}"
      -F "model=gpt-image-2" -F "quality=high" -F "size=${SIZE}"
      -F "prompt=<${PROMPT_FILE}")
    for ref in "$@"; do ARGS+=(-F "image[]=@${ref}"); done
    curl --max-time 540 "${ARGS[@]}" -o "$RESP"
    CODE=$(python3 - "$RESP" "$OUT" <<'PY'
import base64, json, sys
try:
    resp = json.load(open(sys.argv[1]))
except Exception as e:
    print("PARSE_ERROR", str(e)[:200]); sys.exit(0)
if "data" in resp and resp["data"]:
    item = resp["data"][0]
    if item.get("b64_json"):
        open(sys.argv[2], "wb").write(base64.b64decode(item["b64_json"]))
    elif item.get("url"):
        import urllib.request
        urllib.request.urlretrieve(item["url"], sys.argv[2])
    else:
        print("NO_IMAGE", json.dumps(resp)[:300]); sys.exit(0)
    print("OK", resp.get("size", ""), resp.get("usage", "")); sys.exit(0)
msg = json.dumps(resp)[:400]
low = msg.lower()
if "size" in low and ("invalid" in low or "unsupported" in low or "not supported" in low):
    print("BAD_SIZE", msg)
elif "no available" in low or "compatible accounts" in low or "overload" in low or "rate" in low or "busy" in low or "capacity" in low:
    print("RETRY", msg)
else:
    print("FATAL", msg)
PY
)
    echo "  -> ${CODE}" | tee -a "$LOG"
    case "$CODE" in
      OK*) cp "$RESP" "${NAME}.response.json"; echo "SAVED ${OUT} size=${SIZE}" | tee -a "$LOG"; exit 0 ;;
      BAD_SIZE*) break ;;            # next size
      RETRY*|PARSE_ERROR*) [ "$ATTEMPT" -lt 3 ] && sleep 20 ;;
      *) echo "FAILED ${NAME}" | tee -a "$LOG"; exit 1 ;;
    esac
  done
done
echo "FAILED ${NAME} (all sizes/attempts exhausted)" | tee -a "$LOG"; exit 1
