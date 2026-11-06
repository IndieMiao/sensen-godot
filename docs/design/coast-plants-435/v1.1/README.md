# SGODOT-435 · 海岸植被 v1.1

【赵云】按上官婉儿 `2622ac79` 的两条，以及不知火舞随后在 435 补充的 `d5d1392f` 两条，一并修改棕榈、冰花、柏树和灰绿灌木。分支仍为 `wp-3d-scene-zhaoyun-coast-plants`，PR #841。

| 返修项 | v1.1 实现 | 三角面 |
|---|---|---:|
| 棕榈 | 从顶上放射 8 片窄长叶，向上拱起后下垂 0.95–1.55 m；树干底部直径由 0.32 m 收到 0.22 m，近档加 6 道窄环纹；近远档同步 | 近 752 / 远 120 |
| 冰花 a / b | 连续柔边绿垫，加密短肉叶和粉紫花；a 为 26 片叶 / 7 朵花，b 为 21 片叶 / 9 朵花；可重叠拼成地毯 | 各 394 |
| 蒙特雷柏 | 四层向 +X 风向伸出的成对云团，从下到上缩短；加大弯干、深灰绿配色，高度保持 5.8 m，近远同步 | 近 692 / 远 118 |
| 灰绿灌木 | 配色改为 #75976C / #94B18A / #587D50，偏绿并保留灰调；几何不变 | 156 |

全套 **10 GLB / 3,218 三角面**，全部单 mesh / surface、哑光顶点色、无纹理。海滨草 a / b 和黄绿灌木 b 三个 GLB 保持 `a590b559` 字节。共享材质、导入脚本和 10 份 `.import` 保持原字节；未修改本套件之外的运行时文件。

## 审阅图

- [catalog](SGODOT-435_COAST_PLANTS_v1.1_catalog.png)：全件表加 1.75 m 游戏人物，近远档同尺度；下方加冰花六块拼接和厚叶 / 小花近景。
- [default_360x800](SGODOT-435_COAST_PLANTS_v1.1_default_360x800.png)：原 43° / yaw 14.5° / 6.72 m 取景，426 冷灰岸石 + 430 浪花 + 432 海湾原预设。审阅示例将棕榈向内收 1.2 m，冰花后退到完整地面上，便于看新叶形、避免底垫压进岸石；相机与模型比例未变。示例仍只在 output，不交 layout 或游戏场景。

图为 Godot 4.7.2 Vulkan Mobile / RTX 2060 实渲，仅拼版与署名，无后期调色；长边 ≤1600 px。

## 规格与接入

冰花 a 约 1.00 × 0.76 m、b 约 1.40 × 1.03 m，高均约 0.181 m。连续铺设建议小块 X/Z 间距 0.82/0.62 m，大块 1.18/0.84 m；少量重叠、交替转向，使绿垫相接。保留脚底中心原点，根部放在地面上；不复制网格，按原型用 MultiMesh 批次铺设。

棕榈近远档高约 5.65 m，柏树近远档高 5.8 m；每对的节点原点和完整 AABB 相同。40 m 使用 `visibility_range` 切换，无交叉淡化 pass。棕榈远档保留 8 片叶的弧形与下垂，省略六道细窄树干环纹；近远细节差异可在 catalog 中直接比较。具体设置见 [套件 README](../../../../assets/landmarks/_shared/coast_plants/README.md)。

## 验证

- [几何 / 导入](asset-validation.json)：**217 项通过**。实际网格验证连续垫层、叶片和花朵数量、中部 221 点完整覆盖；8 个方向的棕榈下垂叶、细干尺寸和 6 道环纹；柏树四层云团逐层缩短与弯干；灰绿灌木只改顶点色，POSITION / NORMAL / indices 不变；3 个通过件及全部导入文件保留。
- [场景实渲](render-validation.json)：**74 项通过**。实际 GLB SHA、原导入材质、MultiMesh、示例资源、人物、两张新近景和默认取景均核对。
- [LOD 实渲](lod-validation.json)：**75 项通过**。39 / 41 m、39.95 / 40.05 m，以及 14.5° / 60° / 150° / 240° 方位均只绘制正确档位，没有重叠绘制；报告 SHA 与本版树一致。
- [图像量测](lod-image-metrics.json)：同一 43° 取景下四方位轮廓 IoU，柏树 0.914–0.924，棕榈 0.849–0.867；棕榈远档的弧线和折面更简化。这是该组截图量测，画面验收由上官婉儿与不知火舞判断。

10 份 `.import` 的 uid、`nodes/root_script=null`、`texture_map_mode=1` 保留。提交后再清缓存冷导入、同步并确认 `git status --short` 干净，新头与结果写在交付评论。所有 Blender / Godot 调用均在 `flock ~/gs66-render.lock` 下，ADB 私有 5099，用完退出。

可编辑 [Blender 源](../../../../tools/art/source/coast_plants_435/coast_plants.blend)、[生成器](../../../../tools/art/build_coast_plants_435.py)、[几何检查](../../../../tools/art/source/coast_plants_435/verify.py)已同步。资源来源沿用 v1，见 [reference-resources.json](reference-resources.json)。桌面实渲不代表物理手机性能结果。
