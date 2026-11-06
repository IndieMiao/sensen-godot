# 教堂套件准备 / 复现

用户只授权套件和审阅示例；不改已上线poi_church，不创建新教堂/游戏layout。
original-files.json记录开始时原目录71个文件的SHA-256，verify.py核对文件集合和内容均不变。

- prepare_assets.py把七件现有GLB和2048²图集复制到新kit；不复制.import UID。
- build.py按2m模数生成墙/真窗洞/转角、上层带/木梁/地板/小台阶；从原编辑源提取彩窗和
  石框，玻璃原材料名映射六个UV色组；玫瑰窗等比缩放0.92适合2m墙段。
- copy_editable.py仅追加原blend的相关命名集合，保存到本目录，保留原件编辑能力。
- finish_assets.py读实际导出顶点统计并生成manifest、独立provenance和两款8×1色板。
- prepare_review.py建立隔离工程；原房间复制仅用于已有Avatar依赖/缓存，新review只加载新kit。
- sync_imports.py仅回拷新kit由Godot生成的.import、shader/脚本.uid。
- review.gd为审阅源，例子只在内存中装配，不导出layout或完整游戏场景。

```bash
output/art-setup/venv/bin/python tools/art/source/church_kit/prepare_assets.py
source ~/.codex-huangzhong/env.sh
flock ~/gs66-render.lock blender --background --python tools/art/source/church_kit/build.py
flock ~/gs66-render.lock blender --background --python tools/art/source/church_kit/copy_editable.py
output/art-setup/venv/bin/python tools/art/source/church_kit/finish_assets.py
output/art-setup/venv/bin/python tools/art/source/church_kit/prepare_review.py
flock ~/gs66-render.lock godot --headless --path output/church-kit-423/project --editor --import
flock ~/gs66-render.lock godot --path output/church-kit-423/project --rendering-method mobile --rendering-driver vulkan --display-driver x11 --disable-vsync --max-fps 60 --resolution 960x800 res://review.tscn
output/art-setup/venv/bin/python tools/art/source/church_kit/sync_imports.py
output/art-setup/venv/bin/python tools/art/source/church_kit/verify.py
output/art-setup/venv/bin/python tools/art/source/church_kit/package_review.py
```

prepare_review复用本工位output/church-423/project的已验证Avatar fixture；新机器先按原教堂
审阅工具建立对应隔离工程。不要在原poi_church上运行改写生成器。
碰撞射线只在临时接缝测试场景创建，用于核验真窗洞和闭合接缝，之后清除；GLB无碰撞节点。
同一灯光/相机下出Classic和Meadow两套玻璃图，变化来自palette_texture，石墙/石框不换材质。
所有运行时路径以新kit为根，无外部原教堂依赖；所有模型保持米制，人物实测1.745m。
