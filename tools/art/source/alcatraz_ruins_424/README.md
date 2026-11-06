# 恶魔岛废墟细节源文件 · 赵云

`alcatraz_ruins_details.blend`含五个命名collection与独立拱券石、碎片、茎叶和牌面，可编辑。`build_alcatraz_ruins_424.py`只重建本包五件和`ruin_details_manifest.json`，不修改主废墟、#802十件或#816花园。

源文件中原型为了检视而并排，GLB仍以各自本地底部原点导出。藤蔓特殊约定：背平面Z=0、正面+Z、底部Y=0；不是按厚度中心对齐。说明牌不含文字和挂点逻辑，运行时不应赋予交互。

按顺序运行，**每一步必须等待退出后再开始下一步**。Python需NumPy/Pillow；所有Blender/Godot操作使用共享锁和私有ADB5099：

```bash
mkdir -p output/alcatraz-ruins-424
source ~/.codex-zhaoyun/env.sh
flock ~/gs66-render.lock blender --background --python-exit-code 1 --python "$PWD/tools/art/build_alcatraz_ruins_424.py" > output/alcatraz-ruins-424/build.log 2>&1
python3 tools/art/source/alcatraz_ruins_424/prepare.py
python3 tools/art/source/alcatraz_ruins_424/placements.py
python3 tools/art/source/alcatraz_ruins_424/prepare.py
flock ~/gs66-render.lock godot --headless --path "$PWD/output/alcatraz-ruins-424/project" --import > output/alcatraz-ruins-424/import.log 2>&1
flock ~/gs66-render.lock godot --headless --path "$PWD/output/alcatraz-ruins-424/project" --script configure.gd > output/alcatraz-ruins-424/configure.log 2>&1
flock ~/gs66-render.lock godot --headless --path "$PWD/output/alcatraz-ruins-424/project" --import > output/alcatraz-ruins-424/reimport.log 2>&1
python3 tools/art/source/alcatraz_ruins_424/prepare.py --sync-imports
python3 tools/art/source/alcatraz_ruins_424/verify.py
nvidia-smi
flock ~/gs66-render.lock godot --path "$PWD/output/alcatraz-ruins-424/project" --rendering-method mobile --rendering-driver vulkan --display-driver x11 --disable-vsync --max-fps 60 --resolution 720x800 --quit-after 2400 res://review.tscn > output/alcatraz-ruins-424/render.log 2>&1
python3 tools/art/source/alcatraz_ruins_424/package.py
```

`prepare.py`导出固定v6 `b16c3198`的离线工程，独立QA用户目录、单一Avatar autoload，无生产存档或网络操作。只追加本包GLB与审阅脚本；原layout、导航、主体、树、水面均保持。`placements.py`使用真实地面三角形核落地件根部/角点，藤蔓按墙柱正面+20mm安装，输出世界坐标与相对ruins_000坐标。

`verify.py`独立读GLB，核对预算、1surface、法线、无退化面、UID、原点、低碎片范围、挂墙平面和相对坐标；`review.gd`验证实际导入缓存和尺寸，并沿实际导航路线检查高件UI净空。区域图使用检视相机而非伪造原生默认视角，另附默认路线图。原树在场景中仍遮住部分藤蔓，正式合成后由场景方重新核查。

`package.py`要求报告晚于当前脚本/点位、最终GLB SHA一致，才生成署名图与交付JSON；锁排队期间不能拿旧报告打包。渲染视口≤1500长边，签名后≤1600。完成后自动退出，不开编辑器挂机。
