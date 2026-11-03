# N3 Culture Hall White Sources

赵云，SGODOT-323白模v0。`reference/` 保留318 R3主图、SVG、清单和已通过的323摆法提案。位置以323 `1f4f9753` 为准，R3旧文档的后角展台位置已被替代。

- `plan.py`: structured SVG measurements, inner-wall coordinate datum, the three approved layout changes, four seats and review targets.
- `build_blockout.py`: ten owned coarse proxy GLBs, named editable `culture_hall_blockout.blend`, layout asset list and placed statistics. Does not write a final props directory or room atlas.
- `check_plan.py`: rear clear strip, support, footprint intersections, direct routes, capsule-centre connectivity and sixteen positions.
- `check_navigation.gd`: actual Godot collision sweeps and P0RoomNav checks.
- `prepare.py` / `configure.gd`: isolated copied runtime; N1 import parameters and Godot-generated UIDs.
- `review.gd`: native P0 opening and four seated actors, plus a separately labelled viewing-area fixture. No new camera or movement implementation.
- `package.py`: raw mesh/UID audit, actual skirting clearance, signed media and validation JSON.

```bash
source ~/.codex-zhaoyun/env.sh
CULTURE_SOURCE="$PWD/tools/art/source/poi_culture_hall"
CULTURE_RUNTIME=/absolute/path/to/private/farm-dev-based-checkout
python3 "$CULTURE_SOURCE/plan.py"
blender --background --factory-startup --python-exit-code 1 --python "$CULTURE_SOURCE/build_blockout.py"
output/art-setup/venv/bin/python "$CULTURE_SOURCE/check_plan.py"
python3 "$CULTURE_SOURCE/prepare.py" --runtime "$CULTURE_RUNTIME"
godot --headless --path output/culture-hall-323/project --import > output/culture-hall-323/import.log 2>&1
godot --headless --path output/culture-hall-323/project --script res://configure.gd
godot --headless --path output/culture-hall-323/project --import > output/culture-hall-323/reimport.log 2>&1
python3 "$CULTURE_SOURCE/prepare.py" --runtime "$CULTURE_RUNTIME" --sync-import
godot --headless --path output/culture-hall-323/project --script res://check_navigation.gd > output/culture-hall-323/navigation.log 2>&1
nvidia-smi
godot --path output/culture-hall-323/project --display-driver wayland --rendering-method mobile --rendering-driver vulkan --max-fps 30 > output/culture-hall-323/render.log 2>&1
output/art-setup/venv/bin/python "$CULTURE_SOURCE/package.py"
```

The white stage stays In Progress. Wait for layout/visual approval and Huangzhong's final module interface before detailed art. The six artworks are currently outside the native middle-entry opening crop; this is explicitly handed back for visual review, not hidden by a custom opening camera.
