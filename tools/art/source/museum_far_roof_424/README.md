# SGODOT-424 主楼远档屋顶 · 黄忠

固定近档#835 ebce1cec（通风口已放大1.5倍）。reference内包含该头的近档、旧远档、旧远档清单及总manifest，均为可复现输入，source目录.gdignore不进运行时。
contract.json是马可波罗近档合同原样快照。build.py从旧远档保留全部非屋顶组件；108面近档屋顶板原样继承，其余屋顶用低面方体与平面色块。
平面玻璃按43°/14.5°视线把近档彩色面投到同一高度，以保持默认镜头分色比例；法线保持近档坡面光照。三块3.8×2m白框位置不变。

```bash
source ~/.codex-huangzhong/env.sh
flock ~/gs66-render.lock blender --background --python "$PWD/tools/art/source/museum_far_roof_424/build.py"
python3 tools/art/source/museum_far_roof_424/prepare.py
flock ~/gs66-render.lock godot --headless --path output/museum-far-roof-424/project --editor --import
flock ~/gs66-render.lock godot --path output/museum-far-roof-424/project --rendering-method mobile --rendering-driver vulkan --display-driver x11 --disable-vsync --max-fps 60 --resolution 960x800 res://review.tscn
output/art-setup/venv/bin/python tools/art/source/museum_far_roof_424/verify.py
output/art-setup/venv/bin/python tools/art/source/museum_far_roof_424/package_review.py
```

新blend保留命名的楼体部件/屋面/压顶/天窗/通风口。导出后回填自定义法线，避免Blender的法线量化改变原楼体光照。
verify.py独立读取GLB，核1,941个非屋顶三角、包围、合同颜色、天窗基座、通风口方体、.import/UID及总manifest范围。
review.gd使用真实visibility_range在54/56m切换，并用固定相机强制近/远档作像素对齐控制。
隔离工程关闭近档自动生成的内部网格LOD，验证完整近档与显式远档；原近档.import不改。所有Godot/Blender经flock且用完退出。
