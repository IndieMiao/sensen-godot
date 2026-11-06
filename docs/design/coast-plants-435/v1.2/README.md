# SGODOT-435 · 海岸植被 v1.2 · 去穗补充

【赵云】本版包含 [v1.1 四项返修](../v1.1/README.md)，再落实上官婉儿最新明确的要求：`coast_grass_a` 不能有穗状小头。

移除原来的 3 个浅色穗头及对应独立穗杆，只保留 18 片叶。该件由 **216 → 144 三角面**，高度约 **0.836 → 0.700 m**；叶片形状、颜色保留。去掉最低的斜穗杆端面后，叶片整体重新贴地约 0.42 mm，XZ 原点与外形不变。生成脚本、Blender 源、件表和统计已同步。

其余 9 个 GLB 与 `a4565284` 字节相同：棕榈 8 片弧形下垂长叶、细干环纹；冰花连续厚垫；柏树四层同向缩短云团、明显弯干、深灰绿；灰绿灌木偏绿。整套 **10 件 / 3,146 三角面**，均单 mesh / surface。材质、导入脚本和全部 10 份 `.import` 保持原字节。

- [catalog](SGODOT-435_COAST_PLANTS_v1.2_catalog.png)：重拍全件表，直立海滨草没有穗头；保留冰花拼接与近景。
- [default_360x800](SGODOT-435_COAST_PLANTS_v1.2_default_360x800.png)：原 43° / yaw 14.5° / 6.72 m 镜头和 v1.1 示例摆位，重新拍摄。

两图来自 Godot 4.7.2 Vulkan Mobile / RTX 2060，已逐张查看。只有拼版和署名，未调色、未缩放模型，长边 ≤1600 px。

[几何 / 导入检查](asset-validation.json) **227 项通过**：实际 144 面、无浅色穗头顶点、保留叶片形状与颜色、其余 9 件字节保留、UID 与单 surface 等。新 [实渲检查](render-validation.json) **74 项通过**。四个树文件未变，继续引用源 SHA 完全匹配的 [75 项 LOD 检查](lod-validation.json)，本轮没有重复跑树的 LOD；[图像量测](lod-image-metrics.json)同样沿用 v1.1 的树。

提交后再冷导入 / 同步，确认 23 份运行时文件哈希稳定、工作区干净；新头和结果写进 #841 / Plane 435 交付评论。所有 Godot / Blender 操作都用 `flock ~/gs66-render.lock`，ADB 私有 5099，完成即退出。

[套件 README](../../../../assets/landmarks/_shared/coast_plants/README.md)提供尺寸、原点、MultiMesh 和 40 m 切档说明。示例仅用于图片，426 / 430 / 432 资源来源见 [reference-resources.json](reference-resources.json)；恶魔岛和其他套件未改。
