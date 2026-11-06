# SGODOT-424 主楼远档 v1.1

黄忠。当前固定近档bf0c31b1 / Plane4aa1b62e，source.json和reference GLB为生成输入。
此头已把旧文字改成4个灯塔图形平面，总7面。v1.1远档2205面，近档7869面的28.02%。
同一生成管线保留25组拱窗、反光、主轮廓，59个小倒角件化为同包围方体；新的7面图形原样保留。
验证证明与已验v1远档除219面字换7面图形外，其余三角的位置/法线/颜色完全不变。

```bash
source ~/.codex-huangzhong/env.sh
flock ~/gs66-render.lock blender --background --python tools/art/source/alcatraz_museum_far_424/build.py
output/art-setup/venv/bin/python tools/art/source/alcatraz_museum_far_424/prepare.py
flock ~/gs66-render.lock godot --headless --path output/alcatraz-museum-far-424/project --editor --import
flock ~/gs66-render.lock godot --path output/alcatraz-museum-far-424/project --rendering-method mobile --rendering-driver vulkan --display-driver x11 --disable-vsync --max-fps 60 --resolution 960x800 res://review.tscn
output/art-setup/venv/bin/python tools/art/source/alcatraz_museum_far_424/verify.py
output/art-setup/venv/bin/python tools/art/source/alcatraz_museum_far_424/package_review.py
```

继承原UID和导入方式，55m按Godot AABB中心测距；相机只沿视线移动、正交大小不变。
历史b16c3198白模和d7b57574配色/带字版本仅为追溯，新审阅写入docs/v1.1，不覆盖历史图。
与旧远档/图形的精确差分由../alcatraz_tower_color_424/verify.py补核。

当前屋顶同步版本使用 ../museum_far_roof_424/ 的输入快照、blend和生成器；本目录保留原v1.1无字招牌版本供追溯。
