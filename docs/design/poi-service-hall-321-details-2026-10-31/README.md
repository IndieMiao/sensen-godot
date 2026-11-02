# SGODOT-321 N2 独立新件 v1

作者：黄忠。Plane 署名 `5281cd25-6a49-4df8-9802-f3e534956e80`。

上官婉儿与不知火舞已选 B，8 座等待用户批准。本次按随后派活先完成与排法无关的新件，不装配 B 座位，不做 A2 窄件，不换公共壳皮肤。草稿 PR #597，目标 `wp-3d-scene`，不合并。

## 制作依据

主图为 316 R3 `SGODOT-316_Service_Hall_Main_2026-10-31.png`。尺寸按总监派活原文；雕塑按 321 `64efe200` 与不知火舞 `b421be39` 的补充：底座 Ø1.86m、高 0.40m，镂空螺旋本体宽不超过约 0.60m，组合总高约 1.60m。

十个独立 GLB：花环底座、镂空雕塑本体、两组含陈列的展示龛、宣传架、饮水机、叫号屏、告示板、空白横匾、窗台花箱。花箱复用两次，所有 mesh 名为 `<件名>_mobile`，每件一个 surface，`.import` 带 UID 和 `gltf/texture_map_mode=1`。每件 provenance 在 `tools/art/source/poi_service_hall/modules/`。

尺寸取值和最终顶点实测见 [实测表](SGODOT-321_N2_v1_props_asset_table.md)。展示龛开口宽 0.85m，顶高 2.40m，展示台顶高 0.75m，外框宽 1.10m、深 0.35m；原壳不开洞。叫号屏仅三色点，告示板四张空白纸，横匾留空且 `sign_name` 带 0.88 × 0.23m 可用范围。

## 图集与源文件

使用公共壳 `hall_palette.json` 的固定 2048² 布局，UV 放在语义色块安全区。`hall_albedo_ao_n2.png` 当前只准备新件所需色块，保留原壳区域不变；来源图集和公共壳文件均未修改。改色清单见 `prop_palette.json`。整间石砖、蓝十字地面区和 324 座椅重映射在用户批准 B 后进行。

Blender 源 `service_hall_details.blend` 保留具名部件，两个螺旋带、中央球体、龛框、独立瓶罐、陈列几何体、空白纸页和花叶均可编辑。模块原点为局部落地或挂墙中心，Godot 米制、Y 向上、+Z 正面。源里错开摆放只用于编辑，不是房间排布。

## 审阅与验证

[新件总览](SGODOT-321_N2_v1_props_props_overview.png)、[雕塑近景](SGODOT-321_N2_v1_props_sculpture_detail.png)、[双龛陈列](SGODOT-321_N2_v1_props_niche_displays.png)、[屏板和配套](SGODOT-321_N2_v1_props_boards_and_service_props.png)、[默认 43° 遮挡核对](SGODOT-321_N2_v1_props_fixed_props_default_43deg_360.png)、[固定新件全景](SGODOT-321_N2_v1_props_fixed_props_overview.png)。

最后两图仅在未改几何的公共壳里放固定新件，用于检查尺度和雕塑遮挡，不代表 B 整间定稿。用实际导入三角形检测默认相机到告示板、宣传架、叫号屏各 81 个采样点的遮挡；结果见 [validation](SGODOT-321_N2_v1_props_validation.json)。人物用实际 rig 校至 1.745m，桌面 Godot Vulkan Mobile 实渲，不代表设备性能验收。

公共壳护墙线条最前端到后墙 Z=-2.864m。龛背板在模块内向前移到 Z=0.13m，仍保持龛的 0.35m 总深度；宣传架审阅位置比白模前移 0.14m 至 Z=-2.55m，告示板挂到 Z=-2.83m；花箱移到 X=-2.91m、底 Y=1.06m 避开窗台。后续 B 整间装配须据这些实际厚度重跑胶囊，不能沿用白模导航结果当作细模结果。

## 复现

先按白模目录的 `dependencies.py` 提取固定 #594 / #563 依赖到 `output`，不改共享资产。

```bash
python tools/art/source/poi_service_hall/prepare_detail_palette.py
blender --background --factory-startup --threads 4 --python tools/art/source/poi_service_hall/build_details.py
python tools/art/source/poi_service_hall/verify_details.py
blender --background --factory-startup --threads 2 --python tools/art/source/poi_service_hall/verify_details_source.py
python tools/art/source/poi_service_hall/prepare_details_review.py
```

在本人私有 ADB 5097 环境下，检查 GPU 空闲后执行：

```bash
godot --headless --path output/poi-service-hall-321/details_project --editor --import
godot --headless --path output/poi-service-hall-321/details_project --script res://configure_details.gd -- "$PWD"
godot --path output/poi-service-hall-321/details_project --rendering-method mobile --rendering-driver vulkan
python tools/art/source/poi_service_hall/package_details.py
```

渲染程序输出完整记录后自动退出，再打包和上传。审阅图片与记录必须带黄忠署名上传 321 并下载校验。
