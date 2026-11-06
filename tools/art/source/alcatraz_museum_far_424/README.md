# SGODOT-424 主楼远档

黄忠制作；当前为形体 v0，等待马可波罗近档正式配色，不作为最终配色交件。
输入文件及固定提交由 `reference/source.json` 管理；目前输入是 b16c3198 的实际近档 GLB。

`build.py` 直接读近档顶点、法线、颜色和连通件：保留主体、屋顶、两根墙角饰条、公共入口
门框和玻璃门（552 面），仅把 25 个浅窗盒改成同 X/Y 外轮廓、同正面 Z 的 12 顶点面片
（250 面）；合计 802 面，占近档 3,252 面的 24.66%。原点不重新居中，包围保持原样。
色值直接来自近档，Blender 导出后的结构法线再按源 GLB 恢复，避免自定义法线量化差异。
`alc_museum_far.blend` 保留命名独立构件、顶点色和法线，可以直接编辑查看。

正式色交接后：把指定头的近档 GLB 放入 reference，更新 source.json 的 near_file / git_ref /
revision / colour_status，再执行同一脚本。脚本会核实仍是 25 个 1.25 × 2.15 × 0.04 m 窗盒；
如果近档形状变化而不只是配色，必须检查并适配，不能静默套旧布局。

```bash
source ~/.codex-huangzhong/env.sh
flock ~/gs66-render.lock blender --background --python tools/art/source/alcatraz_museum_far_424/build.py
output/art-setup/venv/bin/python tools/art/source/alcatraz_museum_far_424/prepare.py
flock ~/gs66-render.lock godot --headless --path output/alcatraz-museum-far-424/project --editor --import
flock ~/gs66-render.lock godot --path output/alcatraz-museum-far-424/project --rendering-method mobile --rendering-driver vulkan --display-driver x11 --disable-vsync --max-fps 60 --resolution 960x800 res://review.tscn
output/art-setup/venv/bin/python tools/art/source/alcatraz_museum_far_424/verify.py
```

使用现有 alc_far_material_import.gd 开启线性顶点色和哑光，不改共享脚本。
`.import` 保留原占位 UID，nodes/root_script=null 一行保留；资源本身无根节点脚本。
本包不修改主体场景/layout。装配时将 alc_museum 的 far_placeholder 改 false，保留55m和原坐标。

54/56m 测的是相机到实际全球 AABB 中心的距离，符合 Godot visibility_range 规则。
相机只沿视线移动2m，正交方向/投影宽度保持，所以画面可直接比较；另有完全相同相机
位置强制近/远的控制图。Godot 实际提交三角数分别验证只显示3,252或802，防止两档叠画。
