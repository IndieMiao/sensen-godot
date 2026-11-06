# SGODOT-424 黄忠渡轮与海鸥

`build.py` 以米 / Godot Y-up 坐标建模；共享 `alcatraz_far_424/build.py` 的造型 primitives，
不调用该包的生成入口、不修改它的资产。构件有独立名称，源材质对应 manifest 的色板。

- ferry.blend：近档命名可编辑构件，船头 −X / 原点 Y=0 / 水下到 -1 m。
- ferry_far.blend：远档命名构件；相同轴心和 25 m 长度。
- gull.blend：单个海鸥的命名构件，脚底原点，−Z 朝前。
- gull_export_poses.blend：Export scene 中 gull 单网格及 stand/preen/spread shape keys。

生成（所有 Blender/Godot 必须用共享锁）：

```bash
source ~/.codex-huangzhong/env.sh
flock ~/gs66-render.lock blender --background --python tools/art/source/alcatraz_ferry_424/build.py
output/art-setup/venv/bin/python tools/art/source/alcatraz_ferry_424/prepare.py
flock ~/gs66-render.lock godot --headless --path output/alcatraz-ferry-424/project --editor --import
output/art-setup/venv/bin/python tools/art/source/alcatraz_ferry_424/sync_imports.py
flock ~/gs66-render.lock godot --path output/alcatraz-ferry-424/project --rendering-method mobile --rendering-driver vulkan --display-driver x11 --disable-vsync --max-fps 60 --resolution 960x800 res://review.tscn
output/art-setup/venv/bin/python tools/art/source/alcatraz_ferry_424/verify.py
output/art-setup/venv/bin/python tools/art/source/alcatraz_ferry_424/package_review.py
```

`prepare.py` 固定从 b16c3198 取宿主，复制至 output；Avatar 审阅 fixture 复用此前已验证的
alcatraz-far-424/island-project，若在新机器上请先按该包 prepare / prepare_island 建好。
原 ferry/gull 的 UID 从指定白模保留，ferry_far 和新导入脚本 UID 由 Godot 生成。
`sync_imports.py` 只回写本包三件及脚本 UID。材质导入仅开启线性顶点色、哑光和关闭投影。

`verify.py` 直接解码 GLB（包括 sparse morph accessors），查面数、bounds、法线、形态脚点、
原点单位变换、UID、精确原点位、55 m LOD、宿主字节哈希；不靠生成器预设数字宣布通过。
最终文件名和说明在 runtime README；不提交 fixture 中的主体 layout 或玩法脚本。
