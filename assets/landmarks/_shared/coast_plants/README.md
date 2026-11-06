# 通用海岸植被 · SGODOT-435 · v1.2

【赵云】8 种植物、10 个 GLB，配合 426 海岸套件使用。全部一个 `_mobile` Mesh、一个 surface、哑光顶点色；无贴图、骨架、动画、碰撞或游戏注册。整套 **3,146 三角面**，小件 ≤400、树近档 ≤800、远档 ≤120。

## 件表

| GLB 名称 | 三角面 | 高度 m | 设计 / 用途 |
|---|---:|---:|---|
| coast_grass_a | 144 | 0.700 | 18 片直立窄叶，无穗头或穗杆，岸后稀疏草簇 |
| coast_grass_b | 200 | 0.415 | 低矮向外散开的宽叶草，草簇间过渡 |
| coast_iceplant_a | 394 | 0.181 | 连续小厚垫，26 片短肉叶、7 朵粉紫花，约 1.00 × 0.76 m |
| coast_iceplant_b | 394 | 0.181 | 连续大厚垫，21 片短肉叶、9 朵粉紫花，约 1.40 × 1.03 m |
| coast_shrub_a | 156 | 0.750 | 偏绿的灰调矮灌木，与冷灰岸石区分 |
| coast_shrub_b | 176 | 0.942 | 黄绿色、较紧凑圆冠的矮灌木 |
| coast_cypress | 692 | 5.800 | 加大弯干，四层向同侧伸出、逐层缩短的深灰绿云团 |
| coast_cypress_far | 118 | 5.800 | 同原点、同包围盒远档，闭合树冠 |
| coast_palm | 752 | 5.650 | 8 片放射弧形下垂长叶，细弯干加 6 道窄环纹 |
| coast_palm_far | 120 | 5.650 | 保留 8 片弧形下垂叶和细干，近远同原点 / 包围盒 |

尺寸、原点、SHA、近远档对应关系见 [manifest.json](manifest.json)。坐标以米计，Y 向上。小件原点在占地包围盒的底部中心；两种树原点是树干落地点，**不要按倾斜树冠的包围盒重新居中**。柏树偏向局部 +X，绕 Y 旋转可调整风向。源文件按独立命名 collection 保存，各件均在自己的局部原点，可逐件隐藏编辑。

## 配色与材质

恶魔岛的黄绿植被与暖木色为基线，增加海滨灰绿、橄榄绿和冰花粉紫。灰绿灌木主色 #75976C；柏树使用更深的 #59755F / #78927A / #425E4C。草丛 / 灌木的冷暖差用来配合 426 的冷灰褐与暖沙岸石；植物本身不需要随岸石切换材质。具体 sRGB 颜色在 manifest 的 `palette_srgb` 中，参照色板保存在 `tools/art/source/coast_plants_435/reference/alcatraz_palette.json`。

[coast_plants_matte.tres](coast_plants_matte.tres) 为 StandardMaterial3D：顶点色作为 albedo、顶点 RGB 已是线性颜色、roughness=0.9、specular=0.18、metallic=0、完全不透明、背面剔除、无 next_pass。叶片、花瓣、树冠均有实体背面，不依赖双面材质。

[导入脚本](coast_plants_import.gd) 在 Godot 导入时将这个共享材质绑定到 **Mesh surface**。保留导入后的 surface 材质，提取 Mesh 用于 MultiMesh 时仍有正确颜色；不需要运行时再造材质。通用的白色材质覆盖会丢失顶点色。

10 份 `.glb.import` 由 Godot 生成 UID，保留 `nodes/root_script=null`、`gltf/texture_map_mode=1`、`meshes/light_baking=1`，关闭自动 LOD、切线、shadow mesh 和动画导入。本包无纹理，无新增纹理压缩设置。

## MultiMesh 铺设

草丛、冰花、灌木按 **每个原型一个 MultiMesh** 铺设。以实例变换设置位置 / 绕 Y 朝向，不需要复制网格或分拆花朵。常规旋转可用 0–360°；少量统一缩放建议 0.9–1.1，保持 Y=地面高度。冰花是无泥土底板的地被，适合不规则相接。

示例密度仅作构图起点：冰花放在岸石后方、整个底垫有地面承托的位置；连续铺设小块建议 X/Z 间距 0.82/0.62 m，大块 1.18/0.84 m，边缘有少量重叠并交替转向。草丛交错、留出间隙；灌木向内退 2–4 m，每 1.5–2.5 m 一组；树间距约 5–7 m。入口、主路、玩家和交互设施旁留空，实际避让由场景程序负责；本包不改变通行或碰撞。

## 树的 40 m 切档

两对树的近远档共用根部原点和完整 AABB，数据在 `lod_groups`。两个 MeshInstance3D 保持同一 transform、同一 `custom_aabb`：

```gdscript
near_node.visibility_range_end = 40.0
near_node.visibility_range_end_margin = 0.0
far_node.visibility_range_begin = 40.0
far_node.visibility_range_begin_margin = 0.0
```

不设置交叉淡化 pass。Godot 的距离按实例包围盒中心计算；同一 AABB 可让两档在同一距离切换。近 / 远不能各自按冠形重新居中。树若使用 MultiMesh，要按空间块分组，并让近 / 远两批使用相同覆盖范围；把整片海岸的树放进一个超大批次，会让它们按整批的包围盒一起切换。

验证了 39 / 41 m、39.95 / 40.05 m，以及 14.5° / 60° / 150° / 240° 方位的 43° 视角。每次仅绘制所需档位，没有重复绘制或消失。远档保留闭合背面，不限定只从某一侧看。棕榈远档保留 8 片叶的拱起和下垂轮廓，省略树干六道窄环纹；柏树远档保留四层云团。轮廓与局部折面仍有低面数差别，见审阅对照图。

## 源与审阅

- [Blender 源](../../../../tools/art/source/coast_plants_435/coast_plants.blend)
- [生成器](../../../../tools/art/build_coast_plants_435.py)、[导入工具](../../../../tools/art/source/coast_plants_435/imports.py)、[几何检查](../../../../tools/art/source/coast_plants_435/verify.py)、[LOD 实渲检查](../../../../tools/art/source/coast_plants_435/lod_verify.gd)
- [审阅图与记录](../../../../docs/design/coast-plants-435/v1.2/README.md)

约 12 m 的示例仅在隔离审阅工程中使用 426 岸石、430 浪花、432 海湾预设。不交示例 layout，不进入游戏，不修改恶魔岛或既有资源。
