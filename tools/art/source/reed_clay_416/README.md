# SGODOT-416 芦苇滩 / 黏土坑 A 款

当前黏土颜色为 v1.1，芦苇仍为通过的 v1。色表见 `clay_palette_v11.json`。
`recolor_clay.py` 的普通 Python 路径只改现有 GLB 的指定 RGB 字节和 manifest 颜色 / SHA；
Blender 路径只改 clay_pit.blend 的四种源材质颜色。木铲、草边和几何不变。

【黄忠】Plane `5281cd25-6a49-4df8-9802-f3e534956e80`。
按上官婉儿派活、不知火舞 `e061cf13` 定的 A / A 制作。
`reference/` 保留所给单张设定、clay.svg、槽位和临时摆件 / 旧件代码。
只以设定图定形状与配色；尺寸来自派活，未从图片量尺寸。

- `reed_bank.blend`：独立命名的 22 片实体尖叶、6 根棕色香蒲及茎、深湿泥、2 颗小卵石。
  叶片采用有厚度的截面和光滑法线，香蒲头全部高出叶顶。芦苇只放 L / R / B 岸边槽，不放 F2。
- `clay_pit.blend`：低草缘、浅坑内壁、光滑的赭色陶土堆和小土瓣、2 块小土砖、细木铲。
  铲柄保留开孔；草缘最高 0.065 m、坑底 0.008 m，以轻微起伏表达浅坑，无需改地形或水着色器。
- `build.py`：确定性重建两个源文件，在临时场景合并导出。每件只有一个 `<件名>_mobile` mesh / surface。
  修改形状须同步生成器；运行会覆盖当前源文件。

单位米，Y 向上、+Z 朝前，原点为底面 / 占地包围盒中心，节点单位比例。
顶点色已转线性；GLB 材质与 `sign.glb` 相同。运行时用 `FarmArt.instance(name, at)`，
共享 FarmArt.material()，roughness 0.9，metallic 0，无贴图 / 骨骼 / 动画。
每个 .import 独立 UID，参数照 sign：tangents / LOD 开，light_baking=1，texture_map_mode=1。

## 重建与验图

在仓库根目录执行；复用已验证工具链，Godot 私有 ADB 5097，不启动手机或模拟器。

```bash
source ~/.codex-huangzhong/env.sh
python3 tools/art/source/reed_clay_416/recolor_clay.py
blender --background --threads 3 --python "$PWD/tools/art/source/reed_clay_416/recolor_clay.py"
python3 tools/art/source/reed_clay_416/prepare_review.py
SENSEN_OFFLINE=1 godot --headless --path output/reed-clay-416/project --editor --import
SENSEN_OFFLINE=1 godot --headless --path output/reed-clay-416/project --script res://configure_imports.gd -- "$PWD"
output/art-setup/venv/bin/python tools/art/source/reed_clay_416/verify.py
output/art-setup/venv/bin/python tools/art/source/reed_clay_416/verify_color_v11.py
blender --background --threads 3 --python "$PWD/tools/art/source/reed_clay_416/verify_source.py"
nvidia-smi
SENSEN_OFFLINE=1 godot --path output/reed-clay-416/project --rendering-method mobile --rendering-driver vulkan > output/reed-clay-416/render-v11.log 2>&1
output/art-setup/venv/bin/python tools/art/source/reed_clay_416/package_review_v11.py
```

先确认 GPU 空闲再渲染；脚本拍完自动退出。所有暂存源、缓存、日志和原始截图在 `output/reed-clay-416/`。
本轮只拍 F2 和七件并排，原始图写入 `captures-v11/`，渲染日志保存为 `render-v11.log`。
需要完整重建黏土时运行 `build.py -- clay_pit`（Blender 的 `--` 后参数），该路径也读取 v1.1 色表。

隔离审阅从 b1 `67116c6d` 导出，采用提供的 `pond_scenery.mock2.gd` 和本地 zz_slots.json 临时替换工厂：
芦苇放 Fern Pond L1 `(-0.3,-6.6)`，人物移到 stand `(0.88,-6.62)`，用原生 p0_recenter / 默认 43°；
黏土放 Willow Pond F2 `(7.6,-1.4)`，保留原开场、出生点和 UI。
这两张游戏截图为原生 360×800；署名在画面外。按模型全部三角形的投影边计算距真实切换键外圈的最近距离。

七件对比沿用塘内灯光 / 地面，树林、石堆、香草由原附件代码构造；亚麻来自 `c0179102`，硬木来自 `aee148bf`，
只读提取到隔离工程，无比较用缩放。对比固定版本和哈希记录在 validation。
L1 实拍中，原场景前景固定树冠遮住部分下方叶丛；截图保留这个实际状态，完整造型见并排图。
所有接入及审阅用改动仅在 output 工程，不提交客户端运行时文件。
