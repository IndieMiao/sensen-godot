# SGODOT-424 · 接入与协作约定

当前分支 `wp-3d-scene-makeboluo-alcatraz-424`，场景 `res://scenes/landmark/alcatraz_island.tscn`，运行数据 `assets/landmarks/alcatraz_island/layout.json`。进度以本卡最新提交头为准。

## 时间和分工

- 11-06 12:00：可走白模、逐屏 360×800 图、开场／半山／主楼前的实测预算及俯视。
- 11-08 18:00：黄忠交城市／桥／对岸山丘贴片、灯塔与水塔近远档；主楼远档在取得本分支近档后制作。
- 11-08 白天：赵云交重复小件；每种单网格、单 GLB，局部原点和尺寸沿用本表。
- 11-08 20:00：本分支推可走文件和 layout.json，附整岛图与三个位置预算；上官婉儿转亚瑟接入。
- **11-09 08:00：正式件硬线。** 用户目标 11-09 晚进游戏；vivo 帧率由亚瑟实测，低于 30 FPS 不上线。

马可波罗负责地形、步道／台阶、码头／渡轮、主楼近档、整岛摆位与合成。灯塔／水塔、远景及重复小件目前明确是占位，不当作马可波罗完成的最终资产。废墟内部、花园品种、海鸟动画、渡轮细节和浪花后补。

## 坐标与尺寸

米制，岛中心 `(0,0,0)`；+X 东，+Z 南／码头，-Z 北／主楼，Y 向上。Blender 为 `(x,-z,y)`，glTF Y-up。本地前向 +Z；yaw 绕 +Y，正角把 +Z 转向 +X。主楼正面朝 +Z。请应用源变换，模块以地面／安装中心为局部原点，不烘入岛上位移。

海面 Y=-0.15；码头广场 Y=1；台地 Y=3.25／5.5／7.75；山顶 Y=10。出生 `(-22,1,19)`，出口 `(-23,1,19.4)`。全岛／码头外框 X=[-30,30]、Z=[-20,20]；可走区外框见 `walk_bounds`，实际可走性以 `navigation` 为准。

| 模块 | 世界落点 | 原点／尺寸 | 负责人 |
| --- | --- | --- | --- |
| alc_museum | (0,10,-13) | 落地中心；40×10 m，地上高 9 m；门框凸出前面 | 马可波罗 |
| alc_museum_far | 同近档 | 同枢轴、同轮廓；目前方块 | 黄忠 |
| alc_lighthouse / _far | (-25,10,-11.5) | 落地中心；高 15 m，占位最大直径 3.7 m | 黄忠 |
| alc_watertower / _far | (25,10,-14) | 落地中心；高 12 m，占位最大直径 5.4 m | 黄忠 |
| alc_far_bridge / _far | 以 layout 位置为准 | XY 贴片、底边中心、前面 +Z，当前投影占位宽 2 m／高 0.9 m | 黄忠 |
| alc_far_city / _far | 以 layout 位置为准 | XY 贴片、底边中心、前面 +Z，当前宽 4.8 m | 黄忠 |
| alc_far_hills / _far | 以 layout 位置为准 | XY 贴片、底边中心、前面 +Z，当前宽 8 m | 黄忠 |

远景安装基准 `far_anchor=(-22,-0.15,39)`，即从码头出生点向 +Z 岛外约 20 m。为 43° 正交开场而设置的视觉抬高、投影深度补偿已放在 `FarZone`／`far_card.gdshader`；贴片安装点约 Y=30–31 m，**不是地理海拔**。最终贴片保持局部底边原点，使用 layout 的实例位置，不自行把补偿烘进顶点。材质有 albedo_texture 时预览绑定到卡片 shader；透明贴图保留 alpha。

## 复用小件

`placement_points.json` 给出每个重复件的名字、asset、zone、position、rotation_degrees、scale；同种只引用一份 GLB。`layout.instances` 是同一表的副本。预览按区块／类型生成 MultiMesh。

| 名称 | 占位约定 |
| --- | --- |
| alc_bench | 1.5 m 长、座面 0.45 m，前向 +Z |
| alc_lamp | 3.5 m 高，落地中心 |
| alc_rail_straight | 标准长 2 m，沿本地 X，高 1 m，底部中心 |
| alc_rail_corner | 底角原点，向 +X／+Z 各伸 0.5 m，高 1 m |
| alc_curb | 标准长 2 m，沿 X，高 0.16 m、宽 0.18 m |
| alc_tree_a / alc_tree_b | 高 3.4／4 m，占位冠宽 1.8／2.2 m |
| alc_flowerbed | 1.4×0.7 m，高 0.55 m |
| alc_bin | 0.45×0.45 m，高 0.75 m |
| alc_sign | 杆高 1.3 m，牌宽 0.9 m／高 0.45 m，正面 +Z |

大部分实例使用普通 TRS。台阶斜栏杆／石沿另有 `basis_columns` 三列，直接构造 `Transform3D(Basis(col0,col1,col2), position)`；它沿长度方向加入高差，保持立柱竖直。`slope_rise_m` 表示此段两端高差。给出的 rotation／scale 保留平面朝向和水平长度，**有 basis_columns 时应优先使用矩阵**，不能只按 TRS 让立柱整体歪斜。Blender 源中的实例与 Godot 都使用同一矩阵。其碰撞用保守盒体，不给物理体施加 shear。

## layout.json 及加载

- `camera` 按茶馆格式提供 position／target／size，另带默认 zoom=1、最远 3 倍（20.16 m）与平移范围。默认投影 43°／14.5° 不变；上官已确认最远端转为 60° 斜向，容纳主楼正面的大半和灯塔。
- `spawn` 为三维坐标；`anchors` 为 name／position／yaw_degrees 列表，包含 spawn、exit、badge_exit、cam_default、far_offshore。
- `boundaries` 采用 size／at／name；`walk_bounds` 仅是外框，不能把框内花园当作可走。高程导航在 `navigation`，分区多边形在 `zone_polygons`。
- `DockZone`、`TerraceZone`、`SummitZone`、`FarZone` 是四个独立节点。前三者各有碰撞／导航，连接同一私有地图；每区地形＋步道＋台阶离线合为一个静态地面 GLB（alc_ground_dock／alc_ground_terraces／alc_ground_summit），以压低 draw call。重复件仍是独立原型，未焊入地面。FarZone 无交互碰撞。
- `assets` 是模块及负责人／占位标记；`instances` 是重复件表；`placements` 是本预览的完整装配表。接入时二选一装配，不要把 placements 和 instances 重复实例化。
- `lod_groups` 提供六组 near／far 文件和 visibility_range 建议；近远档同原点。预览在 55 m 硬切换、两侧 margin=0，避免近远档之间消失；远档不投阴影。实际阈值和阴影距离由亚瑟确定。占位阶段路灯／垃圾桶／指示牌／石沿／栏杆小转角／低花坛／渡轮／海鸟不投影，主体、树、长椅和栏杆仍投影；预算按此状态报告。
- Godot 的默认 4096 导航搜索多边形会截断岛上长路线，预览按当前导航规模设置查询上限并检查真实到达。无需更改共享玩法代码。

只改文件内容而不改模块名／原点／尺寸时，可直接替换占位 GLB，点位不变；重新导入后保留 Godot 自动产生的 UID，并重跑屏幕预算和导航。更改尺寸须先检查实际通道与相邻物体。正式导出至少包含 layout.json、全部 GLB 和两份 shader；点位表／manifest 随交接保留。地图入口、导出清单与 vivo 性能验收由亚瑟接入，不由本美术分支发布。
