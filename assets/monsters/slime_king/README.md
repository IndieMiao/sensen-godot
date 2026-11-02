# 守关头饰 v1

黄忠 / SGODOT-355。按 r=1.0 m 的代码史莱姆制作，Y up、正面 +Z、背面 -Z。
原点是头顶接触中心；挂在 `(0, 1.43*r, 0)` 并随王统一缩放 r。
局部负 Y 包覆圆顶/后背，不要按 GLB 下沿重新落地。

| 件 | 三角形 | surface | 宽 × 高 × 深（m） |
| --- | ---: | ---: | --- |
| crown | 728 | 1 | 0.614 × 0.428 × 0.663 |
| ironback_plates | 672 | 1 | 0.460 × 0.651 × 1.225 |
| quartz_cluster | 368 | 1 | 0.483 × 0.547 × 0.392 |

无骨骼、动画、碰撞、贴图；不透明平滑法线，线性顶点色。
每件 `.glb.import` 的 `import_script/path` 指向现有
`res://assets/monsters/material_import.gd`，它只打开线性顶点色并关投影。
UID 已由 Godot 生成，保持 `remove_immutable_tracks=false` 和空 `_subresources`。
manifest 的 `preview_body_tint` 仅用于审阅图，王的身体颜色由程序决定。
源和真实 Godot Vulkan Mobile 审阅：美术分支的
`tools/art/source/monsters/slime_king/`、`docs/design/mine-kit-355-2026-11-02/headgear/`。
