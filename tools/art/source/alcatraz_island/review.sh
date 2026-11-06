#!/usr/bin/env bash
set -euo pipefail
task_source="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
task_root="$(cd -- "$task_source/../../../.." && pwd)"
cd "$task_root"
mkdir -p output/alcatraz-424/v4
python3 "$task_source/prepare.py"
flock "$HOME/gs66-render.lock" timeout 180s godot --headless --path output/alcatraz-424/project --editor --import > output/alcatraz-424/v4/import.log 2>&1
if rg -q "SCRIPT ERROR|ERROR:" output/alcatraz-424/v4/import.log; then tail -30 output/alcatraz-424/v4/import.log; exit 1; fi
python3 "$task_source/prepare.py" --sync-imports
# Use the caller's valid display credentials. No authorization changes or shared editor left running.
flock "$HOME/gs66-render.lock" timeout 420s env ALCATRAZ_REVIEW="$task_root/output/alcatraz-424/v4/review" godot --path output/alcatraz-424/project --resolution 360x800 --fixed-fps 60 --disable-vsync --max-fps 60 > output/alcatraz-424/v4/runtime.log 2>&1
