# SGODOT-424 黄忠动作增量

在原#815基础上增加gull的turn_head shape和两个外链AnimationPlayer场景，不动原海鸥网格
或原两种形变，不改两个船身GLB。小旗是独立52面单surface顶点色件，Blender源带flutter形态。

```bash
source ~/.codex-huangzhong/env.sh
flock ~/gs66-render.lock blender --background --python tools/art/source/alcatraz_ferry_424/build.py -- --gull-only
flock ~/gs66-render.lock blender --background --python tools/art/source/alcatraz_anim_424/build_flag.py
output/art-setup/venv/bin/python tools/art/source/alcatraz_anim_424/prepare.py
flock ~/gs66-render.lock godot --headless --path output/alcatraz-anim-424/project --editor --import
flock ~/gs66-render.lock godot --headless --path output/alcatraz-anim-424/project --script build_scenes.gd
flock ~/gs66-render.lock godot --path output/alcatraz-anim-424/project --rendering-method mobile --rendering-driver vulkan --display-driver x11 --disable-vsync --max-fps 60 --resolution 960x800 res://review.tscn
```

运行 sync_delivery.py 把独立工程生成的两个场景、两个动画库和旗帜import拷回runtime，
并生成动作manifest；UID由Godot生成。再跑verify.py和package_review.py。
prepare复用已验证的output/alcatraz-ferry-424/project（b16c3198固定宿主），在新机器先按其脚本建立。
录制每个动画按30fps固定时刻取样，180帧正常速率编码成6s，不是GPU吞吐性能视频。

build_scenes.gd使用原生AnimationLibrary，采样smoothstep转头/理毛/扑翅、sin渡轮起伏；
所有循环首尾一致。手写轻量tscn只外链模型，避免PackedScene重新打包一份内嵌ArrayMesh。
生成器未放入运行时依赖，不添加根脚本。验证脚本直接解码GLB含sparse morph，再在Godot
逐时间取样根位置、船身范围、静止占比、错峰偏移、循环首尾和镜头里的桥。
