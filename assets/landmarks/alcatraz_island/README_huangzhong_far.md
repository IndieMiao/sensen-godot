# SGODOT-424 · 黄忠 · 远景与双塔

本包仅拥有下表七件及其导入器、独立清单，不修改马可波罗的 `layout.json`、`manifest.json` 或主体场景。
v1.1 已按 #792 的 `34df9c0b` 对齐命名、摆位与 FarZone，并用该白模原场景实拍开场。

| 文件 | 用途 |
| --- | --- |
| alc_lighthouse / alc_lighthouse_far | 白色 15 m 灯塔，近远档共享底部中心原点和 bounds |
| alc_watertower / alc_watertower_far | 锈红木铁结构 12 m 水塔，远档保留开放斜撑 |
| alc_far_bridge | 橙红双塔悬索桥，XY 卡片 2.0×0.9 m，498 面 |
| alc_far_city | 泛美金字塔、赛富时大楼轮廓，XY 卡片 4.8×0.91 m，208 面 |
| alc_far_hills | 三层低对比对岸山丘，XY 卡片 8.0×0.52 m，120 面 |

单位米，Y 向上、+Z 正面，原点为底部 / 外包围中心。两塔按真实尺寸制作；三张远景是故意压缩的布景，
不代表真实建筑尺寸、不作为可走桥或交互对象。具体尺寸、三角形和 SHA-256 见 `alc_far_manifest.json`。
全部为单 mesh / 单 surface，平涂线性顶点色、哑光、无贴图、无骨骼或动画。

`alc_far_material_import.gd` 仅供这七件 GLB 的 import 使用：打开顶点色、保留线性色值和哑光，
三件远景关闭投影；不包含染色、玩法或运行时控制。GLB import 和该脚本 UID 均由 Godot 生成。
两档塔应放在相同位置、同角度、单位比例，给宿主的 visibility_range 用；不要同时绘制近远档。
两塔沿用宿主 55 m 切档，margin=0；三个远景卡片各单档，马可波罗已在 424 `6b09d152` 确认。
合成时移除三卡的 `lod_group` 和 `_far` 占位，两塔 near/far 仍保留。

完整摆位合同在 `alc_far_placement.json`，均为米、单位比例、yaw=0，FarZone 本身保持单位变换：

| 件 | 节点 | 世界坐标 X / Y / Z |
| --- | --- | --- |
| 灯塔近 / 远 | SummitZone | −25 / 10 / −11.5 |
| 水塔近 / 远 | SummitZone | 25 / 10 / −14 |
| 桥 | FarZone | −19.048384 / 30.166543 / 39 |
| 城市 | FarZone | −15.691458 / 30.881962 / 39 |
| 山丘 | FarZone | −16.827648 / 30.411582 / 39 |

`far_anchor=(-22,-0.15,39)` 是安装基准，不要再加到表内坐标。远景 Y≈30–31 m 是宿主假高度，
不是地理海拔；GLB 本地底部仍 Y=0、Z=0。宿主 `far_card.gdshader` 将 XY 卡片面向相机并推入远深度。
layout 注记的深度值为 0.92；该头实际脚本使用桥 0.94 / 城市 0.96 / 山丘 0.98，本次保持宿主脚本字节不变。
默认出生 (-22,1,19)，43° / yaw 14.5° / 宽 6.72 m，最远 20.16 m；开场图见审阅 v1.1。

生成与源文件在 `tools/art/source/alcatraz_far_424/`。所有 Blender / Godot 调用须使用
`flock ~/gs66-render.lock`，一次只运行一个，完成后退出。
