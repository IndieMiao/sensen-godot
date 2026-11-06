> 最新交付见 [v1.1 四项返修](v1.1/README.md)。以下保留 v1 审阅记录。

# SGODOT-435 · 通用海岸植被 v1

【赵云】新分支 `wp-3d-scene-zhaoyun-coast-plants`，基于最新主线 `7214c718`。交 2 种海滨草、2 块冰花地被、2 种矮灌木、风斜蒙特雷柏和扇叶棕榈，两种树各带 40 m 远档。只新增 coast_plants、对应源文件和审阅材料，既有资源全部保留。

10 个 GLB 共 **2,402 三角面**。草 / 地被 / 灌木 156–392 面；柏树近 / 远 **372 / 118** 面，棕榈近 / 远 **316 / 120** 面。全部一个 Mesh / surface、实体背面、完全不透明哑光顶点色。生成器保留命名部件，Blender 源可逐件编辑。件表、尺寸和接入说明见 [套件 README](../../../assets/landmarks/_shared/coast_plants/README.md)。

## 审阅图

- [件表加人](SGODOT-435_COAST_PLANTS_v1_catalog.png)：10 件全部出现，每格带 1.75 m 游戏人物，小件 / 树分区取景；同对树近远档同尺度。
- [360×800 默认镜头](SGODOT-435_COAST_PLANTS_v1_default_360x800.png)：43° / yaw 14.5° / 6.72 m，冷灰褐岸石；宽 12 m 示例的中段按游戏视宽取景。
- [12 m 岸线全景](SGODOT-435_COAST_PLANTS_v1_overview_warm.png)：暖沙岸石，同一批植被，补看默认镜头画外的整段组合。
- [39 / 41 m 切档](SGODOT-435_COAST_PLANTS_v1_lod_39_41.png)：由 Godot `visibility_range` 自动切换，非手动隐藏两档。

所有图来自 Godot 4.7.2 Vulkan Mobile / RTX 2060；PNG 仅拼版、署名和标注，未调色或缩放模型。件表为排版统一缩放图片，原米制尺度通过人物保留。长边均 ≤1600 px。

## 组合与资源来源

隔离审阅工程中，用 6 个 2 m 岸石段组成 12 m 岸线，地面 Y=0.65、水位 Y=0.20、浪花 Y=0.218。地被 / 草丛 / 灌木按六种原型使用 MultiMesh，共 22 个实例，另放柏树、棕榈各一棵。玩家站位与中央空地留空。

- 426：主线 `7214c718` 中的海岸套件 v1.2；只在审阅实例材质上设置水位和暖 / 冷色板参数。
- 430：主线同头的 `water_edge` 原 GLB、shader、材质与贴图，关闭浪花投影，保持单层。
- 432：#837 / `15b0012ee4cb64eaaa07c6637a3d2ea76cafde4c` 的 `sea_backdrop/bay.tres`，原预设分配给单层水面，未改参数和源文件。该未合入分支只临时提取到 output 审阅工程。

完整借用资源 SHA 见 [reference-resources.json](reference-resources.json)。本 PR 不复制这些资源到运行时，也不交示例场景 / layout。

## 验证

- [几何与导入](asset-validation.json)：**165 项通过**，核对 10 GLB 的实际面数 / 单 surface / `_mobile` 名称、原点、闭合边、正向法线、顶点色、两对同包围盒、UID 与完整导入设置。
- [场景实渲](render-validation.json)：**72 项通过**，核对实际渲染 GLB SHA、原导入材质、1.75 m 游戏角色、六类 MultiMesh、426 / 430 / 432 与 12 m 示例。
- [LOD 实渲](lod-validation.json)：**75 项通过**，覆盖边界两侧和四个方位。Godot 实际 primitive / draw 记录证明各距离只画对应档位。
- [切档图像量测](lod-image-metrics.json)：43° 同取景下，柏树四方位轮廓 IoU 0.907–0.930，棕榈 0.935–0.951；共同覆盖区 RGB 平均差约 7.0–10.3 /255。这些是这组截图的量测，画面是否通过交由验收。

Godot 导入脚本把共享哑光顶点色材质绑到 Mesh surface，MultiMesh 取网格仍保留；10 个 `.import` 都有 Godot 生成的 uid、`nodes/root_script=null` 和 `texture_map_mode=1`。提交后再清缓存冷导入 / 同步，确认工作区干净，具体新头和结果写在 PR / 435 交付评论。

所有 Blender / Godot（含 headless 导入）均用 `flock ~/gs66-render.lock`，私有 ADB 5099，用完退出。本轮是桌面目标渲染器与资产验证，不是物理手机性能结果。

## 复现

```bash
source ~/.codex-zhaoyun/env.sh
nvidia-smi
flock ~/gs66-render.lock blender --background --python-exit-code 1 --python tools/art/build_coast_plants_435.py
python3 tools/art/source/coast_plants_435/imports.py stage
# 首次使用空导入工程时，先让 Godot 生成导入文件与 UID。
flock ~/gs66-render.lock godot --headless --path output/coast-plants/import-project --import
python3 tools/art/source/coast_plants_435/imports.py configure
flock ~/gs66-render.lock godot --headless --path output/coast-plants/import-project --import
python3 tools/art/source/coast_plants_435/imports.py sync
python3 tools/art/source/coast_plants_435/verify.py
```

几何检查需要 NumPy；打包审阅图需要 Pillow。提交后执行 `stage → cold → Godot --import → sync → git status --short`。LOD 验证脚本是独立审阅 Node，可在隔离工程用临时 `.tscn` 挂载；不注册进游戏。生成器复用仓库已有的通用几何与 LOD 导出函数，未改它们的文件。
