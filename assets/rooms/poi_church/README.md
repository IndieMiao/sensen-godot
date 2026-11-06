# SGODOT-423 · Grace Cathedral · 教堂室内 v1

黄忠制作。第一版仅对应旧金山 Grace Cathedral；使用批准的教堂概念图作为造型参考。
装配入口 `res://scenes/poi_church/poi_church_art.tscn`，所有位置和交互挂点读取 `layout.json`。

房间 10.5 × 10.5 m，主地面 Y=0.08 m；石墙约 5 m，深色拱顶 / 木梁带延至约 8 m。
两面前墙按设定剖开，外沿台阶、墙基座和低草坪补齐默认镜头四角。
`cam_default` 为 43° 俯角、45° 方位、6.72 m 正交宽度，固定镜头；与茶馆和农场人物比例一致。
草坪是实际几何地面，不是面向相机的背景板。

两列各四排木长椅；8 个 `seat_left_1..4` / `seat_right_1..4` 挂点，坐面距主地面 0.715 m。
每个座位带所属 module、朝向和 approach，消费端只显示 i-seat 图标，不写座位名称。
入口在屏幕左前方：`spawn`、`exit`、`badge_exit`，后者供 i-door + `Map` 名字条使用。
中央通道 1.60 m，排间净距 0.85 m，入口净宽 1.40 m；实测和碰撞验证见审阅文档。

祭坛三级台阶为布景，包含白布桌、蜡烛和花架；没有 NPC 服务位或新的玩法。
彩窗只有花纹和几何色块；玫瑰窗、挂旗和桌布使用四叶纹，不画人物或十字。
迷宫为低对比、比地砖深一档的同色系石纹。地面彩光为宽色块平面，alpha=0.28，无实时投影。
两盏铁艺吊灯的暖光写入 `local_lights`，照茶馆装配成不投影的 OmniLight3D。

所有 GLB 各为 1 surface、外链同一张 2048² `room_albedo_ao.png`；原点保留模块的地面/安装轴。
Blender 编辑源和生成脚本：`tools/art/source/poi_church/poi_church.blend`、`tools/art/build_poi_church.py`。
每件 mesh 命名 `<件名>_mobile`，`.import` 的 UID 由 Godot 导入生成，texture_map_mode=1。
资产模板带 `review_only=true` 时只供实例引用，预算只统计实际摆放。

审阅材料：`docs/design/poi-church-423-2026-11-05/`。
这份是美术资产与装配交付；POI 数据、路由和正式 P0PoiRoom 接入由后裔 / 哪吒负责。

## v1.1 · 通道地毯与跟随取景补带

在已合并 v1 上增添三个模块，既有 20 个 GLB 和全部 `.import` 字节不变。
`layout.json` 只新增资产条目并更新 revision；原来的 assets / instances、8 个座位、
spawn / exit / badge_exit / cam_default、camera、boundaries、local_lights 和通道数据逐项不变。

- `aisle_carpet`：1.20 × 5.59 m，厚 0.004 m，顶面 Y=0.087，比地砖高 7 mm；
  沿通道 v=-2.84..2.75 m，距迷宫外圆、祭坛第一阶各 0.06 m，无碰撞、不投影。
  低饱和暖赭色 #986D61，使用原 2048² 图集中未被旧 UV 使用的 16×16 像素区
  (1896,124)..(1911,139)，旧 UV 周围另留 4 px；其余图集像素完全一致。
- `vault_extension`：原 layout 的两面实体墙名为 `north_wall` / `west_wall`。
  原墙不动；上方深色拱顶实际向室外退 2 m，带宽从 10.9 延到 14.9 m（两端各 2 m），
  用斜木梁顶带与原墙冠相接。后侧最高点 Y=11.58 m，保证竖屏跟随停稳时上角覆盖。
  这是实际固定建筑几何，不是跟随相机的卡片；无新增碰撞、不投影。
- `grass_extension`：跟随到最外侧角落时，旧 27 m 草坪在下角仍有小缺口；补一层 30 m
  草坪外缘，顶面 Y=-0.70，比原草坪低 3 cm，原草坪保留。无碰撞、不投影。

摆放后 **107,454 三角面 / 40 surface**；植物 **16,984 面**。口径为非 review_only 资产
加 `instances` 的实际次数，单件模板只算入 unique；详见 `asset_stats.json`。
所有新 GLB 各 1 surface，共享原单张图集，新增 UID 由 Godot 4.7.2 导入生成。

本次按“只改 assets/rooms/poi_church”交付，新增源、脚本与审阅材料也收在此目录：
`_source_v11/` 为命名可编辑 Blender 源及生成/验证脚本，`_review_v11/` 为原生截图和验证结果；
两目录带 `.gdignore`，不进入运行时资源导入。

复现：先运行 `_source_v11/prepare_increment.py`（Python + Pillow），然后在共享锁下运行
`blender --background --python .../_source_v11/build_increment.py`，再执行 `measure_assets.py`。
`prepare_increment.py` 固定读取 provenance 的 v1 基线，不覆盖已生成 UID。
审阅用 `prepare_review.py` 建独立工程，所有 Godot 导入和渲染都加
`flock ~/gs66-render.lock`，通过 `res://review.tscn` 出图；导入生成的新增 `.import` 再拷回。
`verify_increment.py` 核对 GLB、预算、旧资产哈希、layout 不变项、图集空白区与地毯净距。

验证：171 项资产检查、157 项 Godot 检查通过，包含原通道/座位 approach 的胶囊检查。
默认镜头、四角（X/Z=±4.70）、右盆栽回归点和 5×5 跟随位置网格（X/Z=±4.85 范围），
合计 31 个视角各做背景色→洋红对照，整幅 360×800 均为 **0 像素差异**，四角均无露底。
默认沿用 layout camera；跟随图取玩家停稳后的脚下中心（Y=0.08），角度/屏宽不变。
NW 角在原祭坛背后，人物受原布景遮挡，名字条标记位置；未改动原布景以遮掩这个情况。

截图来自独立 Godot Mobile/Vulkan 工程和真实资产/默认角色；名字条为审阅标记。
这是美术覆盖与通道验证，不是已接入的 P0PoiRoom 服务端/UI、手机性能或发布验收。
