# SGODOT-424 · 刘备 · 岸石与坡地植被源文件

Blender 5.2.2 LTS / Godot 4.7.2。交接及验收图见 [设计记录](../../../../docs/design/alcatraz-nature-424/README.md)。

`alcatraz_nature.blend` 保留六个独立 collection：岩石各一个可编辑网格，灌木分别 7 / 9 个命名叶团，草丛 6 片折叶。各 collection 都在原点；编辑时隔离所需 collection。运行时按 collection 合并为单网格、单 surface；不把整座岛合并进去。

坐标以 Godot 米制、Y 向上、+Z 向南为准，Blender 映射 `(x,-z,y)`。每件原点在底面/水平包围盒中心。主灌木名为 `alc_shrub`（首版 `alc_shrub_a` 已改名），第二款为 `alc_shrub_b`。顶点色为线性 COLOR_0；无贴图。`alc_nature_material.tres` 负责 Godot 的顶点色启用与哑光参数，每个 `.glb.import` 绑定它。

参考原件保留在 `reference/`，来源为用户指定的 `~/incoming/landmark/`。`blockout_layout.json` 来自马可波罗 #792 的 `b16c31982f34a64cdd4f9c6683064edbf20837a0`。未见面、背面和单件尺寸是按设定风格作出的制作推定。`provenance.json` 记录文件哈希。

在仓库根目录执行（Blender 脚本须用绝对路径）。隔离预览需要本地已有上述固定白模提交；新克隆可先 `git fetch origin refs/pull/792/head` 获取其历史，`prepare.py` 仍只解包固定的 `b16c3198`：

```sh
flock /home/deck/gs66-render.lock blender --background --python /绝对路径/tools/art/source/alcatraz_nature_424/build.py
python tools/art/source/alcatraz_nature_424/placements.py
python tools/art/source/alcatraz_nature_424/verify_assets.py
flock /home/deck/gs66-render.lock blender --background --python /绝对路径/tools/art/source/alcatraz_nature_424/verify_source.py
python tools/art/source/alcatraz_nature_424/prepare.py
flock /home/deck/gs66-render.lock godot --headless --editor --path output/alcatraz-nature-424/project --import
flock /home/deck/gs66-render.lock godot --headless --path output/alcatraz-nature-424/project --script res://configure_imports.gd
flock /home/deck/gs66-render.lock godot --headless --editor --path output/alcatraz-nature-424/project --import
flock /home/deck/gs66-render.lock godot --headless --path output/alcatraz-nature-424/project --script res://verify.gd
flock /home/deck/gs66-render.lock godot --path output/alcatraz-nature-424/project --rendering-method mobile --rendering-driver vulkan
```

`build.py` 会覆盖 `.blend` 和六个 GLB；手工改模后先把改动同步到生成脚本或另存源文件。`prepare.py` 只向忽略目录 `output/` 解包已固定的白模版本，不改动主体的 layout、场景和水体。`placements.py` 从固定布局提取 114 个刘备占位，以 `source_name` 一对一替换；v3 把 c_003 换小号 a、X 改为 -27；a_004 移至 (-29.2,-.35,8.5)，让原开场左上桥与城市带无岩石；其余为植物根部贴地及灌木款式分配，不追加旧版179点。`verify_placement_support.py` 需要 NumPy，检查实际地形三角面与78个植物根点。

实拍输出在 `output/alcatraz-nature-424/captures/`。首次导入后的 `.import` 必须随对应 GLB 交付。

Android v3 用 `prepare.py` 生成项目后另复制到 `output/alcatraz-nature-424/android-project-v3`，运行 `prepare_android.gd` 并导出 `Android Alcatraz Nature QA`。只安装到离线模拟器的 `com.sensen.alcatraznature424qa`。私有 ADB 包装脚本配合仓库 `tools/android/run_test.sh` 调用 `android_smoke_v3.py`：360×800 / density160，核对当前进程六件、114实例、9批次、完整人物及两次真实缩放按钮。测试后恢复本机已核实的720×1280覆盖/default density并停止QA app。换设备需先记录当前值。首版34df9c0b的双指失败保留在历史记录，v3不声称完成双指或全导航。

2026-11-06 v3：三款岸石为 196 三角面，截肩块状轮廓、两条凹裂带、12% 平滑法线；色板 stone=777A75 / light=93958B / shade=515B59。三件植物 GLB 与 v2 字节一致。`android_review.gd` 已更新为 v3；当前轻量检查用 `android_smoke_v3.py`，旧 `android_smoke.py` 为首版历史失败复现，不用于本轮验收。
