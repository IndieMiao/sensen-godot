# SGODOT-319 公共大厅壳 + N1 酒店大堂 v1.1

赵云 · 初版 2026-10-31，返修 2026-11-02。壳已获上官婉儿技术通过（319 `5fe1b06c`，PR #594 `3aa23466`）。本次将技术复审与画面验收的六处返修合为一个 v1.1 增量，PR 保持草稿，未合并，等待复核与用户批准。

## 2026-11-02 返修

根据 #594 评论 6560650776 / Plane 319 `75affd0f`：20 个新 `.import` 经 Godot `--import` 重新生成并回写 `uid`，ConfigFile / ResourceUID / ResourceLoader 校验全部通过；保留 `texture_map_mode=1`。原流程在导入后再次准备工程时覆盖了导入结果，现用 `prepare_hotel_lobby_319.py --project --import` 在校验后立即回写，打包也拒绝 UID 缺失或与校验记录不一致的元数据。

横匾外框改为 1.68 × 0.30 m，可写区改为 1.60 × 0.22 m，挂点位置不变。按不知火舞 `319 1db13376` 和上官婉儿最新派活，四张 N1 边桌改为直径 0.70 m、离地高 0.90 m，灯具及其局部光一起下降 0.23425 m；324 原件不动。地毯改为中饱和森林绿，金边提亮；壁炉改暖中灰，烟囱改成四层错缝石块，两层台板均减薄到 0.08 m，摆件支撑高度不变。

spawn 及 cam_default 移到前沿右侧 (2.85,0.08,2.35)，exit / badge_exit 同步移到 X=2.85。未改相机程序；原生 P0 仍跟随出生位置、保持 43° / 6.72 m。电梯门、三钟、钥匙墙和横匾的投影包围盒均完整落在 360×800 的安全画面内，胶囊重测通过。

本版只重导边桌、壁炉、壁炉台和横匾四个 GLB，其余 15 个保持字节不变；共享图集、324 文件和公共壳不改。可选琴叶榕暂未替换，保留两盆共享橄榄树。返修证据见 `n1-validation-v1.1.json`，默认进门和全景两图见 `media-manifest-n1-v1.1.json`。此前 `v1` 图片与验证记录保留为历史版本，最新结果以 `v1.1` 为准。

## 依据与交付

Stark 的 315 R3 主图、SVG 俯视图和清单保留在 `reference/`；批准记录 `315 9704634d`，不知火舞复核 `3a4547e9`，上官婉儿拆分 `d231c310`。SVG 按 120 px = 1 m 读取，未标高度采用 H=1.745 m 的比例基线。

- 公共壳：`assets/rooms/_shared/shell_hall/`、`scenes/shell_hall/`。
- N1：`assets/rooms/poi_hotel_lobby/`、`scenes/poi_hotel_lobby/`。含 19 个 GLB、逐件 provenance、layout、asset_stats、一张 2048² 图集。
- 源：`tools/art/source/poi_hotel_lobby/poi_hotel_lobby.blend`，19 个 KIT 集合和 398 个具名编辑部件。重复家具用实例，壳及共享植物保留各自源文件，完整装配由 Godot 场景和 layout 复现。

## 正式尺寸

Godot 米制，Y 向上，+Z 为开放前沿；地面中心为原点。以下窗、护墙板、顶线取值已由上官婉儿正式核定。

| 项目 | 取值 |
|---|---|
| 地台 | 6.8 × 6.4 m，底面 Y=-0.28，顶面 Y=0.08 |
| 墙 | 两面，离地高 3.70 m，顶面 Y=3.78，厚 0.20 m；无前墙、门、墙端方柱 |
| 护墙板顶 / 顶线 | Y=1.1525 / Y=3.4625–3.746 |
| 共用窗洞 / 窗台 | 1.24 × 2.04 m / Y=1.20 |
| 两窗中心 | 左墙 Z=-1.78、+1.78，Y=2.22；窗框、三列四行窗格独立 |
| 环形沙发 / 中央花池 | 外径 2.43 m / 1.09 m；六块坐垫 |
| 坐面 | 离地 0.715 m，挂点 Y=0.795；扶手椅及环形沙发一致 |
| 扶手椅 ×2 | 原 324 尺寸 1.50 × 0.89 × 1.326 m，未缩放 |
| 圆边桌 ×4 | N1 副本直径 0.70 m，桌面离地 0.90 m，按 11-02 画面验收定值 |
| 新矮书架 / 白罩落地灯 | 约 0.90 × 0.42 × 1.10 m / 高约 1.90 m |
| 关门电梯 / 行李车 | 约 1.40 × 0.16 × 2.60 m / 0.95 × 0.77 × 1.75 m |
| 钥匙格墙 / 三只挂钟 | 宽 2.21、高 1.30 m，挂装 Y=0.88 / 原直径 0.78 m |
| 空白匾文字区域 | sign_name=(0.62,3.20,-2.92)，size=[1.60,0.22] m；外框 1.68 × 0.30 m |
| spawn / exit / badge_exit | (2.85,0.08,2.35) / (2.85,0.08,2.88) / (2.85,0.55,3.00) |

完整实测包围盒见 `n1-measurements.md`。本版不设前台或收银台，0.66H 台面基线无对应新增设施。装配不带 NPC、文字、UI、环境光、太阳或相机；局部灯和共享炉火随资产提供。

## 家具与通道

保留 324 扶手椅原尺寸和全部 8 座，N1 边桌按新批准尺寸缩小。环形沙发在 (1.10,0.08,0.58)，两扶手椅沿左墙分列，第四圆桌在后排扶手椅旁，其余三桌围绕沙发。最终位置见 `tools/art/source/poi_hotel_lobby/layout_plan.json`。

- 主通道用半径 0.35 m、高 1.745 m 胶囊从 spawn 到电梯前验证，对应净宽至少 0.70 m。
- 8 个座位接近区和 16 个站位用半径 0.25 m 的角色胶囊验证；最小接近区净空半径约 0.355 m。右侧座位的通路仍按角色胶囊验证，不宣称所有支路均为 0.70 m 主通道。
- 16 个站位中心距离至少 0.55 m，均在同一可达区域。这是静态几何容量验证，未模拟 16 人同时移动。
- seat_sofa_1..6、seat_armchair_1..2 均带坐面 Y、module、yaw、stand；yaw 按角色默认朝 -Z 的约定，朝向可走区。
- 家具与重复实例按 layout 生成碰撞；壳生成地面、两面墙及开放边沿的不可见边界；植物使用半径 0.31 m 的简化碰撞。
- 没有未分类几何穿插。线脚安装搭接、贴墙固定、地毯薄层与家具脚接触单列；花池开口有到达土面的射线验证。

## 复用与图集

324 来源固定为 PR #563 的 `104446a2a995c8a0269d12d27308b3d547b29f6e`。准备脚本从 git 取回具名 Blender 源。扶手椅、风景画逐三角形与原件比对，尺寸不变；边桌按 X/Z=0.70/1.10、Y=0.90/1.13425 缩放后逐三角形比对，仍为 240 面。缩放写入 N1 副本顶点，导出根节点保持单位变换；不改黄忠原文件。

邮局提供三盏台灯、三只钟及改成浅挂柜的钥匙格主体；Deluxe 10 提供壁炉、壁炉台、烛台，新增浅石饰面、椭圆镜和小相框。火焰复用 178 的 fx_hearth_fire.tscn。两盆落地植物直接引用共享 olive_tree.glb，中央花池植物另建。牛皮毯为新 316 三角形平面件。

公共 hall_albedo_ao.png 字节不变。hall_palette.json 包含 6 个壳区域、32 个色块、像素及 glTF/Blender UV、16 px 安全边和 324 语义色映射。N1 的 room_albedo_ao.png 沿用同一 UV 布局，壳和家具共用这一张 2048² 房间图集；植物、炉火继续使用既有共享库贴图。

**parquet 区允许换花纹**，N2 可换石砖。地板 UV 已转 90°：世界 X 对应 -V，Z 对应 -U；范围 6.6 × 6.2 m，见 hall_palette.json.pattern_replacement.parquet，无需改变几何。

N1 家具 AO 存在顶点标量颜色，导入和装配启用 vertex color；保留玻璃、画心及植物的 surface 材质。N1 调色为 wood_dark 783B22、cloth_green 中心色 42683A、stone 8C8376；v1.1 地毯底色 567E4A、金边 C4A15B，沙发用的中心色块不变。记录见 atlas_skin.json。无照片木纹、黑描边、文字或家具移动后留下的地面压痕。

## 预算与验证

- 完整装配 **61,770 三角形、38 个静态 surface**；共享炉火最多增加 40 个三角形、2 个粒子绘制，总计最多 61,810 / 40，低于 150k / 50。窗玻璃为独立 1 个 surface。
- 全部 GLB 设置 gltf/texture_map_mode=1，图集启用 mipmaps 与 VRAM 压缩。装配保留各 surface 材质。
- v1.1 的 238 项几何、图集、局部轴心、来源尺寸和穿插检查见 n1-validation-v1.1.json.geometry。20 项 UID、52 项预布置 Godot 导航、75 项最终装配/渲染检查通过，另核原生镜头的六组酒店标识包围盒。
- 白天窗光来自太阳穿过真实窗洞。三盏桌灯、落地灯、炉火共五处局部灯；附同相机开关对比，两个时刻火焰像素变化验证共享粒子运行。
- 公共壳六个网格名改为 <件名>_mobile，只改 GLB JSON，二进制几何载荷哈希不变，记录见 n1-validation.json.shared_shell_naming。
- 仅 gs66 RTX 2060 / Godot 4.7.2 Mobile Vulkan 桌面艺术与碰撞验证，无 Android 输入、手机性能、联机或发布结论。

## 默认镜头与媒体

v1.1 的 entry_360 为 360×800，使用原生 P0Room 在新 spawn 进门后的 **43° / 6.72 m / 跟随玩家**构图。原生导航吸附约 3.54 cm，证据见 native-camera-n1-v1.1.json。图片不画人或 UI，PNG 元数据署赵云，其余审阅板署可见姓名。

原生 P0 的 near=.05 / far=4000 会降低单级阴影精度。本组保持原生位置、方向和宽度，裁面使用 .1 / 40 m；layout.camera 记录推荐裁面与全景相机，程序接入需采用合适裁面。未改 P0Room 或运行时分支，探针临时复制内容已还原，记录在 n1-validation.json.runtime_restoration。

`cam_default` 是位于 spawn 的跟随目标基准，不是相机眼点；role=camera_follow_target，携带 43°、45°、6.72 m 与推荐裁面元数据。原生相机实际眼点和 basis 以探针记录为准。横匾按最新派活使用 sign_name，替代旧卡模板的 sign_door。

6.72 m 视宽自然裁掉侧边，另交 43° / 11 m 不裁切整间全景。10 张 N1 图见 media-manifest-n1-v1.json：全景、俯视、壁炉、钥匙墙、环形沙发、进门 360/720、Stark 并排、灯开关、通道图；前缀 SGODOT-319_N1_v1_。原空壳四面等图及 validation.json 保留为已通过的壳阶段证据。

## 复现

Blender 5.2.2 LTS、Godot 4.7.2，Python 需 NumPy、Pillow、Shapely。用私有 ADB 5099，渲染前检查 GPU，脚本完成自退，只停自己的 PID。保留 output/.gdignore 与源目录 .gdignore。

```bash
source ~/.codex-zhaoyun/env.sh
python3 tools/art/prepare_hotel_lobby_319.py
output/art-setup/venv/bin/python tools/art/make_hotel_atlas_319.py
output/art-setup/venv/bin/python tools/art/check_hotel_lobby_plan_319.py
# 没有壳隔离工程时，先运行 prepare_shell_hall_319.py。
godot --headless --path output/poi-hall-319/project --script "$PWD/tools/art/check_hotel_lobby_navigation_319.gd" -- "$PWD/output/hotel-lobby-319/plan/physics-fixture.json"
blender --background --factory-startup --threads 2 --python "$PWD/tools/art/build_hotel_lobby_319.py" -- --asset=blank_name_plaque,round_side_table,hearth,hearth_mantel
blender --background --factory-startup --threads 2 --python "$PWD/tools/art/verify_hotel_lobby_319.py"
python3 tools/art/prepare_hotel_lobby_319.py --project --import
# 同一 layout 可用已提交的原生镜头记录；改 spawn 或镜头后重跑：
# python3 tools/art/capture_hotel_native_camera_319.py --runtime <干净私有 farm-dev checkout>
# python3 tools/art/prepare_hotel_lobby_319.py --project
nvidia-smi
godot --path output/hotel-lobby-319/project --display-driver wayland --rendering-method mobile --rendering-driver vulkan --max-fps 30
output/art-setup/venv/bin/python tools/art/package_hotel_lobby_319.py --technical-fix
```

生成器会重建源和导出件，手工改源需同步生成逻辑或保存独立版本。无 P2 接入、联机容量验证、APK、生产数据或发布操作。

本次用 `--asset` 指定四个改动模块，避免其他件三角索引排序产生无关变化；完整初建时去掉该参数。
