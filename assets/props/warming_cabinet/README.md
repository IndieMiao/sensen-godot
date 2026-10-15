# Warming Cabinet（SGODOT-282，正式模型）

农舍厨房的保温柜，替换 Basic Room、Standard Room 里的 `warming_cabinet_placeholder`（Deluxe pantry 缩到 0.6 倍）。刘备制作，审阅材料在 wp-3d-scene（#425，154ce642）。不知火舞验收通过，玻璃选 B（282 aeaf6973）：没有玻璃面，门框内侧画了两道斜高光。A 案留在 wp-3d-scene，没有带过来。运行时文件从 `warming_cabinet_b.glb` 改名为 `warming_cabinet.glb`。

- 尺寸 0.56 宽 × 0.50 深 × 1.32 高（米），导入 scale 1；1490 面，8 个网格节点。轴心在地面、宽度中心、背面（z = 0），+Z 朝前。
- 6 盘菜是独立的 MeshInstance3D：`dish_1` … `dish_6`，顺序是上层左、右，中层左、右，下层左、右（从 +Z 看）。隐藏一个节点就少一盘，以后可以按存量显示。
- 空节点：`top_center` (0, 1.32, 0.25)、`door_center` (0, 0.795, 0.498)、`glow` (0, 0.795, 0.25)。
- 材质：`room_albedo_ao.png` 是占位那张贴图集的逐字节副本；`interior_food.png` 是 256² 的柜内琥珀色和菜色小图。没有自发光，没有灯。
- 数值汇总见 `manifest.json`：collider、sockets、两个房间的落位。

## 接入（程序改 anchors 时照做）
- prop 条目**不要带 `atlas`**。`p0_room.gd` 的 `_prop_node` 遇到 atlas 会给所有网格套同一个 material_override，柜内菜色和高光就没了。用 glb 自带的材质。
- 高光：glb 的 specular 是 0.5，房间里其他东西是 0.28。不知火舞要求对齐到 0.28，用 metallic_specular 0.28（只改这一项，保留各 surface 的贴图）。
- 落位（yaw 90，门朝 +X 正对镜头）：Standard (−2.916, 0.082, −1.19)；Basic (−2.850, 0.082, −1.69)。新柜子的外包络完全在占位里面，原来核过的避让照用。
- collider：at (0, 0.66, 0.25)，size (0.56, 1.32, 0.50)。
- `use_warming_cabinet` 改到 top_center：Standard 约 (−2.666, 1.402, −1.19)，Basic 约 (−2.600, 1.402, −1.69)；badge、stand、cam 跟着核一下。
- 接入后删掉 `assets/props/warming_cabinet_placeholder/`。
