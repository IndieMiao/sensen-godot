# SGODOT-424 · 刘备 · 可选台地与步道细节 v1

为原先平涂顶点色的地面补三档草色、细草、浅色铺石缝和顺板木纹。**这是可选材质包，没有自动套入场景；是否采用由马可波罗和不知火舞决定。**

基准是马可波罗 #792 `bf0c31b1c871011008b455434d167224d14de59c`，包括同头的 `tools/art/source/alcatraz_island/palette.json`。已在 SGODOT-424 评论 `6b9e7e68-bf73-4dfa-ac8d-7e3f40368004` @ 马可波罗对接。实际参考为 `~/incoming/landmark/c_alc2.png` 与 `landmark_alcatraz_v2.jpg`，原始图已在仓库泡沫件的 reference 中留存。本包颜色直接对应马可波罗色板，不采样照片。

## 套用与撤回

全部运行资源在 `assets/landmarks/alcatraz_island/ground/`。在马可波罗 `_add_asset()` 中创建节点时，可按 `p.asset` 选择下面的 `material_override`；只改这四个节点的材质。**马可波罗现有 `material_override=paint` 会盖过 surface material，不能只改 surface override。** 本 PR 不修改那段马可波罗代码。

| 原型 | 可选材质 |
|---|---|
| alc_ground_dock / alc_ground_terraces / alc_ground_summit | alc_terrain_detail.tres |
| dock | alc_dock_detail.tres |

```gdscript
# 由马可波罗决定是否接入；这里是说明示例。
if p.asset in ["alc_ground_dock", "alc_ground_terraces", "alc_ground_summit"]:
    node.material_override = preload("res://assets/landmarks/alcatraz_island/ground/alc_terrain_detail.tres")
elif p.asset == "dock":
    node.material_override = preload("res://assets/landmarks/alcatraz_island/ground/alc_dock_detail.tres")
```

撤回时恢复原来的 `paint`。`strength=0` 可做现场对照：三处开场视角平均 RGB 最大通道差不足 0.018/255，局部至多 2/255（StandardMaterial 与 shader 的渲染舍入差）。完全恢复原 paint 即是原材质。

地形按导入的**线性 COLOR_0** 精确选择 garden / garden_dark / garden_light / road；仅近朝上的表面生效。其余崖石、石墙、土床和竖面保留原色与材质响应。保留原网格和 UV，草地与路面采用世界米制坐标，三层交界处不受 UV 缝影响。木纹采用 dock 局部 XZ，沿 X 横板方向，仅原模型局部 Y≈0 的木板顶面生效，保留 26 块板的几何和真实缝隙；不改桩、桩帽、侧面。

若马可波罗重着色、更改模型局部轴或烘焙模型缩放，需要重新核对选择参数；不要将此材质直接用到海面或其他道具。默认先不套即可。两份材质共享参数资源时，改参数会影响所有使用该材质的节点；单处试色请先 duplicate。

## 色板和参数

草色取 `garden_dark #759448` / `garden #86A84F` / `garden_light #9AB55D`，路色 `road #DFCBA7`；木色沿用原板 `wood #BB8B52` / `wood_light #D0A56C` / `wood_dark #9A7046`。不烘日光、阴影或 AO，不增加法线贴图。

| 参数 | 默认值 | 含义 |
|---|---:|---|
| finish_kind | 0 地形 / 1 木板 | 两份材质的唯一类型差异 |
| strength | 1.0 | 整体强度 |
| palette_tolerance | 0.012 | 线性 RGB 欧氏距离，当前所有选色无重叠 |
| grass_patch_repeat_m | 24 | 另以 38.832m 交换轴采样，权重 80/20，打散大块重复 |
| grass_detail_repeat_m | 2 | 短叶细纹米制平铺 |
| grass_detail_strength | 0.13 | 细草明暗幅度 |
| paving_repeat_m | 4 | 每贴图 4×8 块，单块约 1×0.5m，错缝 |
| paving_joint_strength | 0.16 | 柔和细缝暗化，中心约 12mm 加柔边 |
| paving_tone_strength | 0.10 | 单块轻微明暗差 |
| wood_repeat_m | (3, 1) | 局部 XZ 米制细纹 |
| wood_grain_strength | 0.32 | 顺板细纹幅度 |
| surface_roughness / surface_specular | 0.94 / 0.15 | 与原 paint 相同 |

草地大场中，深→普通的 smoothstep 为 **0.41–0.46**，普通→浅色为 **0.54–0.60**；颜色始终落在马可波罗三档绿色之间。大色块沿当前狭窄草带展开，局部细叶只做低对比纹理；未新增可采集植物或装饰模型。完整机器可读参数与绑定合同：`alc_ground_materials.json`。

## 两张贴图 / 成本

| 1024×1024 RGB 数据贴图 | R | G | B |
|---|---|---|---|
| alc_ground_fields.png | 草地大场 | 短叶细纹 | 预留细矿物颗粒，本版不采样 |
| alc_ground_surfaces.png | 浅铺石缝 | 石块明暗 | 顺板木纹 |

两张均由原创周期场生成；无照片、无外部贴图库。必须作为线性数据采样，**不加 source_color**。Godot 4.7.2 自动生成 UID；启用 mipmaps、VRAM 高质量压缩（BPTC / ASTC）及 shader 各向异性过滤。PNG 共约 2.4MiB；GPU 实际大小以目标设备格式为准。

两份材质共用一个 opaque spatial shader，无 TIME、透明、深度、屏幕采样、新几何或额外 pass。草地每片元 3 次纹理读，铺石 1 次、木纹 1 次，未选中区域 0 次。三张原默认镜头可见 draw/三角数套用前后均相同：开场 **28 / 35,678**，半山 **33 / 50,669**，山顶 **27 / 44,363**（SubViewport visible 计数，不含阴影；不能与马可波罗整窗计数直接相减）。这些是审阅场景的计数，不是手机性能结论。

## 验图与验证

- [开场前后](opening-comparison.png)、[半山前后](mid_hill-comparison.png)、[山顶前后](summit-comparison.png)：每侧原生 360×800。人物落点沿用 layout 的 review_points，镜头宽 6.72m、43°俯角和原光照；只在隔离工具中切材质。
- [草坡 / 铺石近景](grass_paving_detail.png)、[木板近景](dock_grain_detail.png)、[整岛](whole_island.png)。这些为额外工具机位，非开场机位。
- 桌面 Vulkan Mobile / Steam Deck VANGOGH：**36 项检查通过**，六组原材质 / 强度零 / 新材质对照；静态间隔 30 帧零变化。前后拍摄冻结 QA 时钟，马可波罗海面 shader 的原 TIME 动画文件未改。
- **98 项资产 / 保留检查通过**：马可波罗原型、UV、地形、layout、导航、海面、镜头与光照源文件逐字节相同；分类不触及崖石 / 墙 / 土床 / 桩帽，贴图数量 / 尺寸 / UID / 压缩 / mip 配置通过。详见 source-validation.json 和 render-validation.json。
- 开场实际桥和城市区 `x=0..149, y=45..159` RGB 最大差 **0/255**。历史 180px 宽保护框的右端包含岸上草地，因此那一整个旧框并非零差；原始较大框测量也保留在报告中。

Android 验证与范围见同目录 android-smoke.json / android-package-validation.json。正常计时，不复用桌面冻结；独立 QA 包，不涉及玩家存档、生产安装或本轮完整导航验收。接入更新后的整岛时，马可波罗仍需按最终画面决定是否采用。

源和复现入口：`tools/art/source/alcatraz_ground_424/README.md`。此次只交材质、贴图、参数及审阅工具，未修改马可波罗的场景应用逻辑。
