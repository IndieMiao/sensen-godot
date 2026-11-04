# SGODOT-417 七种「采过」源文件

【黄忠】Plane `5281cd25-6a49-4df8-9802-f3e534956e80`。
按 417 `e4c7afdd` 定稿方向与 410 `924d6611` 换件接口制作。参考原件为主线 `4d662915`。

七个 `<名字>_gathered.blend` 保留各自独立命名部件；`build.py` 可重建源及单 mesh / surface GLB。
每件保留原资源点原点，不按新包围盒重新居中，不用站位坐标做原点。
运行时仅由程序切换原件与采过件的 visible，名字条、点击区、站位不随模型变化。

`original_metrics.json` 是 Godot 直接实例化原模型 / 旧拼法后量得的顶点包围盒，包含缩放与旋转。
树林、石堆、香草调用原附件；其余四件直接读主线 GLB。规格不从设定图估尺寸。
`asset_stats.json` 包含新件真实 bounds、原点、复用来源、源部件预算和可见地块的实际顶点。
这些顶点用于跟随镜头的像素测量，不用大树冠、零散小芽或人为留白扩宽。

四种植物统一用同一个新芽：两个椭圆叶片、细茎、#8FA46B，单位比例。树林 / 芦苇 / 硬木 / 亚麻各 2 棵。
石堆、黏土不加芽；香草保留浅色底和半宽以上的剪矮叶簇。
湿泥、浅褐土、坑沿、小胡桃桩直接加载原 Blender 命名部件，保留其几何和世界局部坐标。
黏土使用 v1.1 红褐暗部 #9D674B，薄层顶面采用平整法线，原木铲只做刚性旋转后平放。

## 重建

在仓库根目录使用已验证工具链，私有 ADB 5097：

```bash
source ~/.codex-huangzhong/env.sh
blender --background --factory-startup --threads 3 --python-exit-code 1 --python "$PWD/tools/art/source/gathered_417/build.py"
python3 tools/art/source/gathered_417/prepare_review.py
SENSEN_OFFLINE=1 godot --headless --path output/gathered-417/project --editor --import > output/gathered-417/import.log 2>&1
SENSEN_OFFLINE=1 godot --headless --path output/gathered-417/project --script res://configure_imports.gd -- "$PWD"
output/art-setup/venv/bin/python tools/art/source/gathered_417/verify.py
blender --background --threads 3 --python-exit-code 1 --python "$PWD/tools/art/source/gathered_417/verify_source.py"
nvidia-smi
SENSEN_OFFLINE=1 godot --path output/gathered-417/project --rendering-method mobile --rendering-driver vulkan > output/gathered-417/render.log 2>&1
output/art-setup/venv/bin/python tools/art/source/gathered_417/package_review.py
```

首次生成 .import 时不写 UID；**UID 由 Godot 导入生成**，configure 只回收、校验 `[a-y0-8]` 和唯一性。
重建已有资产保留现有 UID。所有参数照 sign：tangents / LOD 开、light_baking=1、texture_map_mode=1。
每件一个 `<名字>_gathered_mobile` mesh，一整件合并成一个 surface，线性顶点色、哑光 .9。

如需重新量原件，先 prepare / import，再运行：

```bash
SENSEN_OFFLINE=1 godot --headless --path output/gathered-417/project --script res://measure_originals.gd -- "$PWD/tools/art/source/gathered_417/original_metrics.json"
```

只重建指定件可在 Blender 命令最后加 `-- clay_pit` 等基本名。生成器会覆盖该源文件，不保留未写回脚本的手工改动。

## 审阅边界

审阅工程固定 b1 `67116c6d`，独立账号目录、阻断会话请求。原生 P0 Pond、人物、灯光、跟随镜头和 UI。
原件 / 采过件同时以原尺寸出现在同帧；跟随图为完整 360×800、zoom 1、43°，未拉近。
冷却用离线 fixture：完整冷却 4 小时，示例剩余 3h 12m，调用原生 `P0Ui.name_bar(..., dimmed=true)`；
模型仅 visible 切换，锚点 / 点击坐标 / stand 在切换前后核对一致，不表示 410 功能已经接入。

按已定「高件不挡资源槽」规则，在隔离 PondScenery 临时避让 L1/L2 的装饰树与槽附近草丛，
保留原导航、出生点、相机及水体；实际模块文件未提交。临时树干排除圈 3 m 含树冠余量，矮装饰排除圈 1.5 m。
此处是模型审阅布局，正式场景避让和冷却由 410 接入。每次渲染前查看显卡，脚本拍完自行退出。
