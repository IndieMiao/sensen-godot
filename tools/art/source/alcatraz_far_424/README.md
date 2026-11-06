# SGODOT-424 远景与双塔源

参考 `reference/landmark_alcatraz_v2.jpg`、`reference/c_alc2.png`，用户 11-05 定 B，采用真实人物比例。
每个 GLB 对应一个可编辑 `.blend`，对象按石基、塔身、灯室、支撑、罐体、桥索或城市轮廓命名。

```bash
source ~/.codex-huangzhong/env.sh
flock ~/gs66-render.lock blender --background --factory-startup --threads 3 --python-exit-code 1 --python /absolute/worktree/tools/art/source/alcatraz_far_424/build.py
python3 tools/art/source/alcatraz_far_424/prepare.py
flock ~/gs66-render.lock godot --headless --editor --path output/alcatraz-far-424/project --import --quit
flock ~/gs66-render.lock godot --headless --path output/alcatraz-far-424/project --script configure.gd -- /absolute/worktree
flock ~/gs66-render.lock godot --path output/alcatraz-far-424/project --rendering-method mobile --rendering-driver vulkan --display-driver x11 --disable-vsync --max-fps 60
output/art-setup/venv/bin/python tools/art/source/alcatraz_far_424/verify.py
python3 tools/art/source/alcatraz_far_424/sync_placement.py
python3 tools/art/source/alcatraz_far_424/prepare_island.py
flock ~/gs66-render.lock godot --headless --editor --path output/alcatraz-far-424/island-project --import --quit
flock ~/gs66-render.lock godot --path output/alcatraz-far-424/island-project --rendering-method mobile --rendering-driver vulkan --display-driver x11 --disable-vsync --max-fps 60
```

导出前把各命名部件的平涂材质色转为线性 COLOR_0，合为一个 surface；保留源中的独立部件。
远档是单独建模，保留全高、底部中心和外包围，不用运行时缩放伪造距离。
独立审阅工程不加载账号、网络或主体场景；带实际 1.75 m 默认人物，截图最长边 1500 px。
v1.1 已按马可波罗 34df9c0b 布局确认。`prepare_island.py` 仅在 output 中取该头的白模、相机、shader 和导航，
替换本包七件并去掉三卡 LOD；原宿主脚本逐文件哈希核对不变。`review_island.gd` 检查真实开场、
两塔55 m切档和四个视角预算，通过实际桥开 / 关像素比较确认桥在画面上缘可见。
`build.py -- --cards-only` 只重建三张卡片，不动四个塔 GLB。命名已改为 city / bridge，旧 skyline / goldengate 不再交付。

v1.2 双塔配色：四塔按bf0c31b1正式整岛校色，源材质及本生成器PAL已同步。
精确RGB字节更新与对照复现见 ../alcatraz_tower_color_424/；几何、UID、三卡均不变。
