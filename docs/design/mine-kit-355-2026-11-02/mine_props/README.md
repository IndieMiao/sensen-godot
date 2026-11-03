# SGODOT-355 矿层摆件与矿石 v1

电梯站、守关场地及矿石形状已通过画面验收；矿石最新颜色见 [v1.1](v1.1/README.md)。本页保留 v1 审阅。

黄忠，2026-11-02。按 `dispatch-huangzhong-2.txt` 及 `props-dims.txt` 末尾周瑜 b1 修订制作，待技术检查和画面验收。

| 资产 | 三角形 | surface | 宽 × 高 × 深（m） |
| --- | ---: | ---: | --- |
| rock_iron_ore | 114 | 1 | 0.889 × 0.630 × 0.885 |
| rock_quartz | 114 | 1 | 0.889 × 0.630 × 0.900 |
| rock_coal | 114 | 1 | 0.871 × 0.630 × 0.895 |
| rock_copper_ore | 114 | 1 | 0.881 × 0.630 × 0.885 |
| guard_arena | 2,421 | 1 | 6.889 × 1.560 × 4.353 |
| elevator_station | 2,394 | 1 | 1.595 × 2.240 × 1.300 |

均为单位米、地面中心原点、Y up、正面 +Z；单 surface、单顶点色材质、无贴图、无动作、无碰撞。
共用现有 `assets/monsters/material_import.gd` 及其 UID，只开线性顶点色、关投影。
每个 `.glb.import` 由 Godot 生成 UID，保持 `animation/import=false`、`remove_immutable_tracks=false`、`texture_map_mode=1`、空 `_subresources`。
所有运行时文件在 `art/monsters-355`，本 PR 保留 Blender 源、生成脚本和审阅证据。

## 四种矿石

沿用实际 `mine_art.gd::_ore` 的四层七边轮廓，半径层 0.36 / 0.47 / 0.34 / 0.15 m，顶点最高 Y=0.63 m。
底圈落在 Y=0，轻微不规则外形，最大实测半径不超过 0.47 m。假影半径仍由程序用 0.52 m。
铁矿锈红褐矿脉、石英白粉晶面、煤为黑亮块、铜矿铜橙与绿锈；色斑沿真实三角面分割，离表面 2 mm，避免跨非平面四边形穿插。
四件是固定可复用资产，碎裂、拾取和假影由程序控制。

## 守关场地

装配位置 `(4.9, 0, -3.8)`。44 块矮碎石围出椭圆，中央保留 6.0 × 3.6 m 椭圆净空。
碎石高度不超过 0.23 m；后沿两根火把高 1.56 m，石碑高 1.15 m，王冠纹为深色凹刻视觉处理。
火把和石碑全部在世界 X 3.10–6.55 内，符合要求的 2.7–6.8；高件离电梯及下行梯均超过 1.6 m。
椭圆自然收进左后角；逐三角形投影与电梯底座矩形做相交检查，没有重叠。
场地最靠后顶点约世界 Z=-5.984，电梯底座前沿 Z=-6.10；两件至少有约 0.116 m 的 Z 向间隔。
整件不带任何碰撞，王和玩家可以越过。火焰只有暖黄顶点色形状，未内置灯光。

## 电梯站

装配位置 `(1.25, 0, -6.75)`。底座 1.45 × 1.30 m，平台木板顶面 Y=0.17 m，总高 2.24 m。
完整包围盒宽 1.595 m 包括右侧保留的指示灯立柱；底座宽度仍为 1.45 m。
四立柱、木架斜撑、后栏、顶梁、后绞轮、绕绳和吊绳均为同一 surface。
牌面无字，模型不放指示灯，供运行时挂接：

| 空节点 | 本地位置（m） | 朝向 / 大小 |
| --- | --- | --- |
| PlateAnchor | (0, 0.99, 0.515) | 正面 +Z；牌面 0.50 × 0.30 m |
| LampAnchor | (0.8, 0.73, 0.47) | identity basis；指示灯由程序画 |

牌背板前面 Z=0.480，牌面 Z=0.510，向前凸出 0.030 m；PlateAnchor 再离牌面 0.005 m，避免文字 z-fighting。
两个空节点同时保留在 Blender 源和 GLB，导入后实际坐标与 +Z 朝向均检查。

## 验证与复现

152 项独立 GLB/导入与几何检查通过，包括预算、bounds、顶点色、法线、无退化三角面、地面原点、UID、
净空椭圆采样、后沿高件范围、运输点距离、电梯底座投影避让及两个空节点。
Godot 4.7.2 Vulkan Mobile / RTX 2060 真实渲染，两种矿各有默认 43° 图、两件同时出现的全景和四矿石并排。
默认截图每栏原始 360×800，游戏 zoom=.8；全景与矿石比较图明确标注，不冒充默认缩放。
真实 Avatar 按顶点调到 H=1.745 m。交付 GLB 与渲染源 SHA-256 一致。
未改 b1/farm-dev 玩法接入，未合并或发布，没有手机性能结论。

```sh
blender --background --factory-startup --threads 2 --python-exit-code 1 --python tools/art/source/mine_kit_355/build_mine_props.py
output/art-setup/venv/bin/python tools/art/source/mine_kit_355/prepare_review.py mine_props
source ~/.codex-huangzhong/env.sh
godot --headless --path output/mine-kit-355/mine_props/project --editor --import > output/mine-kit-355/mine_props/import.log 2>&1
godot --path output/mine-kit-355/mine_props/project --rendering-method mobile --rendering-driver vulkan > output/mine-kit-355/mine_props/render.log 2>&1
output/art-setup/venv/bin/python tools/art/source/mine_kit_355/verify.py mine_props
output/art-setup/venv/bin/python tools/art/source/mine_kit_355/package_mine_props.py
```

源目录为 `tools/art/source/mine_kit_355/models/`，每件 `.blend` 保存命名部件并附独立 provenance；
生成会覆盖本批源文件，人工修改前先保留。先前头饰与本批共用静态导出工具，已通过的王冠和正式怪物不修改。
