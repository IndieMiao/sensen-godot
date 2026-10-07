# Coffee Shop · SGODOT-179 · 第 1 轮修改样板

刘备，2026-10-07。按不知火舞在 SGODOT-171 / 179 的评审修改。本卡保持 **In Progress，待用户确认样板**；180–186 本轮尚未改动。共享角色 harness 消费赵云提交 `39f50fb`，核心文件未修改；共享植物库独立提交 `26aed6f`。

![Figma / Godot / 50% overlay](comparison.png)

## 参考、机位与色板

Figma 文件 `OMLTC3yw3u2WDjOZhLnhaR`，[node 545:2956](https://www.figma.com/design/OMLTC3yw3u2WDjOZhLnhaR/Gensen--US-?node-id=545-2956)。保留原图 SHA-256 `bac78a88a5cb5fdc3aa2d2e7a026c31ec402bc84b5a978c84413c2951d44ce7a`，本轮重新目视对照；不是重新抓取的云端修订。

美术相机 yaw 45°、pitch 约 28°、正交 size 9.3，目标 `[0,1.18,0]`。三栏用完整原图和完整实景等尺寸 letterbox；第三栏直接 50% 混合，没有形变或逐物件挪图。此叠图会如实暴露屋高、招牌位置和家具间距的剩余差异，不是像素还原度分数。角色测试使用相同 yaw/pitch，在 4:3 视口拓宽至 size 10.2 并上移视点 0.08m，防止屋顶裁切。

下表是原图 9×9 像素区域的中位色（含原图光照），材质 albedo 另据实际灯光调整，不能直接把采样值当无光照反射率。采样坐标和方法见 [reference-palette.json](reference-palette.json)。

| 色类 | 原图采样 | 像素坐标 |
|---|---|---|
| limestone | `#F5C485` | [1229, 674] |
| sage_board | `#C3B693` | [1008, 520] |
| honey_oak | `#ECB477` | [606, 1020] |
| upholstery | `#E1B38B` | [705, 846] |
| leaf_lit | `#78803B` | [664, 540] |
| leaf_shadow | `#738141` | [623, 503] |
| graphite_pedestal | `#605754` | [597, 949] |
| ivory_lamp | `#FEFAEB` | [821, 387] |

## 评审清单逐项回应

| 要求 | 本轮结果 |
|---|---|
| 共享植物库 P0 | 已做。龟背竹 11 片裂叶、白掌 4 朵白花、绿萝、0.65/1/1.4m 白花藤、矮灌木；另有橄榄树和果树。叶片为封闭弯曲体，叶脉烘进独立图集，局部轴心、可编辑源文件与实际预览齐全。见 [植物库](../../../assets/rooms/_shared/plants/README.md)。 |
| 花藤 P0 | 已做。沿主拱整圈、右窗拱与柱、窗顶和前沿布置分段件，增加花量；短中长段、旋转和偏移打破相同直条重复。仍能看出重复叶形，后续可按样板反馈继续雕形。 |
| 椅子和桌脚 P0 | 已做。白色连续软包圆背和布面坐垫、木腿；深灰细柱与圆盘底。桌/椅高度按 Basic Room 校准。 |
| 温室窗 P0 | 已做。真实独立透明玻璃、细窗棂、窗外独立植物和退后的淡色背景，不再在不透明玻璃上贴叶片。没有昂贵折射/SSR。 |
| 柜台 P1 | 已做。保留浅木竖板和浅色台面，三层可颂/玛芬/蛋挞带烤色，银色咖啡机、黑手柄、磨豆机、杯碟、小盆栽；补墙架、四种杯色/尺寸和植物画。 |
| 吊灯 P1 | 已做。两盏加大的米白灯罩移到柜台前上方，各配不投影的局部暖灯。 |
| 植物角 P1 | 已做。左后龟背竹、白掌与小盆；右侧大叶盆栽和高盆栽。共享绿萝使用编织盆；大盆暂为有筋纹的陶盆，尚未把右侧大盆做成参考的完整藤编纹理。 |
| 招牌 P1 | 已做。外挑铁杆、椭圆木牌、GREENHOUSE CAFE 字样。相对原图外挑距离仍较大，叠图可见。 |
| 前沿 P1 | 已做。台阶与前沿连接，柱头花丛与向外垂藤；碰撞使用连续凸坡道，台阶外侧有受控落脚区及边界。 |
| 桌面 P1 | 已做。雏菊花瓶、杯碟与咖啡纹样。 |
| 窗梁/后墙/倒角 P2 | 已做。保留可见斜撑；后墙四种鼠尾草板色；强化柱帽、台面、厚底座圆角。 |
| 光照/材质共性 | 已做。冷色环境、暖主光、两盏局部灯、较强接触 AO；错缝木板、细拼缝和近窗暖色衰减。地板可见实时窗框投影，叶脉/木纹/布面噪声烘焙。仍比参考的绘画式漫反射和圆润细节更简化。 |
| 机位/对照 | 已做。全参考、整景、50% 叠图、两张细节和正交图；保留可见差异，未宣称美术验收。 |

## 角色、碰撞与尺度

共享 harness 的同一默认 Avatar、胶囊 r=0.21 / h=1.25 / SPEED=3.75。真实 Godot Mobile/Vulkan 运行 **39/39 项通过**：出生点、十段连续路线、家具/盆栽/矮墙/开放边界探针、三个实测通道、入口出入、斜向滑墙、输入释放、idle/run 和前后台失焦停止。

第一次真实测试发现旧斜箱与地板有断差，现用凸多边形连续坡道；地板碰撞顶面对齐美术 0.0495m。两内侧椅子移开，额外 0.70m 宽胶囊扫掠通过。实测两桌横切 1.19m、桌柜间 1.30m、入口 1.32m；这些是在 JSON 指定切面测量，完整路线由角色实际走过。

H≈1.7455m。Blender 实际几何高度：柜台 1.2005m（基线 +4.16%）、椅面 0.71045m（+3.72%）、桌面 1.0175m（−10.35%）。侧面温室拱净高 2.69m，比 Basic Room 门 2.33m 高 15.45%；保留温室高拱与窗框的对齐，是明确记录的建筑例外。角色入口是前沿缺口，侧拱外沿仍受边界约束。

证据：[逐项结果](bench-result.json)、[尺度](bench-scale-measurements.json)、[源模型测量](source-scale.json)、[录制路线](bench-record-result.json)、[视频元数据](bench-video-metadata.json)。截图：出生点、柜台前、门口和碰撞体均附本卡。共享框架默认实心调试材质会遮住本场景内部，咖啡店的独立 capture_collisions.gd 改用同一批实时物理形状的线框截图，未改动框架核心。

首次默认 VSync 检查出现长帧间隔；隔离项目关闭 VSync、限制 60 FPS 后重跑通过。此环境处理仅在本场景 adapter，不改核心或生产设置。X11 录制虽然编码成功但画面全黑，已作废。最终视频来自真实 Godot 视口，保存实际单调时钟时间戳后按原时间间隔编码成 15 秒视频；无加速。抽查 0/1.5/3/4.5/6/7.5/10/14.5 秒共 8 帧，均无黑屏；约 6.8 秒完成整条路线，后半段保留 idle 观察。它是桌面走位证据，不是手机性能测量。

![Character scale and spawn](bench-spawn.png)

## 源文件、重建与预算

米制、Godot Y-up、前方 +Z，模块为地面/安装点局部轴心。Blender 和生成脚本保持一致；source 中含共享植物实例。手动更改大型布局后必须重烘房间接触 AO。

```sh
blender --background --factory-startup --python "$PWD/assets/rooms/_shared/plants/source/build_plants.py"
blender --background --factory-startup --python "$PWD/tools/art/build_coffee_shop.py"
python3 tools/art/source/coffee_shop/render_r1.py
# Pillow 环境中生成三栏图、正交图及预算证据
python3 tools/art/source/coffee_shop/package_r1.py
python3 tools/art/source/coffee_shop/run_bench.py --record
```

Editable：`tools/art/source/coffee_shop/coffee_shop.blend`。美术场景：`scenes/coffee_shop/coffee_shop_art.tscn`。正式模型、放置、简易碰撞、bench 数据：`assets/rooms/coffee_shop/`。共享 harness 位于 `tools/dev/scene_bench/`，调用方式没有修改其核心。

| 指标 | 当前值 |
|---|---:|
| 房间独立 / 摆放三角面 | 60,678 / 80,734 |
| 已使用植物独立 / 摆放三角面 | 85,372 / 441,576 |
| 合计摆放三角面 | 522,310 |
| 静态 surface | 97 |
| 共享图集 | 2 × 2048²，mipmap / VRAM compression |

32 个本场景 GLB + 9 个植物库 GLB 均通过单 mesh/surface、无重复内嵌图集检查。实际摆放 97 个实例。高密度植物使摆放几何成本高于初稿；这是本轮质量样板预算，尚未做实体手机验收，不把桌面 60 FPS 当作移动端性能结论。完整数值见 [revision-verification.json](revision-verification.json)。

![R1 compared with previous draft; framing differs](revision-before-after.jpg)

交付：SGODOT-179 新增 11 个 R1 附件（9 张图、15 秒视频、逐项结果），5 个已有附件保留；11 个文件下载 SHA-256 全部匹配。用户飞书通过 Lark CLI 发送 6 条消息，4 张图及视频下载 SHA-256 全部匹配。见 [交付验证](delivery-verification.json) 与 [视频时序抽帧](bench-video-timeline.jpg)。原始回执和大视频保存在忽略的 output 目录，不提交私人聊天 ID。Basic Room、赵云场景、生产存档与发布配置没有修改。
