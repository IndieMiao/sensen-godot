# SGODOT-424 主楼远档 v1

黄忠制作。正式源近档固定为马可波罗d7b57574 / Plane7726588c；
reference/source.json记录近档GLB和提交，palette-d7b57574.json为追溯用色板。
旧b16c3198参考与docs/v0留作历史，不作为本版生成输入。

build.py直接解码正式近档顶点、法线、COLOR_0和连通件，不依赖可能继续变化的主体生成器：
96个组件的1490面原样保留（包含25组拱窗、反光、主体/基座/屋顶轮廓等）；
59个小倒角方件由6372面简化为同包围708面；12个字由916面保留原正面219面。
合计2417面，是近档8778面的27.53%。原点不重新居中，所有原窗位和10种颜色不变。
结构和文字保留面的原法线在导出后按源恢复，避免Blender自定义法线内部量化造成差异。
Blender源保留独立组件、顶点色和自定义法线；每个组件的原包围/处理方式见manifest.parts。

```bash
source ~/.codex-huangzhong/env.sh
flock ~/gs66-render.lock blender --background --python tools/art/source/alcatraz_museum_far_424/build.py
output/art-setup/venv/bin/python tools/art/source/alcatraz_museum_far_424/prepare.py
flock ~/gs66-render.lock godot --headless --path output/alcatraz-museum-far-424/project --editor --import
flock ~/gs66-render.lock godot --path output/alcatraz-museum-far-424/project --rendering-method mobile --rendering-driver vulkan --display-driver x11 --disable-vsync --max-fps 60 --resolution 960x800 res://review.tscn
output/art-setup/venv/bin/python tools/art/source/alcatraz_museum_far_424/verify.py
output/art-setup/venv/bin/python tools/art/source/alcatraz_museum_far_424/package_review.py
```

共享材质导入脚本不改，.import保留原占位UID及nodes/root_script=null。
54/56m距离按实际AABB中心计算，符合Godot visibility_range；相机只沿视线移动2m，
正交方向/宽度不变。另有完全同一相机位置的强制切档控制。实际提交面数验证只显示一档，
不会因叠画遮住差异。图片对比记录全幅、对象均差、最大值及差异像素数，不只给平均数。
