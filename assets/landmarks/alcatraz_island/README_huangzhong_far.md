# SGODOT-424 · 黄忠 · 远景与双塔

本包只拥有 `alc_*` 文件，不修改马可波罗的 `layout.json`、`manifest.json` 或主体场景。
当前为独立模型预看；已在 424 留言核对 v2 坐标和开场机位，确认后补最终建议摆位及开场桥截图。

| 文件 | 用途 |
| --- | --- |
| alc_lighthouse / alc_lighthouse_far | 白色 15 m 灯塔，近远档共享底部中心原点和 bounds |
| alc_watertower / alc_watertower_far | 锈红木铁结构 12 m 水塔，远档保留开放斜撑 |
| alc_far_goldengate | 橙红双塔悬索桥的压缩比例远景卡片 |
| alc_far_skyline | 包含泛美金字塔、赛富时大楼轮廓的浅色城市远景 |
| alc_far_hills | 三层低对比对岸山丘 |

单位米，Y 向上、+Z 正面，原点为底部 / 外包围中心。两塔按真实尺寸制作；三张远景是故意压缩的布景，
不代表真实建筑尺寸、不作为可走桥或交互对象。具体尺寸、三角形和 SHA-256 见 `alc_far_manifest.json`。
全部为单 mesh / 单 surface，平涂线性顶点色、哑光、无贴图、无骨骼或动画。

`alc_far_material_import.gd` 仅供这七件 GLB 的 import 使用：打开顶点色、保留线性色值和哑光，
三件远景关闭投影；不包含染色、玩法或运行时控制。GLB import 和该脚本 UID 均由 Godot 生成。
两档塔应放在相同位置、同角度、单位比例，给宿主的 visibility_range 用；不要同时绘制近远档。
切档距离需结合 v2 相机距离与屏幕像素再定，不能直接把默认相机到人物的偏移当作 LOD 距离。

坐标待核：马可波罗远端 d93763c3 仍为 v1 小岛，不能沿用它的摆位。
43° 正交下，深度退后 20 m 会让投影上移约 13.64 m，超过默认画面半高约 7.47 m；
“离岛 20–40 m”与“码头开场上缘可见”需要在 v2 机位中确认压缩远景深度或背景层投影的处理。
核对评论 `a1b86c07`，投影约束说明 `ae4cdbf8`。

生成与源文件在 `tools/art/source/alcatraz_far_424/`。所有 Blender / Godot 调用须使用
`flock ~/gs66-render.lock`，一次只运行一个，完成后退出。
