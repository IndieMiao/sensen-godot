# SGODOT-244 洒水器 v1.2

黄忠制作，2026-10-30。依据上官婉儿规格 v1.1、设定图 v1 和不知火舞 `a10515ef` / `5dc06847` 意见。尺寸以文字规格为准，设定图只约束造型、配色方向。交上官婉儿技术检查、不知火舞按游戏渲染验收；草稿 PR 目标 `wp-3d-scene`，进主线前仍须用户批准。

本轮按上官婉儿 [PR #566 最新规格修订](https://github.com/IndieMiao/sensen-godot/pull/566#issuecomment-6520454418)：head 与 spray_origin 从 Y=0.55 m 降到 0.42 m，整件高由 0.647 m 改为 0.517 m；立杆下段 Ø0.13 m、上段 Ø0.11 m。喷头、喷臂、顶帽、石垫保留 v1.1 尺寸。上官婉儿同时更正：v1 立杆实际 Ø0.092 m，先前 0.06–0.07 m 是目测误判；三版对比按真实资产标注。本轮交默认 43°、最远缩放、正俯视及三版 43° 局部对比四张图，旧图完整保留。

入口切换期间按指令本地完成，等待上官婉儿通知后再推送和上传本轮附件；未提前更新远端 PR 或 Plane。

## 资产

`assets/farm/art/sprinkler.glb`：778 三角形，两个 mesh / 两个 surface，共用一个不透明顶点色材质，无贴图、UV、描边或发光。低面圆润石垫和鼠尾草绿立杆，偏黄黄铜喷头、两条先下弯再上翘的短臂、圆头喷嘴、蓝色水滴顶帽。喷嘴中心只有共面顶点色深色圆点，没有钻孔、凹陷或独立小零件。

| 项目 | 实测 |
| --- | --- |
| 整体 X × Y × Z | 0.390614 × 0.517000 × 0.250000 m |
| 床面以上总高 | 0.517000 m |
| 喷头绕轴旋转外径 | 0.390830 m |
| 石垫直径 | 0.250000 m |
| 立杆下段 / 上段直径 | 0.130000 / 0.110000 m |
| 轮毂直径 / 高 | 0.140000 / 0.070000 m |
| 喷臂截面直径 | 0.040000 m |
| 喷嘴直径 | 0.052000 m |
| 水滴顶帽直径 | 0.100000 m |
| 距本田边缘最小余量 | 0.274585 m |
| base / head | 264 / 514 三角形，各 1 surface |
| head_pivot / spray_origin | (0, 0.42, 0) m |

轴心为床面中心，Y 向上、+Z 朝前、单位比例；放置根节点到 `BED_H=0.15 m`。实际田块外缘 0.94 m 见方，中心距 1.30 m。土屑最高顶点约 0.155 m，不把土屑高度当床面锚点改动。

源文件：`tools/art/source/sprinkler_244/sprinkler_244.blend`，8 个具名结构件按 base/head 集合组织，保存正确局部轴心。生成脚本 `tools/art/build_sprinkler.py` 复用 294 温室几何与顶点色工具，单独重建洒水器；manifest 仅新增 `sprinkler` 条目。原件、其他 manifest 条目和玩法代码均未修改。

## 给程序

- GLB mesh 节点为 `base`、`head`，mesh 资源名为 `sprinkler_base_mobile`、`sprinkler_head_mobile`；空节点 `spray_origin` 在喷头中心。
- 实例化整个 PackedScene，给两个 mesh 绑定同一 `FarmArt.material()`。不能调用只支持单 mesh 的 `FarmArt.mesh_for("sprinkler")`。Godot 导入后给 mesh 资源名追加文件名前缀，节点名仍原样保留。
- `base` 不动，`head` 自身局部原点为 `(0,0.42,0)`；直接改 `head.rotation.y`，不要重设整体模型原点。`spray_origin` 是同根的固定空节点，位于旋转轴线上。
- 接入 v1.2 时，程序必须把 `scenes/p0/p0_farm_facilities.gd` 的 `HEAD` 从 `(0,0.55,0)` 同步到 `(0,0.42,0)`。该变更已写 manifest 的 `integration_note`；本美术分支未改玩法代码。
- 平时不转，只在浇水或点开时旋转 2–3 秒，由程序接入实现。本 PR 没有替换 `_sprinkler_art`、水花、点击判定或玩法逻辑。

## 配色核对

立杆主色 `#A6B397`，比实际作物叶色更浅、更灰。喷头主色 `#E8CE5B`，色相 48.94°，保持偏黄；顶帽 `#8CC7F2` 色相 205.29°，与 `COVER_TINT(0.55,0.78,0.95)` 的 205.50° 接近。每部分用 2–3 个平涂顶点色，材质 roughness=0.9，复用原 FarmArt 材质。

**实物与派活措辞有一处差异**：`plot.glb` 实际为圆角土畦，生成源 `build_farm_assets.py` 标为 `Soft earthen bed / Topsoil`，没有木框。两分支 plot 文件一致。对比图如实显示其田沿土色 `#96764F`，并另外采样真实 `storage.glb` 木色 `#CBA067`；未给田块添加虚构木框。黄铜与实测木色的色相差为 14.74°。所有色块均通过游戏材质和同一光照渲染，标签记录源 sRGB，不把渲染像素当作未受光照影响的色值。

## 审阅与验证

所有交付图来自 Godot 4.7.2 / Vulkan Mobile / RTX 2060 的独立离线场景，使用真实 plot.glb、FarmArt 材质和游戏作物网格。农场摄像机、光照与设施常量核对 `farm-dev f4bb293b`；工作分支基于 `wp-3d-scene fadcaa19`。代码证据哈希记录在 validation。

- 默认图：43° 俯角、14.5° 偏航，360 × 800 下视宽 6.72 m，洒水器投影高约 24.5 px；本轮镜头与 v1 完全一致。
- 最远缩放图：实际缩放下限 0.8，视宽 8.40 m，投影高约 19.6 px，未改镜头或整体缩放。小尺寸辨识度交不知火舞判断。
- 周围 8 株使用现有萝卜、生菜、胡萝卜、香草网格第 1 阶段，复用游戏缩放/阶段色公式；实际床面以上 0.406–0.435 m。
- 人物使用 Basic Room 默认装扮，测量当前姿态高 1.718339 m，等比校准到 1.745 m，并按实际脚底落地。
- 正俯视图保留完整九田，框线表示中央田块实际 XZ 包围盒；0° / 45° / 90° 旋转轴心检查继续运行，本轮不重出旋转图或配色图。
- 三版局部图从 `a9f7d142`（v1）、`cf97f40b`（v1.1）和当前 v1.2 GLB 真实重拍，均在同一田块、材质、光照、43° / 14.5°、视宽 1.08 m 下取景，没有逐版缩放或借用旧截图；引用提交和文件哈希写入 validation。
- 72 项独立 GLB 检查、53 项 Godot 检查、13 项源文件检查和 1 项实际像素遮挡检查通过，共 139 项。另做重建字节一致性验证。后方生菜的白色隔离轮廓在有/无黑色洒水器对照中无像素被遮住，此结果仅对应记录镜头和作物阶段。
- v1.1 喷头本地顶点最大分量差约 0.000000060 m，拓扑、颜色、材质保持；浮点重算法线的最大夹角差为 0.00546°，低于 0.02° 检查限。石垫几何保留，只有立杆长度/粗细和喷头节点高度改变。Blender 源与导出件双向顶点误差最大约 0.000000030 m。

本轮不做 Android 输入、真机性能、全农场玩法或用户验收结论。所有启动的 Godot 使用私有 ADB 端口 5097，渲染前检查 GPU，结束正常退出。

本轮文件前缀 `SGODOT-244_SPRINKLER_v1_2_`：默认 360 图、俯视图、最远缩放图、三版局部对比、尺寸 Markdown / CSV、validation JSON；media-manifest 记录尺寸与哈希。审阅图均署黄忠，待通知后上传 Plane 244 并回读校验。原 `v1_`、`v1_1_` 图片与验证记录保持原样，不代表 v1.2 几何。

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
godot --path output/sprinkler-244/project --rendering-method mobile --rendering-driver vulkan --max-fps 30 -- --proportion-revision --compare-revisions
output/art-setup/venv/bin/python tools/art/package_sprinkler_review.py --proportion-revision
```

生成脚本覆盖本任务生成源；手工修改源后必须同步脚本。设定图和 v1.1 规格原文保存在源目录，不从设定图量尺寸。
