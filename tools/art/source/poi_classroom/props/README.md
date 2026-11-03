# SGODOT-322 N4 新道具 v1

黄忠，2026-11-03。按上官婉儿派活及 317 R3 主图制作。这里只交 7 种新道具，场景白模、壳、家具复用及组装由赵云负责。

## 组装交接

运行时文件均在 `assets/rooms/poi_classroom/props/`，尺寸和局部挂点见同目录 `prop_manifest.json`。
米制、Y 向上、+Z 朝正面。落地/桌面件原点在包围盒底面中心；黑板和招牌原点在背面中心，向 +Z 凸出。
7 个 GLB 均为 1 mesh / 1 surface，mesh 名为 `<件名>_mobile`，没有贴图；七件使用同一种哑光顶点色材质设定。

| 模块 | 文件 | 数量 | 实测 W × H × D（m） | 单件面数 |
| --- | --- | ---: | --- | ---: |
| M06 | blackboard.glb | 1 | 1.900 × 1.100 × .160 | 264 |
| M07 | teacher_desk.glb | 1 | 1.300 × 1.184 × .723 | 484 |
| M08 | globe.glb | 1 | .369 × .469 × .320 | 496 |
| M05 | desk_stationery.glb | 2 | .545 × .255 × .270 | 270 |
| M12 | plaster_study.glb | 1 | .678 × .505 × .238 | 470 |
| M13 | reading_cushion.glb | 2 | .600 × .160 × .600 | 188 |
| M19 | name_sign.glb | 1 | 1.450 × .380 × .046 | 220 |

唯一网格合计 **2,392 三角面 / 7 surface**。书本笔筒、软垫各复用两份，共 **9 个实例 / 2,850 三角面 / 9 surface**。
预算按实际摆放数量计算，单件最高 496 面，均低于 600；整套低于 3,000。

- 黑板保持空白，含空粉笔托槽。
- 讲台桌面为 **1.13425 m = .65 × 1.745 m**；整体高度 1.18425 m 包括主图上的闭合教学书，不能把整体 bounds 当作桌面高度。
- 地球仪独立导出；讲台 manifest 的 `globe_mount` 是底座支撑位置，合成时使用该局部位置即可。讲台为布景，没有 NPC/use 挂点；附简单盒体建议供组装时使用。
- 文具是 1 本翻开的空白书和 1 个空心笔筒、3 支笔，整组复用两次，不额外生成第二份网格。
- M12 为无宗教符号的石膏头像与几何练习体。练习体平面与底座接触，不悬空。
- 两只鼠尾草绿软垫为装饰，不生成 `seat_*`，不计入房间座位数。
- 招牌为右墙安装件，正面 +Z，根节点随墙旋转。空节点 **sign_door** 局部位置 `[0, 0, .052]`，带 `size=[1.30,.28]` 和 `module=name_sign`，文字留空。原点在牌背中心，赵云按最终墙顶线确定安装位置。

## 材质与导入

每件 `.glb.import` 带独立 UID，`gltf/texture_map_mode=1`。导入脚本为本目录运行时的 `material_import.gd`，连同 `.gd.uid` 一起交付。
按 N1 已验证方式，脚本只在导入时启用线性顶点色、保留 `<件名>_mobile` 资源名，并恢复哑光 specular=.18；不包含交互或运行时染色逻辑，也不关闭道具阴影。
Godot 默认该导入模式不自动启用 COLOR_0，因此请连同 `.import` 和导入脚本一起接件，不要只复制 GLB。

原始部件与 7 个 `KIT_<件名>` collection 存于 `classroom_props.blend`。每件的原创说明在 `modules/<件名>/reuse_provenance.json`；没有从其他房间拷贝几何。
沿用现有 `scene_room_pipeline.py` / `build_basic_room.py` 的建模辅助函数，不修改它们。主图和清单副本在 `reference/`。

## 复现与检查

```sh
mkdir -p output/classroom-props-322
blender --background --factory-startup --threads 2 --python-exit-code 1 --python tools/art/source/poi_classroom/props/build_props.py > output/classroom-props-322/build.log 2>&1
blender --background --factory-startup --threads 2 --python-exit-code 1 --python tools/art/source/poi_classroom/props/verify_source.py > output/classroom-props-322/source-verify.log 2>&1
output/art-setup/venv/bin/python tools/art/source/poi_classroom/props/prepare_review.py
source ~/.codex-huangzhong/env.sh
godot --headless --path output/classroom-props-322/project -s res://configure_imports.gd -- "$PWD"
godot --headless --path output/classroom-props-322/project --editor --import > output/classroom-props-322/import.log 2>&1
output/art-setup/venv/bin/python tools/art/source/poi_classroom/props/verify.py
nvidia-smi
godot --path output/classroom-props-322/project --rendering-method mobile --rendering-driver vulkan > output/classroom-props-322/render.log 2>&1
output/art-setup/venv/bin/python tools/art/source/poi_classroom/props/package_review.py
```

首次导入生成的 `material_import.gd.uid` 需要随运行时脚本提交；本次已包含。日志按 package 脚本所用名称保存在 `output/classroom-props-322/`。
重新生成会覆盖本包源和 GLB，先保留人工修改。UID 配置会保留，未改赵云的场景或公共壳。

GLB 独立核查 120 项；Blender 源核查 18 项；Godot 再检查实际导入的 bounds、面数、材质、UID 和挂点。
审阅是 Godot 4.7.2 Vulkan Mobile / RTX 2060 的真实渲染，比例图使用实装玩家、实测身高 1.745 m、43° / yaw 45°、取景宽 6.72 m。
比例图中的白色墙和支撑块只是尺度示意，不是赵云的白模方案。并排图按各件独立取景展示，尺寸以 W/H/D 标注为准。
本次不做整间通道/座位验收，不连接模拟器或手机，未合并或发布。
