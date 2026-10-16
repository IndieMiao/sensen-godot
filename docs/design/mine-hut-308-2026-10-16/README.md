# SGODOT-308 · Ivo 的矿口小屋

刘备制作；上官婉儿技术检查、不知火舞画面验收，用户批准后合并。目标分支 `wp-3d-scene`。本包依据 Stark 原图、不知火舞标注和《SGODOT-218 3D 制作清单 v1.1》的 308 节与共同要求制作。

## 朝向与站位复核（v1.2）

按不知火舞 `7383cee8` 和上官婉儿最终补充，`suggested_anchors.npc_ivo.yaw_degrees` 改为 **160°，朝屋里**。Ivo `(1.40,0.082,-0.84)`、stand_ivo `(0.80,0.082,0.05)`、spawn `(0,0.082,2.55)` 坐标均保留。正式 anchors 和初始镜头参数未改。

实测发现 v1.1 厚毯盖住了 stand_ivo 脚下，因毯子无碰撞体，原物理测试不会报错。本轮补实际网格投影检查，并把同尺寸毛皮沿 +Z 移 0.57 m，轴心从 `(0,0.084,0.65)` 改为 `(0,0.084,1.22)`；同步重烘焙房间 AO。没有缩小毛皮、改变站位或增设通行阻挡。

| 挂点 | 距毛皮实际外缘 | 扣除 0.25 m 脚圈后的净空 |
|---|---:|---:|
| npc_ivo | 1.195 m | 0.945 m |
| stand_ivo | 0.311 m | 0.061 m |
| spawn | 0.317 m | 0.067 m |

两面墙新增木柱与托架对三个站位的实际网格投影均留足 0.25 m 脚圈加 0.03 m 余量；站位的真实角色胶囊无碰撞，Ivo 名字条预留盒仍为空。矿口 blocker、27 个碰撞体、6 盏局部灯、材质发光和所有相机参数沿用 v1.1。

本轮 1,243 项几何检查与 170 项 Godot 检查，共 **1,413 项通过**。全部 45 件局部网格与 v1.1 对比保留，只有毯子摆位、Ivo 朝向及随摆位重烘焙的图集/UV 更新。最新补图为 `SGODOT-308_MINEHUT_v1_2_ivo_yaw160_43deg_360.png`、`SGODOT-308_MINEHUT_v1_2_standing_clearance_top.png`。俯视绿色圈表示真实 0.25 m 半径脚圈。`validation.json` 更新为本轮结果，`media-manifest-v1.2.json` 记录两图哈希；旧 v1.1 图片及暖光开关验证保留作该轮证据。

## 画面 v1.1（本次增量）

按不知火舞 `abb59b28` 的五项反馈修订，房间 6.8 × 6.4 m 不变：

1. 矿道从墙后延伸 2.50 m（含末端封板实测约 2.53 m），有连续石壁/拱顶、枕木和铁轨、暗暖提灯，沿纵深逐渐变暗。采用逐渐收窄的下行矿道，末端下降 1.00 m、断面收至 40%（轨距不变），让 43° 视角下洞体藏在墙后，不出现墙外黑壳。矿车和交叉木撑保留；洞口左右、上沿加密石块与横梁。此取舍写入 PR，洞口独立 blocker 完全沿用 v1。
2. 两面墙增加四根木柱与成对弧形托架，并在 layout 给四根柱脚补局部碰撞盒；不进入 Ivo 名字条预留空间。
3. 墙色转暖桃，降低均匀环境填充，增强四盏提灯和烤台的暖橘局部光，墙和地面出现暖晕。洞内增加一盏暗灯。环境/太阳仍仅在审阅脚本配置，局部灯仍由原装配脚本读取 layout。
4. 毛皮改为约 2.6 × 2.0 m 的闭合厚软垫，厚约 0.11 m，白底浅棕斑，圆润毛簇边缘；实际含毛簇外缘尺寸见 validation。
5. 烤台增加 0.98 × 0.60 × 0.21 m 石砌底座，炉体及炉炭同步抬高 0.21012 m；底座与石板间隙 0.12 mm，炉脚接触底座。

原 `mine_hut_art.gd/.tscn` 装配代码保留。本轮重新核验所有 layout 灯、材质发光覆盖、每件 collider、前沿两段边界、右切面边界及矿口 blocker；不用整合到游戏后才发现漏项。与五项反馈无关的 38 件局部网格逐一和 v1 比较，双向顶点距离小于 0.01 mm。新图前缀 `SGODOT-308_MINEHUT_v1_1_`，旧 v1 图保留作对照。

## 交付

- 新套件：`assets/rooms/mine_hut/`；地台 6.8 × 6.4 m，地面顶面 Y=0.082 m；Y 向上、+Z 向前，真实米制，导入 scale 1。
- 100,191 三角面、45 个 GLB / 45 个 surface，单张 2048² `room_albedo_ao.png`；每件一个合并 mesh、一个 surface。45 个材质槽共用同一图集，装配后 7 个材质变体；发光提灯和炉炭由场景覆盖材质。面数不含审阅角色及阴影重复绘制。
- 编辑源：`tools/art/source/mine_hut/mine_hut.blend`，分 KIT 集合、命名部件；`reuse_provenance.json` 列出复用来源、缩放、移除的旧内容和依赖版本。
- 独立艺术场景：`scenes/mine_hut/mine_hut_art.tscn`，只装配房间、碰撞和局部灯。没有账号、存档或网络依赖。
- 新墙体、木板地面、岩石矿口、交叉木撑、铁轨与载石矿车；两条盐烤鱼的金属炉；四盏提灯；分拣台、铜锈绿石、石英、料箱；镐加短斧、线条坑道图、盘绳、平底锅、蒜和干草；毛皮毯、麻袋、石阶和无字交叉镐招牌。

## 复用与取舍

- 复用 blacksmith_shop 的 `back_tool_bench`、`metal_ingot_crate`、`left_floor_crate`、`quench_barrel`、`forge_stool`、`stump`、`forge_lantern`、`lantern_glow`、`right_wall_shelf` 的具名 Blender 部件；换色后统一烘入新图集。新做的 `room_shell` 不来自旧套件。
- 木桶原件 5,528 面，煤桶原件 7,400 面，因此选择木桶，去掉水面后装石块；原石锭箱移除旧内容。工作台横向放大 1.16 倍、深度 1.07 倍以容纳三格料盒；仍保留原件各命名部件。
- 墙挂安全帽直接使用 farm-dev `ef70f8052cf547407eaa09fd881839bf2df929e3` 的 `hairhat_npc_ivo_scene.tscn` 网格及贴图，只移到挂墙轴心，另加小挂钩。验证包含原网格全部顶点的对应检查，不能用相似帽替代。
- 保留参考稿橘棕木色、暖米色墙；矿石采用矿口参考中的灰绿，增加不知火舞指定的铜锈绿。四盏灯、烤台和洞内灯为暖橘局部光，环境与主光采用 v1.1 参数。`lighting-validation.json` 用同镜头开关局部灯的实际像素验证墙地暖晕；旧 `colour-validation.json` 仅记录 v1 色块，不作为 v1.1 配色约束。完整画面仍交美术验收。
- 可读性与真实尺寸优先：360×800、43° / yaw 45°、6.72 m 的游戏取景保持比例，边缘会裁切。另交 12.4 m 全景（360 宽和 1200×1000），不以缩小模型冒充完整游戏取景。

## 接入建议

仅 `npc_ivo` 和出口可点；矿口和炉子为布景。矿口有独立实体阻挡，不能进入。下列世界坐标已写入 `layout.json.suggested_anchors`，场景提供 `suggested_*` Marker3D。正式 `mine_hut.anchors.json` 仍由程序编写。

| 建议挂点 | 世界坐标 X, Y, Z（米） | 朝向 |
|---|---|---|
| npc_ivo | 1.40, 0.082, −0.84 | yaw 160°，朝屋里 |
| stand_ivo | 0.80, 0.082, 0.05 | 0° |
| spawn | 0, 0.082, 2.55 | 0° |
| exit | 0, 0.082, 3.08 | 0° |
| badge_exit | 0, 0.70, 3.08 | 0° |

Ivo 审阅造型：`hairhat_npc_ivo + mask16_npc_ivo + cloth1_npc_ivo + shoes3`。名字条预留盒中心 `(1.40, 2.18, −0.84)`，尺寸 `1.0 × 0.55 × 0.65 m`，已检查不被房间网格占据。

## 验证与图

v1.1 交付有 1,223 项几何、174 项 Godot、3 组暖光像素检查，共 1,400 项通过。`validation.json` 汇总实际 GLB、Godot 导入、物理碰撞及局部光开关结果；`media-manifest.json` 记录 12 张 v1.1 交付图尺寸和 SHA-256。

- 实际导入面数、surface、尺寸、UV 范围和 2048² 图集；每个 GLB 的 `.import` 都为 `gltf/texture_map_mode=1`。
- 全部道具两两实际三角面交叠检查，含主动制造穿插的阳性对照。墙柱与地基、岩石与墙洞、小挂钩等装配接触逐项记录；道具无未说明的穿插。提灯、凳子和料盒用实际网格向下射线量支撑间隙，≤1 mm 且不贯入。
- 每个 UV 顶点和三角形中心不采到空黑图集。v1.1 因结构调整重新烘焙整张图集；烘焙后的边缘填色仅扩展空黑 texel，不覆盖本次有效像素。保留已有 GLB 的导入 UID，避免重新生成资源标识。
- 矿道末段用 576 条向外径向射线检查真实 GLB，衬壁全封闭，无向背景漏空；末段与封板重叠接缝，并人工复看洞口/纵深近景。
- Godot 使用半径 0.25 m、总高 1.745 m 的胶囊体实际扫掠，矿口先撞到独立阻挡；出生点至中央、Ivo 接近区和出口接近区通过。
- Vulkan Mobile / AMD Custom GPU 0405（RADV VANGOGH）窗口渲染。当前没有连接的 Android 测试目标；此包不声称 Android 输入、实体手机性能或整合后的完整游戏验收。

审阅图均带 `SGODOT-308 / LIU BEI` 署名，v1.1 前缀 `SGODOT-308_MINEHUT_v1_1_`：游戏默认取景、完整全景、矿道口、分拣台、Ivo 站位；另附 360 宽全景、Ivo 低视角、烤炉近景、俯视、下行矿道细节、关灯对照和参考对照。

## 复现

仓库依赖须包含上述 farm-dev 提交；工具版本 Blender 5.2.2 LTS、Godot 4.7.2。`output/` 与 Blender 源目录保持 `.gdignore`。顺序执行：

```bash
python tools/art/prepare_mine_hut_308.py --helmet
blender -b --factory-startup --python tools/art/build_mine_hut_308.py
python tools/art/prepare_mine_hut_308.py
blender -b --factory-startup --python tools/art/verify_mine_hut_308.py
godot --headless --path output/minehut-308/project --editor --import
godot --path output/minehut-308/project -- --anchors
python tools/art/package_mine_hut_308.py --anchors
```

最后两步需要真实窗口环境、Pillow / NumPy。省略 `--anchors` 可重拍完整 v1.1 视角集合（使用当前 yaw 和毯子位置）。审阅脚本通过 SubViewport 生成准确分辨率，导入与碰撞验证保存在独立的 `output/minehut-308/`；不使用生产存档。
