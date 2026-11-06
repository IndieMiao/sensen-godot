# SGODOT-424 恶魔岛树远档 v1

【赵云】2026-11-06；Plane virtual_user_id：`8ea32e40-c0ba-4a31-864f-374a6bcbc554`。

交付 `alc_tree_a_far`、`alc_tree_b_far`，各一个网格、一个 surface、顶点色哑光材质。近档 GLB 和 `.import` 保持原字节。A 保留向 +X 偏的五团柏树冠和弯干，B 保留三团圆冠；减掉细枝，冠团逐个转移近档的颜色和法线。

| 模型 | 近档三角面 | 远档三角面 | 降幅 | 远档 UID |
|---|---:|---:|---:|---|
| alc_tree_a | 520 | 118 | 77.3% | uid://bukcmggyoa3g2 |
| alc_tree_b | 316 | 118 | 62.7% | uid://diah2mlire5lc |

两档原点均在原树根位置，变换为 identity，Y=0 落地。包围盒逐轴与近档一致，A 冠幅偏心也保留。无贴图、骨骼、动画、碰撞。`.import` UID 由 Godot 生成，`gltf/texture_map_mode=1`、`meshes/light_baking=1`、`meshes/generate_lods=false`。

按 #792 本次读取的 `d7b57574`（17 棵 A + 9 棵 B），26 棵树全近档 11,684 面，全远档 3,068 面，减少 8,616 面 / 73.7%。30 棵远档为 3,540 面。这是几何预算，不是整岛屏幕计数或手机帧率。

## 40 m 接入约定

运行时清单：[tree_lod_manifest.json](../../../assets/landmarks/alcatraz_island/tree_lod_manifest.json)。包含建议的两组 `lod_groups`、40 m 阈值和共同包围盒。对照 #792 的[已发布清单摘录](../../../tools/art/source/alcatraz_tree_lod_424/reference/layout-lod-contract.json)，主楼、灯塔、水塔仍为 55 m；树尚无 LOD 组。本交付增加文件和建议，不修改马可波罗的场景、布局或近档。

单棵或局部小组接入时，近档 `visibility_range_end=40`、远档 `visibility_range_begin=40`，两侧 margin=0；两档设置同一 `custom_aabb`，使用同一位置、yaw、缩放和材质。清单的 `common_aabb` 是 `[min, max]`，构造 Godot AABB 时用 `AABB(min, max-min)`。单 surface 网格可直接用于 MultiMesh。

**距离是实际 Camera3D 到 geometry 世界包围盒中心的欧氏距离。**不是玩家、树脚或相机原始 target 的距离。岛场景的 `FarmCamera.fit_ground_depth()` 会沿视轴后移相机，必须用后移后的 `global_position` 核距离。当前主场景 `_add_asset` 的建筑 55 m 不能直接套给树。

**MultiMesh 的 visibility_range 控制整批。**如果需要逐棵按 40 m 切换，应由程序按相同中心距离把实例分配到近 / 远两个批次；或划为局部小组，按共同的组包围盒切换。不能将全岛同种树塞进一个批次后宣称是逐棵距离 LOD。原始实例碰撞不随显示档位变化。

远档针对岛上固定 **43° 俯视相机、树只绕 Y 旋转**：省去在任意 yaw、俯角 ≥40° 下都背向镜头的冠底面，以及被地面 / 树冠挡住的 A 树干端盖。近档保留完整几何。若以后允许低机位仰看、把树放倒，需用近档或补回这些面；不能把这两个远档当作任意角度的闭合资产。

## 审阅与验证

- [39 / 41 m 切档对照](SGODOT-424_TREE_LOD_v1_39m_41m.png)：每格原始 360×800，43° / yaw 14.5°，正交宽 6.72 m；同框大小不因距离改变，直接比较两档形状。1440×968 拼图未缩放、未调色。
- [侧面 / 背面对照](SGODOT-424_TREE_LOD_v1_angles.png)：yaw 60° / 150° / 240°，每格来自 400×600 截图，仅裁空背景，1:1 像素。
- [几何验证](geometry-validation.json)：47 项通过；两件各 118 面、1 surface、无退化面 / 反向着色面、原点和整体包围盒一致、近档字节不变、UID 与导入参数正确。
- [引擎验证](render-validation.json)：75 项通过。近远实例同时在场景中，由 Godot `visibility_range` 决定可见性；39 / 41 m 以及 39.95 / 40.05 m 的实际可见三角数分别等于对应近 / 远档，没有两个档位同时显示或都消失。报告核对实际 GLB SHA，排除旧导入缓存。
- [图像量测](image-metrics.json)：默认图 A / B 剪影 IoU 为 0.93267 / 0.98785，外包围框最大偏移 2 / 1 px；交集区 RGB 平均绝对差 6.61 / 2.846（0–255）。这是差异记录，不替代不知火舞验收；细枝和冠缘存在低面化变化。

实渲为桌面 Godot 4.7.2 Vulkan Mobile / RTX 2060；使用岛白模的日光、环境光及顶点色材质设置，在隔离工程中验证。没有地面、UI 或阴影 pass，便于读取单树几何计数。这不是整岛合成截图或 Android 性能验收。

## 源文件与复现

可编辑源：[tree_lod.blend](../../../tools/art/source/alcatraz_tree_lod_424/tree_lod.blend)，每棵树独立 collection，冠团与树干分别命名。生成器：[build_alcatraz_tree_lod_424.py](../../../tools/art/build_alcatraz_tree_lod_424.py)。检查与出图脚本在同一 source 目录。

从仓库根目录执行（所有 Blender / Godot 命令必须持有共享渲染锁）：

```bash
source ~/.codex-zhaoyun/env.sh
flock ~/gs66-render.lock blender --background --python tools/art/build_alcatraz_tree_lod_424.py
python3 tools/art/source/alcatraz_tree_lod_424/prepare.py
flock ~/gs66-render.lock godot --headless --path output/alcatraz-tree-lod-424/project --import
flock ~/gs66-render.lock godot --headless --path output/alcatraz-tree-lod-424/project --script res://configure.gd
python3 tools/art/source/alcatraz_tree_lod_424/prepare.py --sync-imports
flock ~/gs66-render.lock godot --headless --path output/alcatraz-tree-lod-424/project --import
flock ~/gs66-render.lock godot --path output/alcatraz-tree-lod-424/project --rendering-method mobile --rendering-driver vulkan --disable-vsync --max-fps 60
python3 tools/art/source/alcatraz_tree_lod_424/verify.py
python3 tools/art/source/alcatraz_tree_lod_424/package_review.py
```

最后一步需要 Pillow、NumPy 和 Noto Sans CJK 字体。隔离工程不读玩家存档、不连服务器，出图后自行退出。ADB 私有端口 5099。
