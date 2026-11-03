# 守关头饰：王冠 v1、铁背 v1.1、石英 v1.2

黄忠 / SGODOT-355。按 r=1.0 m 的代码史莱姆制作，Y up、正面 +Z、背面 -Z。
原点是头顶接触中心；挂在 `(0, 1.43*r, 0)` 并随王统一缩放 r。
头饰按 r=1.0 归一化，游戏里随王的半径缩放；当前王 r=.85。
局部负 Y 包覆圆顶/后背，不要按 GLB 下沿重新落地。

| 件 | 三角形 | surface | 宽 × 高 × 深（m） |
| --- | ---: | ---: | --- |
| crown | 728 | 1 | 0.614 × 0.428 × 0.663 |
| ironback_plates | 672 | 1 | 1.020 × 0.837 × 1.625 |
| quartz_cluster | 280 | 1 | 0.900 × 0.767 × 0.594 |

王冠保持 v1；铁背改宽壳、护额、深铁色与暖磨损边；石英改五根外散的尖端棱柱，白底淡紫尖。
石英 v1.2 在 v1.1 基础上放大约 1.3 倍并重贴底面；头顶以上 .7026 m，随 r=.85 缩放后约 .5972 m。
无骨骼、动画、碰撞、贴图；不透明，线性顶点色。王冠/铁背平滑法线，石英保留返修要求的棱面。
每件 `.glb.import` 的 `import_script/path` 指向现有
`res://assets/monsters/material_import.gd`，它只打开线性顶点色并关投影。
UID 已由 Godot 生成，保持 `remove_immutable_tracks=false` 和空 `_subresources`。
manifest 的 `preview_body_tint` 仅用于审阅图，王的身体颜色由程序决定。
源和真实 Godot Vulkan Mobile 审阅：美术分支的
`tools/art/source/monsters/slime_king/`、`docs/design/mine-kit-355-2026-11-02/headgear/`。
