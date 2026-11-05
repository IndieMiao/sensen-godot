# 教堂源文件与复现

参考 `reference/church_concept_v1.jpg`、`reference/c_church.png`（上官婉儿派活，SGODOT-423）。
使用 Basic Room / 茶馆的建模与导出管线；全部新制几何按模块保留命名对象和本地轴。

所有 Godot / Blender 命令必须使用 gs66 共享渲染锁，避免三位美工同时占 RTX 2060：

```bash
source ~/.codex-huangzhong/env.sh
flock ~/gs66-render.lock blender --background --factory-startup --threads 3 --python-exit-code 1 --python /absolute/worktree/tools/art/build_poi_church.py
output/art-setup/venv/bin/python tools/art/source/poi_church/finalize.py
python3 tools/art/source/poi_church/bench_data.py
python3 tools/art/source/poi_church/prepare_review.py
flock ~/gs66-render.lock godot --headless --editor --path output/church-423/project --import --quit
flock ~/gs66-render.lock godot --headless --path output/church-423/project --script configure_imports.gd -- /absolute/worktree
flock ~/gs66-render.lock godot --path output/church-423/project --rendering-method mobile --rendering-driver vulkan --disable-vsync res://review.tscn
flock ~/gs66-render.lock godot --path output/church-423/project --rendering-method mobile --rendering-driver vulkan --display-driver x11 --disable-vsync --max-fps 60 --resolution 960x720 --borderless -- --slug poi_church --output /absolute/worktree/output/church-423/bench --test
output/art-setup/venv/bin/python tools/art/source/poi_church/verify.py
```

`--geometry-only` 可只生成可编辑源与 layout；完整生成会重建源文件，不覆盖未记录手工改动。
图集烘焙使用 16 samples、柔和接触 AO，不烘实时直射光；所有审阅图长边不超过 1600。
bench 使用现有共享脚本，仅在 layout 中提供路线 / 碰撞 / 尺度数据，不改共享程序。
自定义 review 用 1.745 m 原角色、原 i-seat / i-door 资源模拟挂点展示，未进行玩法接入。

`verify.py` 从 GLB 顶点、索引、UV、材质和 import 实测；review 验人物、胶囊通行、挂点投影、操作区，
使用洋红背景控制图检测露底。正式媒体和检查汇总由 `package_review.py` 生成。
