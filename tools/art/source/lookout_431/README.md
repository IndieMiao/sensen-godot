# SGODOT-431 观景道具 · 黄忠

5件新模型在street_kit内，使用现有哑光顶点色材质。build.py读取street_kit_429的基础建模/导出函数，仅输出新5件与追加清单。
命名Blender部件可编辑；每件独立来源记录在modules/。原16件的文件哈希保存在provenance.json，验证时只允许共用README和manifest更新。

```bash
source ~/.codex-huangzhong/env.sh
flock ~/gs66-render.lock blender --background --python "$PWD/tools/art/source/lookout_431/build.py"
python3 tools/art/source/lookout_431/prepare.py
flock ~/gs66-render.lock godot --headless --path output/lookout-431/project --editor --import
python3 tools/art/source/lookout_431/sync_imports.py
flock ~/gs66-render.lock godot --path output/lookout-431/project --rendering-method mobile --rendering-driver vulkan --display-driver x11 --disable-vsync --max-fps 60 --resolution 960x800 res://review.tscn
output/art-setup/venv/bin/python tools/art/source/lookout_431/verify.py
python3 tools/art/source/lookout_431/cold_import.py
output/art-setup/venv/bin/python tools/art/source/lookout_431/package_review.py
```

需要本工位已验证的output/street-kit-429/project Avatar fixture；新机器先按scene_bench流程建立角色隔离工程。
prepare.py只在新output目录准备资源，从provenance指定的合入基线读取地材的13个运行时文件，不复制地材审阅目录。
无图片生成器；望远镜币口/箭头、圆盘船/灯塔均为顶点色几何。平面图形在导出前明确法线朝上，verify.py检查Godot坐标系的法线。
review.gd在临时场景用射线检查半圆台顶面及新旧栏杆/端柱接缝，随后删除临时碰撞；交付模型不带碰撞节点。
运行结束自动退出，所有Godot/Blender均经共享flock。只交套件及图片，不交可上线观景角或layout。
