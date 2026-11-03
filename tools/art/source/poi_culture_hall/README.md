# N3 Culture Hall Editable Sources

赵云，SGODOT-323整间装配v1。白模及开场获95aed0c2/1eb4f28b通过，独立部分fa0f5e08通过；本轮按8d679529/7aa982a6接黄忠固定供应版v1.1（85b06565），开场不偏移。reference/保留318 R3资料；摆位以323 1f4f9753为准。

完整源为 `culture_hall_v1.blend`；`culture_hall_reuse.blend`保留六个独立模块源，`props/culture_props.blend`是黄忠原样供应的详细命名源。`layout_plan.json`是已批白模输入；不要运行plan.py或build_blockout.py覆盖细模layout。复现历史白模使用aee2d5d0及当时README。

- `assemble_v1.py`: nine approved prop instances, grouped placement replacement, true display heights/colliders/sign mount and raw cost.
- `build_assembly_source.py`: copies named editable modules into the complete source, then checks 26 local bounds against runtime GLBs; no runtime re-export.
- `build_reuse.py` / `make_atlas.py`: independent modules and atlas. Rebuilding now calls final assembly when the approved prop manifest is present. This delivery keeps independent GLBs/imports/atlas byte-identical to fa0f5e08.
- `verify_reuse.py`: independent placement/collision/anchor invariants and exact botanical pixel/vertex/UV comparison.
- `verify_detail.py`: pinned supplier file identity, grouped assets, supports, glass interiors, wall clearance, UIDs and real instanced budget.
- `check_plan.py` / `check_navigation.gd`: rear clear strip, support, routes, sixteen positions and real Godot/P0RoomNav collisions.
- `prepare.py` / `configure.gd`: isolated copied runtime; skips supplier props import settings and preserves their glass material.
- `review.gd`: native opening, viewing area, four seated actors, panorama, topdown and estimated reference camera.
- `package_detail.py`: seven signed full-room media and validation bundle. package_reuse.py and package.py belong to historical stages.

从当前已导出的资产复现：

```bash
source ~/.codex-zhaoyun/env.sh
CULTURE_SOURCE="$PWD/tools/art/source/poi_culture_hall"
CULTURE_RUNTIME=/absolute/path/to/private/farm-dev-based-checkout
output/art-setup/venv/bin/python "$CULTURE_SOURCE/assemble_v1.py"
blender --background --factory-startup --python-exit-code 1 --python "$CULTURE_SOURCE/build_assembly_source.py"
output/art-setup/venv/bin/python "$CULTURE_SOURCE/check_plan.py"
output/art-setup/venv/bin/python "$CULTURE_SOURCE/verify_reuse.py"
output/art-setup/venv/bin/python "$CULTURE_SOURCE/verify_detail.py"
python3 "$CULTURE_SOURCE/prepare.py" --runtime "$CULTURE_RUNTIME"
godot --headless --path output/culture-hall-323/project --import > output/culture-hall-323/import-detail.log 2>&1
godot --headless --path output/culture-hall-323/project --script res://configure.gd > output/culture-hall-323/configure-detail.log 2>&1
godot --headless --path output/culture-hall-323/project --import > output/culture-hall-323/reimport-detail.log 2>&1
python3 "$CULTURE_SOURCE/prepare.py" --runtime "$CULTURE_RUNTIME" --sync-import
godot --headless --path output/culture-hall-323/project --script res://check_navigation.gd > output/culture-hall-323/navigation-detail.log 2>&1
nvidia-smi
godot --path output/culture-hall-323/project --display-driver wayland --rendering-method mobile --rendering-driver vulkan --max-fps 30 > output/culture-hall-323/render-detail.log 2>&1
output/art-setup/venv/bin/python "$CULTURE_SOURCE/package_detail.py"
```

The two case-exhibit groups now use the approved 1.4x individual exhibits with .06 m pedestals. Group origins and slots are unchanged. Future supplier updates must retain their approved commit and rerun assembly/verification/rendering. Full-room v1 uses captures-v1/; the updated media manifest has a separate delivery receipt and supersedes the original ff0258f8 pictures.

复制的供应README记载黄忠自己的5097端口；赵云一律使用上面的环境和私有ADB5099，不运行别人的环境脚本。保持已通过开场，看画从屋内看画区进行。
