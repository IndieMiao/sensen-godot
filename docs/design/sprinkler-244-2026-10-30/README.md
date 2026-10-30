# SGODOT-244 洒水器 v1.1

黄忠制作，2026-10-30。依据上官婉儿规格 v1.1、设定图 v1 和不知火舞 `a10515ef` / `5dc06847` 意见。尺寸以文字规格为准，设定图只约束造型、配色方向。交上官婉儿技术检查、不知火舞按游戏渲染验收；草稿 PR 目标 `wp-3d-scene`，进主线前仍须用户批准。

本轮按上官婉儿 `eb53c35e` / PR #566 比例反馈：立杆下段 Ø0.11 m、上段 Ø0.10 m，黄铜轮毂 Ø0.14 m × 高 0.07 m，喷臂 Ø0.04 m，顶帽 Ø0.10 m；石垫缩到 Ø0.25 m，用 16 个径向分段、6 层圆边轮廓。喷嘴按本轮约 Ø0.05 m 的数值目标做成 Ø0.052 m；原 v1 实测为 Ø0.064 m，本项没有称作放大。总高、HEAD、配色、材质和镜头均保留。本轮仅重出默认 43°、最远缩放、正俯视三张审阅图，旧 v1 图片完整保留作历史对照。

## 资产

`assets/farm/art/sprinkler.glb`：778 三角形，两个 mesh / 两个 surface，共用一个不透明顶点色材质，无贴图、UV、描边或发光。低面圆润石垫和鼠尾草绿立杆，偏黄黄铜喷头、两条先下弯再上翘的短臂、圆头喷嘴、蓝色水滴顶帽。喷嘴中心只有共面顶点色深色圆点，没有钻孔、凹陷或独立小零件。

| 项目 | 实测 |
| --- | --- |
| 整体 X × Y × Z | 0.390614 × 0.647000 × 0.250000 m |
| 床面以上总高 | 0.647000 m |
| 喷头绕轴旋转外径 | 0.390830 m |
| 石垫直径 | 0.250000 m |
| 立杆下段 / 上段直径 | 0.110000 / 0.100000 m |
| 轮毂直径 / 高 | 0.140000 / 0.070000 m |
| 喷臂截面直径 | 0.040000 m |
| 喷嘴直径 | 0.052000 m |
| 水滴顶帽直径 | 0.100000 m |
| 距本田边缘最小余量 | 0.274585 m |
| base / head | 264 / 514 三角形，各 1 surface |
| head_pivot / spray_origin | (0, 0.55, 0) m |

轴心为床面中心，Y 向上、+Z 朝前、单位比例；放置根节点到 `BED_H=0.15 m`。实际田块外缘 0.94 m 见方，中心距 1.30 m。土屑最高顶点约 0.155 m，不把土屑高度当床面锚点改动。

源文件：`tools/art/source/sprinkler_244/sprinkler_244.blend`，8 个具名结构件按 base/head 集合组织，保存正确局部轴心。生成脚本 `tools/art/build_sprinkler.py` 复用 294 温室几何与顶点色工具，单独重建洒水器；manifest 仅新增 `sprinkler` 条目。原件、其他 manifest 条目和玩法代码均未修改。

## 给程序

- GLB mesh 节点为 `base`、`head`，mesh 资源名为 `sprinkler_base_mobile`、`sprinkler_head_mobile`；空节点 `spray_origin` 在喷头中心。
- 实例化整个 PackedScene，给两个 mesh 绑定同一 `FarmArt.material()`。不能调用只支持单 mesh 的 `FarmArt.mesh_for("sprinkler")`。Godot 导入后给 mesh 资源名追加文件名前缀，节点名仍原样保留。
- `base` 不动，`head` 自身局部原点为 `(0,0.55,0)`；直接改 `head.rotation.y`，不要重设整体模型原点。`spray_origin` 是同根的固定空节点，位于旋转轴线上。
- 平时不转，只在浇水或点开时旋转 2–3 秒，由程序接入实现。本 PR 没有替换 `_sprinkler_art`、水花、点击判定或玩法逻辑。

## 配色核对

立杆主色 `#A6B397`，比实际作物叶色更浅、更灰。喷头主色 `#E8CE5B`，色相 48.94°，保持偏黄；顶帽 `#8CC7F2` 色相 205.29°，与 `COVER_TINT(0.55,0.78,0.95)` 的 205.50° 接近。每部分用 2–3 个平涂顶点色，材质 roughness=0.9，复用原 FarmArt 材质。

**实物与派活措辞有一处差异**：`plot.glb` 实际为圆角土畦，生成源 `build_farm_assets.py` 标为 `Soft earthen bed / Topsoil`，没有木框。两分支 plot 文件一致。对比图如实显示其田沿土色 `#96764F`，并另外采样真实 `storage.glb` 木色 `#CBA067`；未给田块添加虚构木框。黄铜与实测木色的色相差为 14.74°。所有色块均通过游戏材质和同一光照渲染，标签记录源 sRGB，不把渲染像素当作未受光照影响的色值。

## 审阅与验证

所有交付图来自 Godot 4.7.2 / Vulkan Mobile / RTX 2060 的独立离线场景，使用真实 plot.glb、FarmArt 材质和游戏作物网格。农场摄像机、光照与设施常量核对 `farm-dev f4bb293b`；工作分支基于 `wp-3d-scene fadcaa19`。代码证据哈希记录在 validation。

- 默认图：43° 俯角、14.5° 偏航，360 × 800 下视宽 6.72 m，洒水器投影高约 29.6 px；本轮镜头与 v1 完全一致。
- 最远缩放图：实际缩放下限 0.8，视宽 8.40 m，投影高约 23.7 px，未改镜头或整体缩放。小尺寸辨识度交不知火舞判断。
- 周围 8 株使用现有萝卜、生菜、胡萝卜、香草网格第 1 阶段，复用游戏缩放/阶段色公式；实际床面以上 0.406–0.435 m。
- 人物使用 Basic Room 默认装扮，测量当前姿态高 1.718339 m，等比校准到 1.745 m，并按实际脚底落地。
- 正俯视图保留完整九田，框线表示中央田块实际 XZ 包围盒；0° / 45° / 90° 旋转轴心检查继续运行，本轮不重出旋转图或配色图。
- 66 项独立 GLB 检查、47 项 Godot 检查、13 项源文件检查和 1 项实际像素遮挡检查通过，共 127 项。另做重建字节一致性验证。后方生菜的白色隔离轮廓在有/无黑色洒水器对照中无像素被遮住，此结果仅对应记录镜头和作物阶段。
- Blender 源与导出件双向顶点误差最大约 0.000000015 m。源父级位移问题在首轮发现后已修复；首轮顶帽外形已改清水滴尖端，交付图全部使用最终版本。

本轮不做 Android 输入、真机性能、全农场玩法或用户验收结论。所有启动的 Godot 使用私有 ADB 端口 5097，渲染前检查 GPU，结束正常退出。

本轮文件前缀 `SGODOT-244_SPRINKLER_v1_1_`：默认 360 图、俯视图、最远缩放图、尺寸 Markdown / CSV、validation JSON；media-manifest 记录尺寸与哈希。审阅图均署黄忠，传 Plane 244 后下载回读核对。原 `v1_` 图片及验证文件保留作旧版记录，其中旋转图和配色图不代表 v1.1 的几何。

## 复现

需要 Blender 5.2.2、Godot 4.7.2、Python NumPy / Pillow，以及仓库中的指定 farm-dev 提交。准备脚本只把所需依赖复制进 `output/sprinkler-244/project`，没有原游戏自动加载、网络或玩家存档。保留 `output/.gdignore` 和 `tools/art/source/.gdignore`。

```bash
source ~/.codex-huangzhong/env.sh
blender --background --factory-startup --threads 2 --python "$PWD/tools/art/build_sprinkler.py"
output/art-setup/venv/bin/python tools/art/verify_sprinkler.py
python3 tools/art/check_sprinkler_rebuild.py
blender --background --factory-startup --threads 2 --python "$PWD/tools/art/verify_sprinkler_source.py"
python3 tools/art/prepare_sprinkler_review.py
godot --headless --path output/sprinkler-244/project --editor --import --rendering-method mobile
nvidia-smi
godot --path output/sprinkler-244/project --rendering-method mobile --rendering-driver vulkan --max-fps 30 -- --proportion-revision
output/art-setup/venv/bin/python tools/art/package_sprinkler_review.py --proportion-revision
```

生成脚本覆盖本任务生成源；手工修改源后必须同步脚本。设定图和 v1.1 规格原文保存在源目录，不从设定图量尺寸。
