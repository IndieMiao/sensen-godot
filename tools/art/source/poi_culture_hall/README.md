# N3 Culture Hall Editable Sources

赵云，SGODOT-323整间装配v1.1。a5ffdae1整间技术通过；本轮按b31eaf83/d5f8ef32只调墙/护墙板颜色并接黄忠新拼花，地砖保留。固定供应头见assemble_v1.py和layout.props_dependency。白模及开场95aed0c2/1eb4f28b不改，reference/保留318 R3资料，摆位以323 1f4f9753为准。

完整源为 `culture_hall_v1.blend`；`culture_hall_reuse.blend`保留六个独立模块源，`props/culture_props.blend`是黄忠原样供应的详细命名源。`layout_plan.json`是已批白模输入；不要运行plan.py或build_blockout.py覆盖细模layout。复现历史白模使用aee2d5d0及当时README。

- `assemble_v1.py`: nine approved prop instances, grouped placement replacement, true display heights/colliders/sign mount and raw cost.
- `build_assembly_source.py`: copies named editable modules into the complete source, then checks 26 local bounds against runtime GLBs; no runtime re-export.
- `build_reuse.py` / `make_atlas.py`: independent modules and atlas. Rebuilding calls final assembly when the approved prop manifest is present. v1.1 changes only four wall/panel atlas slots; independent GLBs/imports and all other pixels remain unchanged. Do not re-export the six independent modules for this colour edit.
- `verify_reuse.py`: independent placement/collision/anchor invariants and exact botanical pixel/vertex/UV comparison.
- `verify_detail.py`: pinned supplier file identity, grouped assets, supports, glass interiors, wall clearance, UIDs and real instanced budget.
- `check_plan.py` / `check_navigation.gd`: rear clear strip, support, routes, sixteen positions and real Godot/P0RoomNav collisions.
- `prepare.py` / `configure.gd`: isolated copied runtime; skips supplier props import settings and preserves their glass material.
- `review.gd`: native opening, viewing area, four seated actors, panorama, topdown and estimated reference camera.
- `package_v11.py`: three signed views, atlas pixel mask, same-point colour samples, geometry and layout preservation proof. package_detail.py / package_reuse.py / package.py belong to historical stages.

从当前已导出的资产复现：

```bash
source ~/.codex-zhaoyun/env.sh
CULTURE_SOURCE="$PWD/tools/art/source/poi_culture_hall"
CULTURE_RUNTIME=/absolute/path/to/private/farm-dev-based-checkout
output/art-setup/venv/bin/python "$CULTURE_SOURCE/make_atlas.py"
output/art-setup/venv/bin/python "$CULTURE_SOURCE/assemble_v1.py"
blender --background --factory-startup --python-exit-code 1 --python "$CULTURE_SOURCE/build_assembly_source.py" > output/culture-hall-323/source-v11.log 2>&1
output/art-setup/venv/bin/python "$CULTURE_SOURCE/check_plan.py"
output/art-setup/venv/bin/python "$CULTURE_SOURCE/verify_reuse.py"
output/art-setup/venv/bin/python "$CULTURE_SOURCE/verify_detail.py"
python3 "$CULTURE_SOURCE/prepare.py" --runtime "$CULTURE_RUNTIME"
godot --headless --path output/culture-hall-323/project --import > output/culture-hall-323/import-v11.log 2>&1
nvidia-smi
godot --path output/culture-hall-323/project --display-driver wayland --rendering-method mobile --rendering-driver vulkan --max-fps 30 -- --v11 > output/culture-hall-323/render-v11.log 2>&1
output/art-setup/venv/bin/python "$CULTURE_SOURCE/package_v11.py"
```

The two case-exhibit groups retain 1.4x individual exhibits with .06 m pedestals. All placements, anchors, camera, lighting and collision declarations stay identical to accepted a5ffdae1. Navigation evidence is retained from that geometrically identical version; this colour pass verifies the preservation and rerenders the room. v1.1 uses captures-v11/, media-manifest-v1.1.json and a separate receipt, preserving historical v1 media.

复制的供应README记载黄忠自己的5097端口；赵云一律使用上面的环境和私有ADB5099，不运行别人的环境脚本。保持已通过开场，看画从屋内看画区进行。
