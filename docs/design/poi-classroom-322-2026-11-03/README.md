# SGODOT-322 N4 Classroom 细模 v1

赵云，2026-11-03。白模与黄忠 7 件已获上官婉儿、不知火舞通过（322 `a055e512`、`330d4474`）；本轮交基础款细模技术和画面检查。分支 `wp-3d-scene-zhaoyun-poi-classroom`，草稿 PR #690 → `wp-3d-scene`，等待验收及用户批准，不合并。

## 内容与来源

- 公共壳、窗及原碰撞文件完全不改：6.8×6.4 m，墙高 3.7 m，地面 Y=.08；房间实例用 `shell_atlas` 替换图集。
- 一张 2048² `room_albedo_ao.png`，保留 hall 固定色块和 UV。墙 E8D8C0、木地 CF9B66、家具 E5C6A0、书本蓝 487594；鼠尾草绿 939D83 从主图方向补定，317 四色色板未单列。`atlas_skin.json` 记录全部色块。parquet 区按 R3 换成原创直木板纹样，保留地板 UV 的 90° 旋转，没有照片纹理。
- 课桌由 Basic Room `KIT_dining_table` 的四腿、四围板及一块桌面板改制：1.02×.58 m，桌面高 1.13425 m。圆凳用 `KIT_chair` 前腿和横撑，删靠背、另制圆座，直径 .48 m，座面 .715 m。
- 高书柜、右储物架、两矮柜、两展示搁板用 `KIT_wall_shelf` 的板和托架改制。高柜 2.30 m，顶部不摆物；上层展示两幅无文字图画，下层摆书与小盆栽。
- 吊灯复用 coffee_shop 的 cream bell pendant；壁灯复用 SGODOT-324 的 opal wall_sconce，固定源副本在 `tools/art/source/poi_classroom/dependencies/hallkit_324.blend`。五盆小植物取 `_shared/plants` 的 peace_lily，等比 .30、几何叶轮廓，映射本房图集，无第二张植物图集。
- 11 个自有细模 GLB，每件一个 `_mobile` 网格、一个 surface。每件 `provenance/<name>/reuse_provenance.json` 记录源集合、SHA-256、改动与面数；总表 `reuse_provenance.json`。
- 黄忠 `props/` 全目录与 `350bd1f1` **逐字节一致**：7 模块、9 实例、2,850 三角形。包括原导入文件与顶点色材质，未重绘或统一覆盖。地球仪使用 `prop_manifest.json` 的 `globe_mount`；GLB 本身不含该空节点，装配时按清单创建再挂载。黑板和招牌保持空白。
- 原白模文件保留作历史对照，细模 `layout.json` 不引用任何 `blockout_` 模型。

## 预算与结构

实际摆放 **74,286 三角形 / 45 surface**，含公共壳，排除审阅玩家；其中五盆植物 4,730 三角形。18 个最终独立 GLB（11 自有 + 7 黄忠），单张房间图集。玻璃仍为共享壳独立透明 surface。所有最终 GLB 的 `.import` 有 Godot 生成 UID、`gltf/texture_map_mode=1`。

装配场景仅含艺术、局部灯、简单碰撞及挂点，环境、太阳和相机由消费场景提供。原壳地面、墙、开放前沿边界碰撞全部保留；新增家具按 layout 生成碰撞。六盏无阴影局部光为两壁灯、两吊灯、两窗漫射补光；一盏方向光、单级 4096 阴影，接触 AO 存自有网格的灰度 COLOR_0。

## 空间与坐姿

白模桌凳位置、spawn、exit 和六座挂点均保留。`seat_desk_1..6` 的 Y=.795（.08 地面 + .715 座面），yaw=0 朝后墙，含家具 module 与站立接近点。`sign_door` 可写区 **1.30×.28 m**。没有 NPC/use 挂点；软垫只是布景。

| 通道 | 净宽 |
|---|---:|
| 中央 | 1.13 m |
| 阅读角 | **.74 m** |
| 左柜旁 | 1.61 m |
| 右侧 | 1.23 m |
| 讲台前 | .7785 m |
| 前沿 | .82 m |

0.25 m 半径 / 1.745 m 高胶囊核六座、出口和 16 个站位；0.35 m 核主通道。实际装配及 P0RoomNav 共 87 项检查通过；151 项资产、UV、尺寸和实际模块包围盒检查通过；103 项实渲检查通过。支撑接触单独声明：书本笔筒、地球仪、石膏件及搁板盆栽。六个原游戏 `sit_idle` 坐姿按原 `.34 m` 坐面下根偏移渲染，未改角色动画。

## 镜头及接入提醒

默认图采用原 `P0Room.use_art("poi_classroom")`、`frame_all()`、P0Ui 安全区及玩家：43° / yaw45° / **6.72 m**，按 360×800 算投影后拍 720×1600。spawn=[2.90,.08,2.50]，cam_default 同位；出口 [.50,.08,2.88]。六桌、黑板、讲台、招牌均完整处于默认宽度内，避开上 100 px / 下 90 px。阅读软垫和内侧书堆在默认视宽可见。

**程序接入需采用 layout.camera.near=.1、far=40（同 N1）。** 当前 farm-dev 基础 P0Room 的 `review_clip()` 忽略 layout 的裁剪值，遇到 shadow 配置即给 far=4000，单级方向阴影因此几乎消失。审阅脚本只把裁剪值设为大厅合同，角度、视宽、玩家跟随取景和位置全部沿用原 P0；投影不变有断言。没有修改公共运行时代码。`clip_comparison.png` 左边保留原 far4000、右边采用 far40，明确交代这一接入依赖。不能把右图当作旧客户端已自动应用裁剪值的证据。

Stark 对照图另外按主图屋檐斜率估计 pitch35° / yaw45°，保持参考比例，供设计比较；它不是默认游戏镜头或严格像素配准。默认图和全景仍为 43°。

## 审阅与复现

前缀 `SGODOT-322_POI_CLASSROOM_v1_`：默认干净/安全区、43° 全景、六座坐姿、俯视标尺、Stark 对照、阅读角/讲台近景、局部灯开关、裁剪范围对照。数据见 `validation-v1.json`、`media-manifest-v1.json`；白模证据和历史说明独立保留。

可编辑 `classroom_detail.blend` 保留自有件命名零件及重复实例，外部壳和黄忠道具由 layout 引用；生成脚本不覆盖其文件。源说明及命令见 `tools/art/source/poi_classroom/README.md`。

Godot 4.7.2 / Mobile Vulkan / RTX 2060，私有 ADB 5099，渲染前检查 GPU 空闲，自己的 Godot 退出后交付。隔离工程、独立用户目录、localhost:9。无 Android/真机性能、多人占座、POI 服务接入或发包结论。
