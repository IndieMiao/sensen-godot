# 野外装饰 422 源文件

制作：赵云。`wild_props.blend` 保留 12 个命名 collection 与所有细分部件；在 Blender 检视网格中排开，导出始终恢复为各自底部中心原点。`build_wild_props_422.py` 是确定性几何 / 配色 / 导出生成器，会覆盖源文件；手动改源请同步生成器或另存。

v1.1 的 `wild_trees.blend` 另保留单干松树、单干圆冠树，不覆盖原 12 件源文件。两树用 `build_wild_trees_422.py` 单独生成并向 manifest / asset_stats 追加。全量重建须先跑 12 件生成器，再跑两树生成器；只改树时只运行后者即可。

参考为本目录 `reference/wild_concept_v1.jpg`、`c_wild.png` 及不可更改的 `pond_slots_v2.json`。`density.json` 为程序撒点建议；`scatter.gd` 仅供临时预览，采集资源先放，装饰后过滤。没有修改正式游戏的地面着色器、导航、碰撞或 PondScenery。

从仓库根目录执行，Python 需要 NumPy / Pillow：

```bash
source ~/.codex-zhaoyun/env.sh
flock ~/gs66-render.lock blender --background --python "$PWD/tools/art/build_wild_props_422.py" > output/wild-422/build.log 2>&1
flock ~/gs66-render.lock blender --background --python "$PWD/tools/art/build_wild_trees_422.py" > output/wild-422/tree-build.log 2>&1
python3 tools/art/source/wild_props_422/prepare.py
flock ~/gs66-render.lock godot --headless --path "$PWD/output/wild-422/project" --import > output/wild-422/import.log 2>&1
flock ~/gs66-render.lock godot --headless --path "$PWD/output/wild-422/project" --script configure.gd -- "$PWD" > output/wild-422/configure.log 2>&1
flock ~/gs66-render.lock godot --headless --path "$PWD/output/wild-422/project" --import > output/wild-422/reimport.log 2>&1
python3 tools/art/source/wild_props_422/verify.py
python3 tools/art/source/wild_props_422/audit_water.py
nvidia-smi
flock ~/gs66-render.lock godot --path "$PWD/output/wild-422/project" --rendering-method mobile --rendering-driver vulkan --display-driver x11 --disable-vsync --max-fps 60 --resolution 720x800 --quit-after 1800 res://review.tscn > output/wild-422/render.log 2>&1
python3 tools/art/source/wild_props_422/package_trees.py
```

按顺序等待每一步退出后再执行下一步，不要把导入与拍摄同时排队。共享 RTX 2060 的锁约束适用于所有导入、渲染和实拍，不能跳过。`env.sh` 保留私有 ADB 5099；不用默认 adb，不开编辑器挂机。

`prepare.py` 从固定 b1 `a43500f3` 建隔离工程、独立 user 目录、本地 fixture，阻断网络，并保留原生塘形/灯光/人物/镜头。在该副本中去掉旧随机蓝花/灌木批次，使用本建议撒装饰；原岸边装饰与草地保持，六棵树按下述 v1.1 方法临时替换。与刘备的新地面尚未整合。渲染窗口 720×800，内部审核视口分别为 360×800、1200×1200、1500×1260，均不超过 1600 长边。

v1.1 在审阅脚本中隐藏原六棵装饰树并实例化新树；`perimeter_trees.gd` 核对树冠圆包围、采集 stand、默认投影、根部在可走区外等条件。四树对比另用 1500×900 视口，显示两个新件及原 Timber / Hardwood；这些替换仍只在隔离工程发生，不提交程序接入。水塘材质 / 颜色 / 着色器 / 岸石 / 水贴图不变，整个 pond_ground.gdshader 也不改。`audit_water.py` 对仓库与隔离工程分别作固定提交的逐文件核对。

`verify.py` 直接读 GLB 二进制，核对预算、表面数、无退化面、法线、顶点色、原点、尺寸、独立 UID、旧 manifest 条目不变。`review.gd` 对实际导入的 mesh、三角面、AABB 与导入缓存源 MD5 再核一次，避免旧缓存冒充新模型。原 `package.py` 留作 v1 历史入口（对应提交 c040a643）；当前交付使用 `package_trees.py`。

当前验证器覆盖 14 件，并显式检查原 12 件 GLB / .import 逐字节不变。`package_trees.py` 生成 v1.1 三张补充图和水源保护报告，保留原 v1 图。两个打包器都会拒绝早于当前拍摄脚本的旧报告，必须等渲染任务从共享锁队列执行完并退出后再打包。

原始运行时文件、源文件和审阅结果一起交；不向 b1 提交预览脚本或临时场景修改。
