#!/bin/bash
# 83 variants, 5 concurrent; one retry per failure.
set -u
ROOT=/Volumes/ACASIS/projects/sensen-godot
STYLE_REF=$ROOT/docs/design/la-map-2026-09-22/production/restaurant/reference-style-cafe.png
CALL=$ROOT/docs/design/la-map-round9-2026-09-23/mockups/call_image_api.sh
sem() { while [ "$(jobs -rp | wc -l)" -ge 5 ]; do sleep 2; done; }
gen() {
  local name=$1 key=${1%_*}
  "$CALL" "raw-$name.png" 1024x1024 "prompt-$name.txt" "$STYLE_REF" "$ROOT/assets/map/poi/$key.png" > "gen-$name.log" 2>&1 \
    || "$CALL" "raw-$name.png" 1024x1024 "prompt-$name.txt" "$STYLE_REF" "$ROOT/assets/map/poi/$key.png" >> "gen-$name.log" 2>&1
}
for p in prompt-*.txt; do
  name=${p#prompt-}; name=${name%.txt}
  [ -s "raw-$name.png" ] && continue
  sem; gen "$name" &
done
wait
echo "BATCH_DONE $(ls raw-*.png 2>/dev/null | wc -l)"
