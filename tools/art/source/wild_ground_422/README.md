# 野外地表 SGODOT-422 · 可编辑源

设计和参数说明见 [交接文档](../../../../docs/design/wild-ground-422/README.md)。
`reference/` 保存上官婉儿提供的两张图、槽位 v2、原审阅 mock；`p0_pond_templates.json` 是固定游戏快照 `67116c6df4f69062ce658c50581e72ab1779a1b4` 的原数据。
草地贴图是确定性原创栅格绘制，未使用照片或 AI 图片生成；参考图只作为画面方向，不当地面纹理采样。

`build.py` 保留大色块域、草叶笔触、路径曲线、土斑位置、边界留白、石子点位及 palette。重新运行会覆盖本任务四张贴图和 manifest。输入坐标是 Godot 米制 XZ，无 Blender 坐标变换。仅平面贴图，无需要提交的 Blender 模型。

工具：Python 3.13、Pillow 11.3.0、NumPy 2.3.3、SciPy 1.16.2、Godot 4.7.2。复用已有环境或新建隔离 venv；本机是 `output/wild-ground-422/venv/bin/python`。

```sh
output/wild-ground-422/venv/bin/python tools/art/source/wild_ground_422/build.py
# 若此只读快照不在本地对象库，先 git fetch origin 67116c6df4f69062ce658c50581e72ab1779a1b4
python3 tools/art/source/wild_ground_422/prepare_review.py
SENSEN_OFFLINE=1 godot --headless --path output/wild-ground-422/project --editor --import
SENSEN_OFFLINE=1 godot --headless --path output/wild-ground-422/project --script res://configure_imports.gd
SENSEN_OFFLINE=1 godot --headless --path output/wild-ground-422/project --editor --import
SENSEN_OFFLINE=1 godot --headless --path output/wild-ground-422/project --script res://verify_maps.gd
SENSEN_OFFLINE=1 godot --path output/wild-ground-422/project --rendering-method mobile --rendering-driver vulkan
output/wild-ground-422/venv/bin/python tools/art/source/wild_ground_422/package_review.py
```

第一次生成 .import 后将输出工程的四份 sidecar 复制回 `assets/ponds/ground/`；后续复现保留现有 UID，不重新编造。
运行实渲时需要本机有效 DISPLAY / XAUTHORITY；截图由 SubViewport 以精确 360×800 生成，不受 Steam Deck 窗口高度限制。审阅脚本会自行拍完退出。
`prepare_review.py` 只改 `output/` 内副本；原生开场/灯光/HUD/资源摆位在前后保持一致，只替换地面材质。水/树/草动态时刻固定用于 A/B，原版运行时 shader 不改。

Android 可选复现（仍须先完成上述 staging/import）：

```sh
SENSEN_OFFLINE=1 godot --headless --path output/wild-ground-422/project --script res://prepare_android.gd
SENSEN_OFFLINE=1 godot --headless --path output/wild-ground-422/project --export-debug 'Android Wild Ground QA' ../wild-ground-422.apk
```

使用自己的私有 ADB 端口和隔离模拟器；Godot `export/android/shutdown_adb_on_exit=false`。安装后必须通过 `tools/android/run_test.sh` 启停测试包；读取 `files/ground_state.json` 观察实际触摸后的站位和缩放。测试结束还原临时显示设置、清除本任务触摸 fixture，保留模拟器和既有数据。
`prepare_android.gd` 会把临时 override 写进**输出副本**的 project.godot，确保导出 APK 使用正确离线入口。之后重新运行 `prepare_review.py` 即回到桌面审阅配置。
