# SGODOT-408 亚麻田 v1

【黄忠】2026-11-04，Plane `5281cd25-6a49-4df8-9802-f3e534956e80`。待上官婉儿技术检查、不知火舞画面验收。

按派活制作细灰绿茎、淡蓝五瓣花和浅褐泥土收边。蓝花直径约 0.184–0.210 m，
12 朵分布在高低不同的茎顶；默认镜头下保留蓝色点簇，区别于棕顶芦苇和圆绿香草。
形态参考派活 `flax.svg.png`，尺寸采用规格范围。

| 项目 | 实测 / 交付 |
|---|---|
| 占地 X × Z | 1.300 × 1.260 m |
| 总高 / Y bounds | 0.686883 m / 0–0.686883 m |
| 原点 / 单位 | 底面中心，Y 上、+Z 前，米，节点单位比例 |
| 三角面 | 894 / 900；土圈 94 + 12 根带花植株 720 + 4 根幼茎 80 |
| Mesh / surface | `flax_patch_mobile` / 1 |
| 材质 | 与 sign.glb 完全相同的 Farm vertex paint；实渲共享 FarmArt.material() |
| 颜色 / 表面 | 线性顶点色；roughness 0.9，无贴图、骨骼、动画 |
| 导入 | 独立 UID；sign 同参数，light_baking=1，texture_map_mode=1 |

运行时文件只有 `flax_patch.glb`、`.glb.import` 和农场 manifest 新增条目。
Blender 源、确定性生成器、旧件对比 fixture 与验图脚本位于 `tools/art/source/flax_408/`。

## 审阅图

- `SGODOT-408_flax_v1_F2_43deg.png`：真实 b1 塘 `pond_san_francisco_01` 开场，
  F2 `(7.9, −1.1)`，原出生点 `(6.125, −1.625)`，43° / 一屏宽 6.72 m。
  保留真实 UI，完整 360×800 截图等比 2 倍展示，图外加说明和署名。
- `SGODOT-408_flax_v1_resource_comparison.png`：树林、芦苇、香草、亚麻同机位并排。
  前三件原样调用派活旧代码、单位比例；均用原材质和塘灯光。
  标签高度指地面以上最高点；香草旧件地下顶点不算可见高度，完整 bounds 见 validation。

在私有 b1 `174bf1a1` 工程中临时修改 PondScenery 放入 F2，未改出生点、导航、镜头或水体。
实际模型投影范围和与切换键 / 主键圆形轮廓的距离记录在 `validation.json`。
UI 使用隔离审阅 fixture；传输由空桩拦截，不读取玩家存档或发出玩法请求。

## 自验与边界

`validation.json` 包含 GLB 实际顶点、预算、颜色空间、材质及导入参数、原 manifest
条目不变，以及 Godot 的实际资源、F2 投影、原始镜头和 renderer 检查。
`media-manifest.json` 记录两张图与自验 JSON 的 SHA-256，供 Plane 上传后回读核验。

Godot 4.7.2 / Vulkan Mobile、RTX 2060 桌面实渲；未做手机性能验收。
运行时接入由程序处理；本分支为美术审阅草稿，不合并。
