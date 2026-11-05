# 野外装饰 422 源文件

制作：赵云。`wild_props.blend` 保留 12 个命名 collection 与所有细分部件；在 Blender 检视网格中排开，导出始终恢复为各自底部中心原点。`build_wild_props_422.py` 是确定性几何 / 配色 / 导出生成器，会覆盖源文件；手动改源请同步生成器或另存。

参考为本目录 `reference/wild_concept_v1.jpg`、`c_wild.png` 及不可更改的 `pond_slots_v2.json`。`density.json` 为程序撒点建议；`scatter.gd` 仅供临时预览，采集资源先放，装饰后过滤。没有修改正式游戏的地面着色器、导航、碰撞或 PondScenery。

从仓库根目录执行，Python 需要 NumPy / Pillow：

```bash
source ~/.codex-zhaoyun/env.sh
flock ~/gs66-render.lock blender --background --python "$PWD/tools/art/build_wild_props_422.py" > output/wild-422/build.log 2>&1
python3 tools/art/source/wild_props_422/prepare.py
flock ~/gs66-render.lock godot --headless --path "$PWD/output/wild-422/project" --import > output/wild-422/import.log 2>&1
flock ~/gs66-render.lock godot --headless --path "$PWD/output/wild-422/project" --script configure.gd -- "$PWD" > output/wild-422/configure.log 2>&1
flock ~/gs66-render.lock godot --headless --path "$PWD/output/wild-422/project" --import > output/wild-422/reimport.log 2>&1
python3 tools/art/source/wild_props_422/verify.py
nvidia-smi
flock ~/gs66-render.lock godot --path "$PWD/output/wild-422/project" --rendering-method mobile --rendering-driver vulkan --display-driver x11 --disable-vsync --max-fps 60 --resolution 720x800 --quit-after 1800 res://review.tscn > output/wild-422/render.log 2>&1
python3 tools/art/source/wild_props_422/package.py
```

按顺序等待每一步退出后再执行下一步，不要把导入与拍摄同时排队。共享 RTX 2060 的锁约束适用于所有导入、渲染和实拍，不能跳过。`env.sh` 保留私有 ADB 5099；不用默认 adb，不开编辑器挂机。

`prepare.py` 从固定 b1 `a43500f3` 建隔离工程、独立 user 目录、本地 fixture，阻断网络，并保留原生塘形/灯光/人物/镜头。只在该副本中去掉旧随机蓝花/灌木批次，使用本建议撒装饰。原岸边装饰、旧树、草地保持；与刘备的新地面尚未整合。渲染窗口 720×800，内部审核视口分别为 360×800、1200×1200、1500×1260，均不超过 1600 长边。

`verify.py` 直接读 GLB 二进制，核对所有 12 件预算、表面数、无退化面、法线、顶点色、原点、尺寸、独立 UID、旧 manifest 条目不变。`review.gd` 对实际导入的 mesh、三角面、AABB 与导入缓存源 MD5 再核一次，避免旧缓存冒充新模型。`package.py` 校验两份报告和最终文件 SHA 后生成署名图片、验证摘要、实际撒点 JSON。

原始运行时文件、源文件和审阅结果一起交；不向 b1 提交预览脚本或临时场景修改。
