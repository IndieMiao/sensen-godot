# SGODOT-216 Tea House v1

作者：黄忠。Plane virtual user：`5281cd25-6a49-4df8-9802-f3e534956e80`。本目录日期按派活约定使用。

依据 Stark 第二版定稿 `2681:135483`、不知火舞标注、上官婉儿 10-31 派活、后裔 `6506d76e`、用户圆墩决定 `b46f278a` 和亚瑟挂点表 `7bec81f9` 制作。源图与派活记录保存在 `tools/art/source/tea_house/reference/`。只交美术资产和桌面验证，不接入玩法、房间服务或设备发布；PR 目标 `wp-3d-scene`，保持草稿，合并须用户批准。

## 场景与尺度

- 地面 6.8 × 6.4m，顶面 **Y=0.08m**，两面墙高 3.70m。浅蜂蜜木长条地板、暖白墙、浅木柱梁；左墙为真正切开的圆窗，窗外景是可替换的独立模块。
- 三张独立圆茶桌，木桌面实测 Ø0.90m、高 1.00m；条纹布略垂出桌沿，碰撞保守取半径 0.47m。每桌茶盘、壶、杯和花瓶均具名可编辑，花叶分成不投影模块。
- 九只软垫圆墩 Ø0.56m，坐面离地 0.715m；窗下 2.10m 长凳另有三座，座距 0.70m。**共 12 座，所有座位世界 Y=0.795m**。圆墩按本次规定尺寸新制，形制参考 324。
- 柜台宽 2.20m、台面高 1.15m，后方留 Ama 通道；上方两层架和三盏方灯笼。门边 1.00m 低台为 Hana 咖啡角，含咖啡壶和两只杯。
- 后墙竖板木门是关闭的布景；入口在前沿中间。前沿 1.30m 宽平接平台保持退出和重新进入时脚下连续有地面，spawn 与 exit 相隔 1.25m。
- 空白招牌在后墙门上方，`sign_name` 可写范围 1.04 × 0.26m。Ama、Hana、Lena 仅有挂点，本卡没有新建居民人物。

先用真实导出白模自查 12 座，再进入细模。当前布局保留三桌分区，前桌略向后收，为入口绕行留出通道；柜台前实测通道 0.825m、入口 1.30m。0.25m 半径 / 1.745m 高胶囊走到所有座位接近点、人物站位和出口；主通道另用 0.35m 半径扫掠。16 个可达站位相隔至少 0.70m，并避开三处 NPC 站位。

## 资产与图集

装配 `scenes/tea_house/tea_house_art.tscn`；资产和合同 `assets/rooms/tea_house/`；可编辑源 `tools/art/source/tea_house/tea_house.blend`；生成器 `tools/art/build_tea_house.py`。原始白模源和预检也保留。

摆放后 **55,948 三角形 / 36 surface**，植物 **6,596 三角形**。25 个 GLB 定义，四个原型只供实例使用，预算包含实际重复摆放。每件都有 `<件名>_mobile` 网格名、单材质槽、外链 `room_albedo_ao.png`、导入 UID、`gltf/texture_map_mode=1` 及逐件 `reuse_provenance.json`。

全场一张 2048² RGBA 图集：左侧 1536 × 2048 为房间色彩、木纹与柔和接触 AO；右下 512² 为共享植物图集缩放后的区域。`olive_tree` 和 `pothos` 保留原网格，UV 重映射，植物原件没有修改。保留双面和 alpha scissor 0.45；小叶、花和窗外景不投影。小花束使用共享植物库的六面叶片和花瓣生成函数，保持可编辑。图片源是表面色彩，不包含最终方向光照。

三盏局部灯属于美术场景；共享 scene_bench 不重复添加它们。一个带阴影方向光配暖环境光。圆窗墙面在布尔切口后保留平面法线，避免大平面出现错误的三角明暗条纹。

## 验证与媒体

[默认 43° / 360px](SGODOT-216_tea_v1_default_43deg_360.png)、[整间全景](SGODOT-216_tea_v1_overview.png)、[正俯视和胶囊](SGODOT-216_tea_v1_topdown_capsules.png)、[软垫圆墩坐姿](SGODOT-216_tea_v1_seated_stool.png)、[柜台与咖啡角](SGODOT-216_tea_v1_counter_coffee_corner.png)、[Stark 对照](SGODOT-216_tea_v1_reference_comparison.png)、[植物图集对照](SGODOT-216_tea_v1_plant_atlas_comparison.png)。

默认相机为 43°、yaw 45°、视宽 6.72m；8m 以上对角线的房间会在默认视宽两侧裁切，全景另行拉远。人物实际 rig 校至 1.745m。坐姿使用现有 `sit_idle` 和坐面以下 0.34m 的根节点偏移；挂点遵守 0° 朝 −Z，审阅 rig 的本地正面是 +Z，因此展示时加 180° 朝向偏移。

[实测资产表](SGODOT-216_tea_v1_asset_table.md)、[完整 validation](SGODOT-216_tea_v1_validation.json)、[scene_bench 结果](SGODOT-216_tea_v1_scene_bench_result.json)、[碰撞图](SGODOT-216_tea_v1_scene_bench_collisions.png)、[15 秒原速路线](SGODOT-216_tea_v1_walkthrough.mp4)。

验证读取实际 GLB 顶点、UV、材质和命名；Blender 检查具名桌面、座面和门板顶高；Godot 检查实际导入预算、挂点、碰撞和灯光。参考同类位置的墙、木梁和地板采样色相差分别记录在 validation，要求 ≤10°，不把它当作注册几何的像素相似度。植物重映射有同机位、同光照对照。

共享 scene_bench 的七组检查按原阈值运行。本机桌面 VSync 首次造成路线计时变慢，隔离 QA 工程关闭 VSync 并限 60 FPS 后通过；没有修改移动速度或测试时限。X11 桌面抓屏得到黑帧，失败产物仅留 `output/tea-216/failed-x11-recording/`；最终视频复用仓库既有视口采集器，按真实单调时钟间隔编码 15 秒，不加速，首、中、尾帧检查并人工查看。录像使用 43° 全景机位，默认截图仍为 6.72m。本轮为桌面 Vulkan Mobile / RTX 2060 证据，不代表手机性能验收。

## 复现

已验证环境：Blender 5.2.2、Godot 4.7.2、Python 的 NumPy / Pillow / Shapely、FFmpeg。按本人私有 ADB 5097 环境运行；显卡共用，先检查 `nvidia-smi`。

```bash
python tools/art/source/tea_house/plan.py
python tools/art/source/tea_house/prepare_window.py
blender --background --factory-startup --threads 4 --python tools/art/build_tea_house.py
python tools/art/source/tea_house/finalize_atlas.py
python tools/art/source/tea_house/bench_data.py
python tools/art/source/tea_house/prepare_review.py
python tools/art/source/tea_house/verify.py
blender --background --factory-startup --threads 2 --python tools/art/source/tea_house/verify_source.py
godot --headless --path output/tea-216/project --editor --import
godot --headless --path output/tea-216/project --script res://configure_imports.gd -- "$PWD"
python tools/dev/scene_bench/run.py tea_house --project output/tea-216/project --output output/tea-216/bench
python tools/art/source/tea_house/record_route.py
godot --path output/tea-216/project --rendering-method mobile --rendering-driver vulkan res://review.tscn
python tools/art/source/tea_house/package_review.py
```

所有本人启动的渲染进程完成后自动退出。中间图、日志、帧序列和失败录像在 `output/`，不进入运行时资产。

## 挂点合同

`layout.json.anchors` 是程序读取的唯一名单；下面的表由它生成。交付后不改名，特别保留 `seat_table1_1`、`seat_table1_2`、`seat_table2_1`、`seat_table2_2`。不为座位另建 `stand_`。坐点朝向 0° 为 −Z，180° 为 +Z；`module` 跟随对应物件显隐。

<!-- generated anchors -->

| name | position (m) | yaw | module | size |
|---|---|---:|---|---|
| use_tea_table_1 | -0.950, 1.080, -0.100 | 0 | tea_table_1 |  |
| seat_table1_1 | -0.950, 0.795, 0.740 | 0 | stool_1_1 |  |
| seat_table1_2 | -0.223, 0.795, -0.520 | 120 | stool_1_2 |  |
| seat_table1_3 | -1.677, 0.795, -0.520 | 240 | stool_1_3 |  |
| use_tea_table_2 | 0.350, 1.080, 1.500 | 0 | tea_table_2 |  |
| seat_table2_1 | 1.077, 0.795, 1.920 | 60 | stool_2_1 |  |
| seat_table2_2 | 0.350, 0.795, 0.660 | 180 | stool_2_2 |  |
| seat_table2_3 | -0.377, 0.795, 1.920 | 300 | stool_2_3 |  |
| use_tea_table_3 | 1.850, 1.080, 0.050 | 0 | tea_table_3 |  |
| seat_table3_1 | 1.850, 0.795, 0.890 | 0 | stool_3_1 |  |
| seat_table3_2 | 2.577, 0.795, -0.370 | 120 | stool_3_2 |  |
| seat_table3_3 | 1.123, 0.795, -0.370 | 240 | stool_3_3 |  |
| use_bench | -2.680, 0.795, -0.400 | -90 | window_bench |  |
| seat_bench_1 | -2.880, 0.795, -1.100 | -90 | window_bench |  |
| seat_bench_2 | -2.880, 0.795, -0.400 | -90 | window_bench |  |
| seat_bench_3 | -2.880, 0.795, 0.300 | -90 | window_bench |  |
| use_counter | -0.500, 1.230, -1.950 | 0 | counter |  |
| stand_counter | -0.500, 0.080, -1.230 | 0 | counter |  |
| stand_keeper | -0.500, 0.080, -1.230 | 0 | counter |  |
| npc_keeper | -0.500, 0.080, -2.640 | 180 | counter |  |
| badge_keeper | -0.500, 2.130, -2.640 | 180 | counter |  |
| npc_hana | 2.500, 0.080, -1.980 | 180 | coffee_console |  |
| stand_hana | 2.500, 0.080, -1.160 | 0 | coffee_console |  |
| npc_lena | -2.650, 0.080, 1.160 | -90 | window_bench |  |
| stand_lena | -1.830, 0.080, 1.200 | 90 | window_bench |  |
| spawn | 0.300, 0.080, 2.550 | 0 |  |  |
| exit | 0.300, 0.080, 3.800 | 180 |  |  |
| badge_exit | 0.300, 1.050, 3.800 | 180 |  |  |
| sign_name | 2.480, 2.920, -2.812 | 180 | name_sign | [1.04, 0.26] |
| cam_default | 0.100, 1.100, 0.400 | 45 |  |  |
