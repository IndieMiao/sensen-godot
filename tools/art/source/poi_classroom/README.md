# SGODOT-322 Editable Sources

赵云，细模 v1。当前主源为 `classroom_detail.blend`；`classroom_blockout.blend` 和 `layout_plan.json` 保留已通过白模。`build_detail.py` 从白模计划派生最终 layout，不运行 `plan.py` 覆盖最终计划。

Source collections are evaluated into independently editable named mesh parts, then joined only on runtime export copies. Module-local scalar AO is exported in COLOR_0. The shared hall and Huangzhong's `props/` remain read-only.

- `make_atlas.py`: fixed hall slots, R3 palette and original plank/miniature art bitmaps.
- `build_detail.py`: Basic Room table/chair/shelf adaptations, reused catalogue lighting and plants, GLBs, provenance, source blend and final layout/stats.
- `dependencies/hallkit_324.blend`: pinned 324 editable lamp source, also retained by N1's dependency pipeline. Only KIT_wall_sconce is read; its SHA-256 is in the exported provenance.
- `check_plan.py`, `check_navigation.gd`, `verify_detail.py`: planar/actual capsule, support, module and raw GLB checks.
- `review.gd`: original P0 framing/actors with the hall near/far contract; the legacy clip comparison is captured separately.
- `package_detail.py`: signed review images and verification bundle.

```bash
source ~/.codex-zhaoyun/env.sh
CLASSROOM_SOURCE="$PWD/tools/art/source/poi_classroom"
CLASSROOM_RUNTIME=/absolute/path/to/private/farm-dev-based-checkout
output/art-setup/venv/bin/python "$CLASSROOM_SOURCE/make_atlas.py"
blender --background --factory-startup --python-exit-code 1 --python "$CLASSROOM_SOURCE/build_detail.py"
output/art-setup/venv/bin/python "$CLASSROOM_SOURCE/check_plan.py"
output/art-setup/venv/bin/python "$CLASSROOM_SOURCE/verify_detail.py"
python3 "$CLASSROOM_SOURCE/prepare.py" --runtime "$CLASSROOM_RUNTIME"
godot --headless --path output/classroom-322/project --import > output/classroom-322/import-detail.log 2>&1
godot --headless --path output/classroom-322/project --script res://configure.gd
godot --headless --path output/classroom-322/project --import > output/classroom-322/reimport-detail.log 2>&1
python3 "$CLASSROOM_SOURCE/prepare.py" --runtime "$CLASSROOM_RUNTIME" --sync-import
godot --headless --path output/classroom-322/project --script res://check_navigation.gd > output/classroom-322/navigation.log 2>&1
nvidia-smi
godot --path output/classroom-322/project --display-driver wayland --rendering-method mobile --rendering-driver vulkan --max-fps 30 > output/classroom-322/render.log 2>&1
output/art-setup/venv/bin/python "$CLASSROOM_SOURCE/package_detail.py"
```

Reuse the existing verified toolchain; do not restart authorization. Reproducing historical white assets requires commit `377d4be3` and its README.
