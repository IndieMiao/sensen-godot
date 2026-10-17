# SGODOT-214 · Tackle Shop · v1.1

【赵云】2026-10-16 · PR #439 的密度、暖度与装配交付返修，待上官婉儿技术复查、
不知火舞画面验收及用户批准。依据火舞评论 `1b92cc5d` 和上官的八项补充要求。

## 交付入口

| 内容 | 仓库文件 |
| --- | --- |
| 可编辑 Blender 源文件 | [tackle_shop.blend](../../../tools/art/source/tackle_shop/tackle_shop.blend)，38 个命名 KIT 集合、936 个可编辑网格零件 |
| 模型生成 | [build_tackle_shop.py](../../../tools/art/build_tackle_shop.py) |
| 同一图集的细节处理与材质导出 | [finalize_tackle_atlas.py](../../../tools/art/finalize_tackle_atlas.py) |
| 独立源文件 / GLB / 交叠验证 | [verify_tackle_shop.py](../../../tools/art/verify_tackle_shop.py) |
| 装配入口 | [tackle_shop_art.tscn](../../../scenes/tackle_shop/tackle_shop_art.tscn) |
| 装配脚本 | [tackle_shop_art.gd](../../../scenes/tackle_shop/tackle_shop_art.gd) |
| surface 导入参数校准 | [material_import.gd](../../../assets/rooms/tackle_shop/material_import.gd) |
| 碰撞与真实 P0RoomNav 验证 | [verify_tackle_assembly.gd](../../../tools/art/verify_tackle_assembly.gd) |
| 建议挂点 / 碰撞 / 局部灯配置 | [layout.json](../../../assets/rooms/tackle_shop/layout.json) |
| 实际资产预算 | [asset_stats.json](../../../assets/rooms/tackle_shop/asset_stats.json) |

## v1.1 改动

- 主地面仍为 **6.80 × 6.40 m，顶面 Y=0.08**；锚纹地毯主体直径从 1.90 增至
  **2.60 m**（含流苏外径约 2.78 m）。
- 柜台及台上小件整体后移 **0.46 m**，柜台后通道从 1.36 缩为实测 **0.90 m**。
  Finn 建议位置调整为 `(-0.36, 0.08, -2.50)`；柜台前站位为 `(-0.36, 0.08, -0.48)`。
- 左墙下增加绳卷木箱，Rafa 一侧增加鱼篓，两者均有碰撞体。Kai / Rafa 对称站位、
  舷窗旁四竿架和两只浮漂桶保留。
- 墙改为暖桃色，木柱、木梁、地板结合实际光照重新校色。重新烘焙更深的墙脚、
  家具接触 AO；环境与主光提高明暗区分。
- 鱼牌放大 1.30 倍（宽约 1.24 m）；旗串约 1.51 m、旗面加高；壁灯放大 1.55 倍。
  三盏实际局部暖光分别来自壁灯、吊灯和柜台提灯。

预算：**38 个 GLB、39 个摆放实例、66,052 三角面、39 surface**，一张 2048² 图集；
鱼竿架连桶仍为 **1,196 面**，全屋正好两只浮漂桶。所有 GLB 均带
`gltf/texture_map_mode=1`。

## 材质与装配

每个 GLB surface 明确拥有自己的材质与外部 `room_albedo_ao.png` 引用。
两类材质分别是 `TackleRoomAtlas`（不透明、roughness 0.80）和
`TackleFishbowlGlass`（alpha 0.075、roughness 0.20、双面）。图片不重复嵌入 GLB。

装配脚本读取 layout 的 assets / instances，保留原有 surface 材质，不设置
`material_override` 或 surface override。Godot 4.7.2 会将 glTF 的 specular 扩展
留为默认 0.5，因此导入脚本只逐 surface 校准该参数到 **0.28**，不替换材质对象，
不改变它的贴图、透明度或粗糙度。实际导入检查确认玻璃仍为 alpha/depth-prepass 透明。

场景自身只创建 layout 的三盏局部灯。`WorldEnvironment` 和太阳由使用场景提供；
审阅工程从 `review_lighting` 读取它们，游戏接入也可按该配置建立环境。

全部 **20 个实际 CollisionShape3D** 来自 assets / instances 的 colliders，包括
room_shell 的主地面、墙、开放边缘限制和出口落脚面；保留位置、旋转与实例缩放。
P0RoomNav 测试直接读取这些形状，得到 6.8 × 6.4 的主地面网格与 Y=0.08，
spawn 可连通 1,115 个网格，柜台、居民及渔情板站位均可达。前沿可达位置进入
现行 0.6 m 出口触发半径。测试未用 layout 的 boundaries / floor_size 构造导航。
游戏的 `assets/p0/outposts/tackle.anchors.json` 仍由程序按本 layout 建议接入。

## 审阅与证据

- **01_spawn_follow_360**：玩家站在 `spawn (0,0.08,0.83)`，镜头跟随该点，
  360×800 / 43° / 45°方位 / 6.72 m。已看图确认柜台和现有造型 Finn 在第一眼画面内。
- **02_whole_43deg**：不裁切的整间全景；其余近景、三视、碰撞图和三列对照覆盖本轮改动。
- **09_lamp_control**：同镜头、同全局光，只有三盏局部灯开关不同，验证暖光确实照到场景。
- **12_color_saturation_value**：柱、梁、墙、地面的对应 11×11 px 中位数，记录
  HSV 与 D65 L*。四处最终最大色相差 **8.61°**；饱和度差、V 差及 L* 差在 JSON
  完整列出。取样用于核对具体表面，不等同全图相似度或画面验收。
- **13_walkthrough**：15 秒原速桌面录像，首、中、尾帧已检查；视频在 Plane 附件，
  仓库记录媒体哈希与下载回读。

本轮 **286 项源 / GLB 检查、262 项实际导入 / 渲染检查、104 项装配 / P0RoomNav 检查、
33 项物理角色路线检查、7 项 spawn 跟随检查**均通过。网格交叠检查无意外跨模块穿插；
墙角、地板承托、舷窗装配和鱼缸接合在报告中明确分类。两个负例分别验证鱼板穿柜台
会被检出，以及去掉柜台碰撞会真实改变 P0RoomNav 网格。

P0RoomNav 与 Finn 的参考代码 / 资源固定来自 farm-dev `f8c3391c`；源哈希、
原始测量和限制见各验证 JSON。实际运行后端为 Godot 4.7.2 / Vulkan Mobile /
RTX 2060；本轮是美术与装配验证，未作完整游戏接入、安卓或真机性能结论。

## 复现

```sh
source ~/.codex-zhaoyun/env.sh
blender --background --factory-startup --threads 6 --python-exit-code 1 \
  --python "$PWD/tools/art/build_tackle_shop.py"
python3 tools/art/prepare_tackle_shop_review.py
python3 tools/art/prepare_tackle_spawn_review.py
python3 tools/art/prepare_tackle_nav_review.py
godot --headless --editor --path output/tackle-214/project --import --quit
blender --background --factory-startup --python-exit-code 1 \
  --python "$PWD/tools/art/verify_tackle_shop.py"
godot --headless --path output/tackle-214/project --script res://verify_tackle_assembly.gd
godot --path output/tackle-214/project --rendering-method mobile \
  --rendering-driver vulkan res://review.tscn
godot --path output/tackle-214/project --rendering-method mobile \
  --rendering-driver vulkan res://spawn_review.tscn
python3 tools/art/run_tackle_bench.py --ffmpeg /path/to/ffmpeg --ffprobe /path/to/ffprobe
godot --path output/tackle-214/project --rendering-method mobile \
  --rendering-driver vulkan --script res://tools/dev/scene_bench/capture_collisions.gd \
  -- --slug tackle_shop --output "$PWD/output/tackle-214/bench"
python3 tools/art/package_tackle_v11.py
```

源码生成会覆盖 blend / GLB / atlas，应先把手工改动写回生成脚本。
截图与录像需要有效桌面显示；gs66 录屏适配按测试 PID 捕获自己的 X11 窗口，
避免 Wayland 根窗口黑图。公共 scene_bench 与其他房间没有修改。
