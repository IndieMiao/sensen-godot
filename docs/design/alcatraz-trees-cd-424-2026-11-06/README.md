# SGODOT-424 · 两种新树 c / d v1

【赵云】2026-11-06；Plane virtual_user_id：`8ea32e40-c0ba-4a31-864f-374a6bcbc554`。

给恶魔岛增加两种不同高度和冠形：c 为 7.8 m 的窄冠意大利柏，作主楼 / 灯塔旁的竖向点缀；d 为 3.6 m 的低伞冠小橄榄树，放台地前沿、步道转角及废墟前。以 #792 已发布 `bf0c31b1` 的场景、树位及 `tools/art/source/alcatraz_island/palette.json` 为基准，使用其中 `garden_dark / garden / garden_light` 与 `wood*` 色，不另引入冷蓝或薄荷绿。

| 资产 | 三角面 | surface | 外包围尺寸 X×Y×Z（m） | Godot UID |
|---|---:|---:|---|---|
| alc_tree_c | 240 | 1 | 1.63 × 7.80 × 1.38 | uid://cb8bxwktdwqtv |
| alc_tree_c_far | 116 | 1 | 同近档 | uid://dw7shdijhxlgp |
| alc_tree_d | 316 | 1 | 3.29 × 3.60 × 2.06 | uid://hqek2b20xc30 |
| alc_tree_d_far | 118 | 1 | 同近档 | uid://dv7vmxfgrujhm |

每个文件一个 `_mobile` 网格、一层哑光顶点色 surface，无贴图、骨架、动画或内置碰撞。原点在树根底部中心，Y=0，节点变换 identity；保留冠形自然偏心。两档整体包围盒相同。四份 `.import` 的 UID 均由 Godot 生成，`texture_map_mode=1`、`light_baking=1`、自动网格 LOD 关闭。旧 a / b 模型和 `.import` 保持原字节。

## 树位替换建议

完整坐标、旋转、scale、zone、原名及理由：[suggested_replacements.json](../../../tools/art/source/alcatraz_trees_cd_424/suggested_replacements.json)。按 `source_name` 原位替换，不新增树、不把 `placements` 与 `instances` 两份表示重复摆放。整岛仍是 26 棵：**8 a + 6 b + 4 c + 8 d**。树根位置和现有碰撞 / 导航不改。

| 原点位 | 新件 | 原坐标 X, Y, Z（m） | 用途 |
|---|---|---|---|
| alc_tree_a_014 | c | -28, 10, -9 | 灯塔南侧窄冠 |
| alc_tree_a_015 | c | -28, 10, -16 | 灯塔后侧竖向点缀 |
| alc_tree_b_007 | c | -22.2, 10, -9.5 | 主楼西侧 |
| alc_tree_b_008 | c | 22.2, 10, -9.5 | 主楼东侧 |
| alc_tree_a_000 | d | -25, 3.25, 6.5 | 第一层西转角 |
| alc_tree_a_002 | d | 24.5, 3.25, 6.6 | 第一层东边 |
| alc_tree_a_003 | d | 18, 3.25, 3.65 | 废墟前露出拱券 |
| alc_tree_a_005 | d | -26, 5.5, 1.5 | 第二层西转角 |
| alc_tree_b_004 | d | 16.7, 5.5, 1.9 | 第二层东转角 |
| alc_tree_a_008 | d | 22, 5.5, 1.9 | 第二层前沿 |
| alc_tree_a_012 | d | 16.7, 7.75, -2.8 | 第三层前沿 |
| alc_tree_a_013 | d | 22, 7.75, -2.8 | 第三层前沿 |

26 棵全近档由 11,684 降至 **9,544 面**，少 2,140 面（18.3%）。c / d 均按原尺寸，不缩放角色或其他树。山坡图是隔离副本中仅替换这 12 个实例的预览；正式 `layout.json`、场景、碰撞与导航留给马可波罗整合。

## 远档接入

[trees_cd_manifest.json](../../../assets/landmarks/alcatraz_island/trees_cd_manifest.json) 包含两组 `lod_groups`：40 m、margin=0；`common_aabb` 是 `[min,max]`，Godot 中使用 `AABB(min,max-min)`。与 #825 相同，两档使用同一变换和 AABB。

距离量到**实际 Camera3D 与世界 AABB 中心**；`FarmCamera.fit_ground_depth()` 会后移相机，接入时需用后移后的坐标。当前 #792 建筑 / 渡轮四组仍为 55 m，不把树组改成 55 m。MultiMesh 的 visibility_range 控制整批；按局部小组分批，或由程序按相同距离条件分配近远实例，避免整岛同种树一起切换。

c 两档均闭合；d 远档为固定 43° 相机省去任意 yaw、俯角 ≥40° 都不可见的冠底面。树保持 Y 轴直立，只绕 Y 转；若以后支持仰看或把树放倒，d 要用近档或补底面。原碰撞不跟随显示档位切换。

## 实渲与检查

- [四种树 + 游戏角色](SGODOT-424_TREES_CD_v1_lineup.png)：同一岛内灯光，原尺寸；1.75 m 游戏角色，43°。
- [山坡前后](SGODOT-424_TREES_CD_v1_slope_before_after.png)：相同 43° / yaw 35° / 27 m 视宽审阅机位，各 720×1000；不是默认开场镜头。沿用 #792 的宽视野细节显隐策略。检查视口几何 37,234 → 35,094 面、场景 draw 23 → 24，仅作为这一审阅机位记录。
- [39 / 41 m 切档](SGODOT-424_TREES_CD_v1_39m_41m.png)：各 360×800，43° / 6.72 m，原生 visibility_range；另验 39.95 / 40.05 m 与三个侧背方位。

验证报告：[几何与交付](geometry-validation.json) **116 项通过**；[整岛副本实渲与点位](render-validation.json) **57 项通过**；[原生切档](lod-validation.json) **75 项通过**。实际读取的 GLB SHA 与本交付一致；四件均无退化面 / 反向着色面，12 个树根保持原坐标并满足原导航留白，原场景 / 布局 / 旧树字节不变。

[像素差异记录](image-metrics.json)：默认图 c / d 剪影 IoU 0.97820 / 0.99649，外包围框最大偏移 1 / 0 px，交集区 RGB 平均绝对差 2.756 / 3.425（0–255）。低面轮廓和枝杈仍有细微变化，数值不替代画面验收。

所有图是桌面 Godot 4.7.2 Vulkan Mobile / RTX 2060 实渲，PNG 长边 ≤1600，只有排版和文字标注，没有调色。不是物理手机帧率或完整游戏接入验收。

## 可编辑源与复现

- [trees_cd.blend](../../../tools/art/source/alcatraz_trees_cd_424/trees_cd.blend)：四个独立 collection，冠、树干、分叉保留命名部件；collection 在根部原点重叠保存，可单独隐藏查看。
- [生成器](../../../tools/art/build_alcatraz_trees_cd_424.py)：色板、近远拓扑、法线转移、预算与导出。
- source 同目录的 `prepare.py / configure.gd / review.gd / lod_review.gd / verify.py / package_review.py`：隔离工程、Godot UID、真实游戏角色与山坡前后、距离切换、独立几何验证和出图。

```bash
source ~/.codex-zhaoyun/env.sh
nvidia-smi
flock ~/gs66-render.lock blender --background --python tools/art/build_alcatraz_trees_cd_424.py
python3 tools/art/source/alcatraz_trees_cd_424/prepare.py
flock ~/gs66-render.lock godot --headless --path output/alcatraz-trees-cd-424/project --import
flock ~/gs66-render.lock godot --headless --path output/alcatraz-trees-cd-424/project --script res://configure.gd
python3 tools/art/source/alcatraz_trees_cd_424/prepare.py --sync-imports
flock ~/gs66-render.lock godot --headless --path output/alcatraz-trees-cd-424/project --import
flock ~/gs66-render.lock godot --path output/alcatraz-trees-cd-424/project --rendering-method mobile --rendering-driver vulkan --disable-vsync --max-fps 60 --quit-after 1800
flock ~/gs66-render.lock godot --path output/alcatraz-trees-cd-424/project --rendering-method mobile --rendering-driver vulkan --disable-vsync --max-fps 60 --quit-after 1800 res://lod_review.tscn
python3 tools/art/source/alcatraz_trees_cd_424/verify.py
python3 tools/art/source/alcatraz_trees_cd_424/package_review.py
```

打包脚本需要 NumPy、Pillow、Noto Sans CJK。私有 ADB 5099，隔离 user dir，不读玩家存档。所有 Blender / Godot 含导入均持有 `~/gs66-render.lock`，脚本完成后自动退出。
