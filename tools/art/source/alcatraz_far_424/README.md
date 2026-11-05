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
```

导出前把各命名部件的平涂材质色转为线性 COLOR_0，合为一个 surface；保留源中的独立部件。
远档是单独建模，保留全高、底部中心和外包围，不用运行时缩放伪造距离。
独立审阅工程不加载账号、网络或主体场景；带实际 1.75 m 默认人物，截图最长边 1500 px。
布局确认前不修改马可波罗文件，也不把推测的开场相机当作验收证据。
