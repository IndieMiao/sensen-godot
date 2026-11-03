# N3 Culture Hall Independent Reuse Sources

赵云，SGODOT-323独立部分预装。白模及开场已获95aed0c2/1eb4f28b通过，开场保持原样。`reference/` 保留318 R3主图、SVG、清单、色板和已通过的323摆法提案。位置以323 `1f4f9753` 为准。

当前源为 `culture_hall_reuse.blend`。`layout_plan.json` 是已通过白模的布局输入；当前阶段不要运行 `plan.py` 或 `build_blockout.py` 覆盖细模layout。复现历史白模请使用aee2d5d0及当时的README。

- `make_atlas.py`: fixed hall palette slots, terracotta tile bitmap, exact used-only botanical RGBA tile copies.
- `build_reuse.py`: editable named source adaptations, module-local scalar AO, six independent exports and the mixed fine/proxy layout. Final Huangzhong props are not accessed.
- `verify_reuse.py`: approved placement/collision/anchor invariants, untouched gray assets, exact botanical pixel/vertex/UV comparison.
- `check_plan.py`: rear clear strip, support, footprint intersections, direct routes, capsule-centre connectivity and sixteen positions.
- `check_navigation.gd`: actual Godot collision sweeps and P0RoomNav checks.
- `prepare.py` / `configure.gd`: isolated copied runtime; N1 import parameters and Godot-generated UIDs.
- `review.gd`: unchanged native opening, viewing area, four seated actors, runtime scissor checks and light controls.
- `package_reuse.py`: signed partial-stage media, UID audit and evidence bundle. `package.py` belongs to the historical white stage.

```bash
source ~/.codex-zhaoyun/env.sh
CULTURE_SOURCE="$PWD/tools/art/source/poi_culture_hall"
CULTURE_RUNTIME=/absolute/path/to/private/farm-dev-based-checkout
output/art-setup/venv/bin/python "$CULTURE_SOURCE/make_atlas.py"
blender --background --factory-startup --python-exit-code 1 --python "$CULTURE_SOURCE/build_reuse.py"
output/art-setup/venv/bin/python "$CULTURE_SOURCE/check_plan.py"
output/art-setup/venv/bin/python "$CULTURE_SOURCE/verify_reuse.py"
python3 "$CULTURE_SOURCE/prepare.py" --runtime "$CULTURE_RUNTIME"
godot --headless --path output/culture-hall-323/project --import > output/culture-hall-323/import-reuse.log 2>&1
godot --headless --path output/culture-hall-323/project --script res://configure.gd
godot --headless --path output/culture-hall-323/project --import > output/culture-hall-323/reimport-reuse.log 2>&1
python3 "$CULTURE_SOURCE/prepare.py" --runtime "$CULTURE_RUNTIME" --sync-import
godot --headless --path output/culture-hall-323/project --script res://check_navigation.gd > output/culture-hall-323/navigation-reuse.log 2>&1
nvidia-smi
godot --path output/culture-hall-323/project --display-driver wayland --rendering-method mobile --rendering-driver vulkan --max-fps 30 > output/culture-hall-323/render-reuse.log 2>&1
output/art-setup/venv/bin/python "$CULTURE_SOURCE/package_reuse.py"
```

The card stays In Progress. Shell skin, seats, lighting and Monstera are authorized now; the final display kit stays gray until Shangguan Wan'er confirms technical acceptance of Huangzhong's files. The opening crop is approved and must not be biased to include the paintings.
