# SGODOT-320 N5 城市绿地 v1

作者：黄忠。Plane virtual_user_id：`5281cd25-6a49-4df8-9802-f3e534956e80`。

按 314 R3 批准主图、SVG 俯视图及上官婉儿的 320 派活制作。批准记录 `4fa670a7`，技术评估 `4c1535ae`；垃圾桶改为新制的确认记录为 320 `77a66827`。本次交付为独立美术装配，提交到 `wp-3d-scene` 的草稿 PR，等待上官婉儿技术检查、不知火舞画面验收和用户合并批准。

## 场景与尺寸

- 8 × 8m，Y 向上，+Z 为前缘入口；SVG 93.75px/m，环道中心 `(0, 0, 0.16)`。
- 四组三叶锯齿花坛，每组约 1.9m 见方，绿篱顶面约 0.35m；按主图建形，未使用 SVG 的方块示意尺寸。
- 农场喷泉直接复用，实测 Ø1.206m、高 0.994m。石材几何未缩放；原静态水片换为现有鱼塘 shader 的独立水面和细水流。
- 环道外径 6.40m、内径 5.50m，入口与十字连接砖道宽 0.72m；环道外草地可走。中央白石放射铺装单独建形。
- 四张绿椅，宽 0.960m，实际三个座板顶面均为 0.715m。八个 `seat_bench_1..8` 挂点含朝向与所属 module。为保证原尺寸喷泉周围通行，椅子从 SVG 示意位置移到半径 1.584m；偏移记录在 layout 中。
- 后部白椅宽 1.040m，只做装饰；玫瑰拱保留农场 pergola 的四柱，改为弧顶。两只鸟浴盆原高 0.840m，四盏新制路灯高 2.200m。
- 入口是独立砖门柱和空白弧牌模块，`sign_name` 带 `[1.45, 0.22]`m 可用区域；牌下净高 2.10m。园名由后续程序接入。
- 绿桶已按总监确认新制。白栅栏复用农场 `deco_fence`，树和灌木保留农场顶点色。外围树冠可略伸出地块，根部和碰撞留在边界内。

## 资产与预算

装配：`scenes/poi_city_park/poi_city_park_art.tscn`。套件与 layout：`assets/rooms/poi_city_park/`。共用地面、边界、栅栏和入口：`assets/rooms/_shared/shell_park/`。每件来源记录：`tools/art/source/poi_city_park/modules/<件名>/reuse_provenance.json`。

摆放后 **101,078 三角形 / 38 surface**，其中植物 **70,908 三角形**；统计包含全部六棵树、四组花坛、水面和背景卡，排除人物、灯的重复绘制和三个未摆放的原件控制模型。单件与原件变化见 [实测表](SGODOT-320_N5_v1_asset_table.md)。

全场景一张 2048² albedo 图集。农场顶点色烘成贴图，额外接触 AO 强度 0.06、距离 0.14m；草地没有整片 AO 压暗。图集实际导入为 BC7，启用 mipmap；各 GLB 为单 surface，不嵌入重复图像，`gltf/texture_map_mode=1`。

鱼塘 shader 与已有 flow/ripple/caustic 贴图按资源路径复用，另有两个 2×2 常量床色/岸距输入；它们不是额外的 N5 主色图集。水体材质保持独立。远景用批准主图的远村裁片，烘入同一图集，作为一个不投影的单层卡；卡随审阅相机水平朝向布置，边缘与天空色衔接。

## 检查与审阅

- 实际 GLB 顶点检查尺寸、三角形、surface、命名、UV、零面积面、图像是否嵌入及导入设置；Blender 源中直接测量具名座板和入口牌净高。
- Godot 4.7.2 / Vulkan Mobile / RTX 2060 实渲并检查导入后的面数、材质、挂点和真实资源路径。
- 半径 0.25m、高 1.745m 的胶囊完成 spawn → 中央 → 八个座位接近点 → exit 扫掠；主轴连接另查 0.70m 净宽，记录 16 个可达且相隔至少 0.70m 的站位。
- 树、白栅栏和未改色农场椅在同机位同光照下做烘前/烘后对照。场景绿椅是主图要求的主动改色，保色控制件不加入实际场景。
- 水体两个时刻的像素变化证明动画在运行；完整数值、路径和资源实测记录在 [validation](SGODOT-320_N5_v1_validation.json)。

[默认 360px](SGODOT-320_N5_v1_default_43deg_360.png) 是 43°、yaw 45°、6.72m 视宽，人物高 1.745m，重点框入口与喷泉；[安全区图](SGODOT-320_N5_v1_default_safe_bands.png) 标出顶部 100px、底部 90px。8m 场地在该默认视宽下会被左右裁切。[全景](SGODOT-320_N5_v1_panorama.png) 另行缩远，不代表默认人物比例。

其他图：[正俯视](SGODOT-320_N5_v1_topdown.png)、[喷泉近景](SGODOT-320_N5_v1_fountain_detail.png)、[花坛近景](SGODOT-320_N5_v1_parterre_detail.png)、[Stark 对照](SGODOT-320_N5_v1_reference_comparison.png)、[农场烘焙对照](SGODOT-320_N5_v1_farm_atlas_comparison.png)。这批图用于 v1 审阅，画面验收尚待不知火舞；桌面记录不代表手机性能结果。

## 复现

Blender 5.2.2；Python 需要 NumPy、Pillow。批准的主图和 SVG 已随源文件保存，Blender 中的背景裁片已打包。

```bash
blender --background --factory-startup --threads 4 --python tools/art/source/poi_city_park/build.py
python tools/art/source/poi_city_park/prepare_review.py
python tools/art/source/poi_city_park/verify.py
blender --background --factory-startup --python tools/art/source/poi_city_park/verify_source.py
```

在自己的 Godot 环境中设置私有 ADB 端口 5097，先看 `nvidia-smi`，再执行隔离工程导入与渲染：

```bash
godot --headless --path output/poi-city-park-320/project --editor --import
godot --path output/poi-city-park-320/project --rendering-method mobile --rendering-driver vulkan
python tools/art/source/poi_city_park/package_review.py
```

审阅程序输出全部截图和 validation 后自动退出。只允许停止本人启动并记录 PID 的进程。本交付未接入房间服务、玩法、相机交互或发布流程，未操作模拟器或真机。
