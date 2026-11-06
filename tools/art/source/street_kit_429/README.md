# SGODOT-429 街道家具 · 黄忠

16件可编辑blend保留命名部件，build.py导出临时副本时合成单mesh/surface；源对象不被破坏。
基础几何函数读取alcatraz_far_424/build.py，色板值以reference记录为准，不改旧目录。
墙牌原点在背面中心，其他件底部中心；转角原点为两臂弯点，详见运行时README和manifest。

复现（仓库根目录；已验证gs66工具链与本工位Avatar fixture）：

```bash
source ~/.codex-huangzhong/env.sh
flock ~/gs66-render.lock blender --background --python "$PWD/tools/art/source/street_kit_429/build.py"
python3 tools/art/source/street_kit_429/prepare.py
flock ~/gs66-render.lock godot --headless --path output/street-kit-429/project --editor --import
python3 tools/art/source/street_kit_429/sync_imports.py
flock ~/gs66-render.lock godot --path output/street-kit-429/project --rendering-method mobile --rendering-driver vulkan --display-driver x11 --disable-vsync --max-fps 60 --resolution 960x800 res://review.tscn
output/art-setup/venv/bin/python tools/art/source/street_kit_429/verify.py
python3 tools/art/source/street_kit_429/cold_import.py
output/art-setup/venv/bin/python tools/art/source/street_kit_429/package_review.py
```

prepare.py复用本工位已验证的output/church-kit-427-v11/project Avatar隔离工程，并从git读取固定的#830地材版本。
新机需要先按scene_bench流程建立Avatar fixture。旧环境文件只在新output工程中移除，不修改任何原场景文件。
所有Godot/Blender调用经共享flock；审阅程序出图后自行退出。

verify.py独立读取GLB顶点/索引/颜色，测预算、边界、单位比例、原点与座高；验证线性颜色来自指定暖色板、
唯一UID、root_script和所有旧文件保持不变。cold_import.py用全新缓存复导套件和原样的#830依赖，比较整个隔离工程内容哈希和源工作区状态。
本目录.gdignore阻止源/审阅脚本进入运行时扫描，示例只在内存装配，不交layout。

v1.1木色增量：`recolor_wood.py`从已验收76a13070的两件GLB生成颜色补丁，逐字节确认仅COLOR_0 RGB改变；
随后用`flock ~/gs66-render.lock blender --background --python "$PWD/tools/art/source/street_kit_429/update_wood_blends.py"`同步两份编辑源。
build.py也已按模块使用#830 v1.1木色，重新生成时不会改动其他件使用的饰边色。

v1.2补充：伞面Ø1.6m、矮柱奶油石帽均在build.py中；只重建这两件可分别用`-- --only umbrella_table`和`-- --only bollard`。recolor_wood.py仅用于复现历史v1.1，不要在v1.2之后执行它覆盖新几何。
