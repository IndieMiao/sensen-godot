# SGODOT-424 · 刘备 · 岸石与坡地植被源文件

Blender 5.2.2 LTS / Godot 4.7.2。交接及验收图见 [设计记录](../../../../docs/design/alcatraz-nature-424/README.md)。

`alcatraz_nature.blend` 保留六个独立 collection：岩石各一个可编辑网格，灌木分别 7 / 9 个命名叶团，草丛 6 片折叶。各 collection 都在原点；编辑时隔离所需 collection。运行时按 collection 合并为单网格、单 surface；不把整座岛合并进去。

坐标以 Godot 米制、Y 向上、+Z 向南为准，Blender 映射 `(x,-z,y)`。每件原点在底面/水平包围盒中心。顶点色为线性 COLOR_0；无贴图。`alc_nature_material.tres` 负责 Godot 的顶点色启用与哑光参数，每个 `.glb.import` 绑定它。

参考原件保留在 `reference/`，来源为用户指定的 `~/incoming/landmark/`。`blockout_layout.json` 来自马可波罗 #792 的 `34df9c0b6af42a85567dfb5318c6717f929a4ab8`。未见面、背面和单件尺寸是按设定风格作出的制作推定。`provenance.json` 记录文件哈希。

在仓库根目录执行（Blender 脚本须用绝对路径）。隔离预览需要本地已有上述固定白模提交；新克隆可先 `git fetch origin refs/pull/792/head` 获取其历史，`prepare.py` 仍只解包固定的 `34df9c0b`：

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

`build.py` 会覆盖 `.blend` 和六个 GLB；手工改模后先把改动同步到生成脚本或另存源文件。`prepare.py` 只向忽略目录 `output/` 解包已固定的白模版本，不改动主体的 layout、场景和水体。实拍输出在 `output/alcatraz-nature-424/captures/`。首次导入后的 `.import` 必须随对应 GLB 交付。

Android 冒烟另用 `prepare_android.gd` 设置临时项目并导出 `Android Alcatraz Nature QA`。安装包名 `com.sensen.alcatraznature424qa`，只在离线模拟器运行。使用仓库 `tools/android/run_test.sh` 启停；`android_smoke.py` 读取当前进程的原子状态文件、注入真实拖拽/双指缩放/按钮/行走点击并验证反馈。`ADB` 应指向专用端口包装脚本，`JOURNEY_SERIAL` 由 runner 设置，`NATURE_TOUCH_DEX` 指向由 `tools/dev/basic_room/RoomTouch.java` 编译的 dex。该次模拟器显示原值为 720×1280，脚本结束恢复此值；换设备时须先记录并相应调整恢复值。
