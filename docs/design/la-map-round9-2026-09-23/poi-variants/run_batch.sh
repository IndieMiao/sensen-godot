#!/bin/bash
# Generate all 12 dining variants, 3 concurrent. Raw magenta output per variant.
set -u
ROOT=/Volumes/ACASIS/projects/sensen-godot
STYLE_REF=$ROOT/docs/design/la-map-2026-09-22/production/restaurant/reference-style-cafe.png
CALL=$ROOT/output/imagegen/round9-2026-09-23/call_image_api.sh
sem() { while [ "$(jobs -rp | wc -l)" -ge 3 ]; do sleep 2; done; }
for key in restaurant chinese_restaurant cafe bakery; do
  for n in 2 3 4; do
    [ -s "raw-${key}_${n}.png" ] && continue
    sem
    "$CALL" "raw-${key}_${n}.png" 1024x1024 "prompt-${key}_${n}.txt" \
      "$STYLE_REF" "$ROOT/assets/map/poi/${key}.png" > "gen-${key}_${n}.log" 2>&1 &
  done
done
wait
ls -la raw-*.png 2>/dev/null
echo BATCH_DONE
