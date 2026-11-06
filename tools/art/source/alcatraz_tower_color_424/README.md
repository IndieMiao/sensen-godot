# 黄忠 · SGODOT-424 双塔校色

recolor.py从固定已验收基线fc19d492读取四个塔GLB，只覆盖COLOR_0 RGB字段；不经Blender重导，
保证JSON/所有非RGB数据原字节。它同时更新原alcatraz_far_424/build.py色表和alc_far_manifest.json。
update_blends.py只同步四份命名编辑源的材质颜色，不动网格/变换。

palette来自马可波罗bf0c31b1的tools/art/source/alcatraz_island/palette.json；实际文件备份在reference。
colour-map.json记录旧新色和每件使用的role及SHA。灯塔仍暖白、水塔仍锈红；roof/glass/stone
直接用整岛同名色，其余作邻近色调整，不改灯光或材质参数。

```bash
output/art-setup/venv/bin/python tools/art/source/alcatraz_tower_color_424/recolor.py
source ~/.codex-huangzhong/env.sh
flock ~/gs66-render.lock blender --background --python tools/art/source/alcatraz_tower_color_424/update_blends.py
output/art-setup/venv/bin/python tools/art/source/alcatraz_tower_color_424/prepare.py
flock ~/gs66-render.lock godot --headless --path output/alcatraz-tower-color-424/project --editor --import
flock ~/gs66-render.lock godot --path output/alcatraz-tower-color-424/project --rendering-method mobile --rendering-driver vulkan --display-driver x11 --disable-vsync --max-fps 60 --resolution 960x800 res://review.tscn
output/art-setup/venv/bin/python tools/art/source/alcatraz_tower_color_424/verify.py
output/art-setup/venv/bin/python tools/art/source/alcatraz_tower_color_424/package_review.py
```

prepare仅在output解包固定宿主，继承已验证alcatraz-ferry-424/project的Avatar fixture/缓存；
新机器先按该源目录prepare建立。主体场景/layout/shader哈希保留。模型替换只在隔离工程，
不提交接入代码；同一场景两帧互换塔mesh、冻结Engine时间，避免海水时间变化污染比较。
GLB/import验证逐字节屏蔽COLOR_0 RGB后比较，而非只比较生成参数。
图形牌小增量由alcatraz_museum_far_424生成；verify另核牌以外远档与原已验件一致。
