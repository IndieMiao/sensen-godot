# SGODOT-424 · 刘备 · 独立岸边浪花源

六个collection保留命名的浪花片、浮标壳体/顶环、漂木/分叉/海草。Blender5.2.2 LTS，Godot4.7.2；米制，Godot Y-up/+Z南，Blender映射(x,-z,y)。`alcatraz_foam.blend` 可编辑，`build.py` 可确定性重建并覆盖六个GLB和blend；手改前另存或同步生成器。

实际参考为用户指定 `~/incoming/landmark/c_alc2.png` 和 `landmark_alcatraz_v2.jpg`；本目录保存原件、哈希及只读layout。独立小浮标、单根漂木及浪花模块细节按概念海岸作制作推定，不是另行生成的新设定。

`provenance.json` 固定宿主 #792 d7b57574、自然件 #801 af3197575、码头 #821 cc59ef9fb；`prepare.py` 只把这些内容解包到 `output/alcatraz-foam-424/project`。本分支运行资产仅新增本包六件、两材质、一张纹样与建议表，不复制其他成员件或改宿主水体。

`texture.py` 用 NumPy/Pillow 生成原创512×128柔边纹样；无照片。纹样RGB保留浅白绿，alpha可平铺、两边归零。Blender源链接此PNG；导出仅保留同名材质占位，避免在四个GLB重复嵌图。Godot `.import` 绑定共享 `alc_foam_material.tres` 后才是完整透明效果；不要覆盖网格材质。

在仓库根目录，使用现有已验证工具环境；所有Blender/Godot均经共享 `flock /home/deck/gs66-render.lock`。Python需要 NumPy/Pillow，当前位于 `wt-3d-scene/output/wild-ground-422/venv/bin/python`。

```sh
python tools/art/source/alcatraz_foam_424/texture.py
flock /home/deck/gs66-render.lock blender --background --python /绝对路径/tools/art/source/alcatraz_foam_424/build.py
python tools/art/source/alcatraz_foam_424/prepare.py
python tools/art/source/alcatraz_foam_424/placements.py
python tools/art/source/alcatraz_foam_424/prepare.py
flock /home/deck/gs66-render.lock godot --headless --editor --path output/alcatraz-foam-424/project --import
flock /home/deck/gs66-render.lock godot --headless --path output/alcatraz-foam-424/project --script res://configure_imports.gd
flock /home/deck/gs66-render.lock godot --headless --editor --path output/alcatraz-foam-424/project --import
flock /home/deck/gs66-render.lock godot --headless --path output/alcatraz-foam-424/project --script res://verify.gd
python tools/art/source/alcatraz_foam_424/verify_assets.py
flock /home/deck/gs66-render.lock blender --background --python /绝对路径/tools/art/source/alcatraz_foam_424/verify_source.py
flock /home/deck/gs66-render.lock godot --path output/alcatraz-foam-424/project --rendering-method mobile --rendering-driver vulkan
python tools/art/source/alcatraz_foam_424/package_review.py
```

首次导入后把QA内对应六个 `.glb.import` 与PNG `.import` 复制回交付资产目录，保留自动UID。后续prepare复用这些sidecar。接入说明、参数、截图和测试范围见 [设计记录](../../../../docs/design/alcatraz-foam-424/README.md)。

Android：把准备好的project复制到独立 `android-project`，复制 `android_review.gd` / `prepare_android.gd`，运行后者并导出 `Android Alcatraz Foam QA`。包名只用 `com.sensen.alcatrazfoam424qa`；私有ADB5071、已验证离线模拟器emulator-5592。用仓库 `tools/android/run_test.sh` 执行 `android_smoke.py`，360×800/density160，检查当前PID、六件/107实例/6批次及两次真实缩放按钮。脚本只在本机已核实原显示是720×1280/default density时适用，换设备需先记录；测试结束恢复显示并由runner停止QA app。旧测试指令在新启动时清除，序列单调递增。

`review.gd` 只作为隔离验图工具。宿主海面自带TIME动画，前后比较在人物组装完成后冻结QA时钟；开场相机、海面shader和材质不改。独立展示的30帧稳定性检查正常计时。Android恢复正常计时运行，不使用桌面的冻结时钟流程。
