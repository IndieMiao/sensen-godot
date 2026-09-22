#!/bin/bash
set -u
CALL=/Volumes/ACASIS/projects/sensen-godot/docs/design/la-map-round9-2026-09-23/mockups/call_image_api.sh
sem() { while [ "$(jobs -rp | wc -l)" -ge 5 ]; do sleep 2; done; }
for p in prompt-*.txt; do
  n=${p#prompt-}; n=${n%.txt}; [ -s "raw-$n.png" ] && continue
  sem; ( "$CALL" "raw-$n.png" 1024x1024 "$p" reference-style.png > "gen-$n.log" 2>&1 || "$CALL" "raw-$n.png" 1024x1024 "$p" reference-style.png >> "gen-$n.log" 2>&1 ) &
done
wait; echo "BATCH_DONE $(ls raw-*.png 2>/dev/null | wc -l)"
