# SGODOT-426 · 海岸套件 v1.2 · 码头木板统一

【赵云】按上官婉儿补充的 #830 v1.1（刘备，`5f9b59b8`）规格，只修改三种码头的木板分格和木色；其余 12 件 GLB 与 `85967444` 字节相同。v1.1 的双配色、湿带、护岸墙、四角桩和全部旧端口保持。

木板名义尺寸 **1.8 × 0.18 m**，邻行错开 **0.9 m**，板缝宽 **0.012 m**。图案裁切到原 2 × 2 m 甲板内，11 行共 28 块（边缘为裁切板）；含缝名义宽 0.18 m，实木面宽 0.168 m、边行 0.174 m。顶面用同一平面内的顶点色分区，板缝也用顶点色，无贴图、无共面叠片、无新增 pass。每块顶面在底色线性 RGB 上作 ±14% 明暗变化，与 #830 的 `wood_board_tone_strength=0.14` 一致。

| 颜色角色 | sRGB |
|---|---|
| 顶面底色 | #A3815D |
| 窄边条亮色 | #B89972 |
| 侧面 / 支撑暗色 | #795F47 |
| 板缝 | #69543F |

三种码头直段 / 尽头 / 系缆桩分别 **224 / 324 / 368 三角面**（各比 v1.1 少 16 面），均为一个 mesh、一个 surface。整套 **15 件 / 2,604 三角面**，单件最高 368 面。

## 审阅图

- [default_360x800](SGODOT-426_COAST_v1.2_default_360x800.png)：43° / yaw 14.5° / 6.72 m，原场景、人物、灯光与相机，#824 浪花叠用。
- [catalog](SGODOT-426_COAST_v1.2_catalog.png)：完整件表、暖沙 / 冷灰褐两套岩石，以及护岸墙 / 码头近景。
- [木板对照](SGODOT-426_COAST_v1.2_wood_match.png)：左为 #830 原近景，右为码头 43° 实渲；不同场景光照，未后期调色。左图保留其原木纹，右图按本任务使用纯顶点色。

参照图从 `5f9b59b8:assets/landmarks/_shared/ground_detail/review/v1.1/wood-close-review.png` 读取，参数核对同提交的 `ground_wood.tres` 和 `ground_detail.gdshader`，来源 SHA 见 [wood-reference.json](wood-reference.json)。两边统一板长、板宽、错缝、板缝、木色和明暗变化幅度；码头没有复制 #830 的纹理 / shader。

## 验证和接入

[几何验证](asset-validation.json) **361 项通过**：导出顶面覆盖恰好 4 m²、顶面朝上、从实际三角形采样核对板缝和半块错位、基色与 ±14% 线性明暗、15 件面数 / surface / UID、12 件 GLB 字节保留、43 组拼接口最大错位 0。

[Godot 实渲](render-validation.json) **132 项通过**，Godot 4.7.2 Vulkan Mobile / RTX 2060；渲染长边 ≤1600。双色板与湿带 shader / 材质 / 导入脚本本轮没有改，继续引用 v1.1 的 [13 项 GPU 探针](material-validation.json)，四份材质源 SHA 已与当前文件核对；本轮实渲重新验证导入后单 surface、两色同 mesh 与无额外 pass。

15 份 `.import` 的 UID 与 `nodes/root_script=null` 保留；按流程最终导入后同步，提交后再清缓存冷导入并确认工作区干净，结果和新头写在 #831 交付评论。所有 Godot / Blender 操作均使用 `flock ~/gs66-render.lock`，ADB 私有 5099，完成即退出。

运行时修改限 `assets/landmarks/_shared/coast_kit/`，同步本套件 blend、生成 / 验证脚本和审阅文档。恶魔岛和 ground_detail 均未修改；示例不交 layout、不进入游戏。

拼法与材质参数仍见 [套件 README](../../../../assets/landmarks/_shared/coast_kit/README.md)：保留导入到 Mesh surface 的材质，`water_level` 对齐世界水面 Y。可编辑源及复现步骤见 [v1.1 README](../v1.1/README.md#复现)，最新生成器导出本版三种码头。
