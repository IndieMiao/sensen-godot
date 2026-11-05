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
