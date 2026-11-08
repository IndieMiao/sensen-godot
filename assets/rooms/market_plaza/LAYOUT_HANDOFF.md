# SGODOT-218 集市广场布局交接

作者：马可波罗。美术场景 `res://scenes/market_plaza/market_plaza_art.tscn`；布局以本目录 `layout.json` 为准。方案 v2.1、33°、排屋 C、a8/a9 背缝封闭已落实。当前为整场交审，未接入正式 P0。

## 坐标与镜头

- 米制，Godot Y-up，房间原点中心，X/Z ∈ [-8,8]，地面 Y=0.05，+Z 朝前。
- 模型正面 +Z；模型 yaw 使用 Godot Y 轴旋转。P0 人物朝向锚点按程序 -Z 约定，Mei/居民 yaw=225°，柜台站位/出生 yaw=45°。
- 正交 yaw=45°、pitch=33°、屏宽=6.72 m。layout.camera 记录艺术镜头；P0 接入须保持该数值，不能再套旧 FarmCamera 43°/宽度补偿。
- 近侧草地到 x/z=18，超出边界10 m；人行道和路沿承接地面。三盆树仅在远角和侧角；入口门柱旁低盆不超过1 m。

## 依赖与变体

SF排屋已按复审更新为八栋五色、0.4 m凸窗、6.0/6.4 m错落檐口及暖色独立屋顶；通用套和碰撞骨架保留。详见 [v2审阅](../../../docs/design/market-plaza-218-2026-11-08/v2/README.md)。


黄忠 PR #877 成品头 `288b47b94f966981603b3d132552d6b16f923303` 已通过件本身技术检查，整场审阅已取这个头的真实模型。请将 #877 与本 PR 一起集成。这里不复制其文件或修改遮阳；其件未在目标分支时自动加载本目录尺寸占位 GLB，不能把占位当作已完成成品。

共享地面材质复用428，低花槽/灯/长椅复用 street_kit，城市卡复用434，特产箱复用 fruit_shop/floor_fig_crate。锚点相关的模块保持 art 根直接子节点，兼容 P0Room 的 module 可见性查找。

`market_plaza_art.city_variant` 可选 `san_francisco`（默认）或 `generic`，切换八段排屋和独立 CityBackdrop 节点。两套开间、门窗、台阶、花箱、碰撞骨架一致；每段结构4 m开间、2.5 m进深，两层约6.5 m，顶面/背面封闭。SF使用蓝/粉/奶油/黄色与维多利亚线脚，通用套中性色、少量线脚简化。装饰檐口、台阶会超出结构包络；独立顶点测量见审阅包。没有3D文字。

## 锚点合同

以 layout.anchors 的数组为完整合同，共20个。柜台只用 `use_counter / stand_counter`，不含 `use_stall_1 / stand_stall_1`。`stand_counter` 与 `stand_keeper` 同点 `(3.25,.05,3.25)`。六个普通摊/花车仅布景，无 use/stand 锚点。

特产箱 `use_specialty_shelf=(4.2,.7,1.1)`、`stand_specialty_shelf=(4.7,.05,1.6)`；委托板 `use_market_board=(1.1,1.8,4.2)`、`stand_market_board=(1.6,.05,4.7)`。Nadia/Tomo共用位置，Theo在工具摊前，均不坐长椅。

两张长椅的 seat 顺序固定 `[seat_1, seat_2]`，锚点Y是实际共享长椅坐面 `.768`（含地面高度），P0按自己的坐姿根偏移处理；approach位于朝喷泉一侧，已在运行时导航核可达。

## 碰撞与导航

P0RoomNav 每次开场从真实场景碰撞体重建导航；`navigation_snapshot.json` 是交验快照，不替代运行时重建。快照含 layout SHA-256、0.15 m格宽和0.21 m人物半径，107×107格中7371格可走。

按a9，小摊占地和遮阳保持不动。各小摊本地后方 `RearServiceGapBoundary` 封住排屋之间的背面/侧面窄缝（2×3×2.4 m，无可见网格）。Mei后方使用可见低花槽，真实模型高0.445 m，封闭喷泉和Mei之间窄带。其余喷泉弧路、入口左/右两条绕行路线都可达；旧“Mei背后保留1.8 m通道”已由a8/a9替代。

0.5 m网格、胸口1.0 m/头顶1.6 m，真实导入遮阳三角形和树冠检测：669个可走站位，0遮挡。原诊断754个站位有47处遮挡；导航8284→7371格，新封913格、新放开0格。**固定 NPC Mei不在可走导航上：脸可见，但其1.6 m头顶射线仍命中原掌柜遮阳**；锚点/模型遵照指示保留，已在图中单独标注交审。

## 程序接入清单（本 PR 未改）

1. `p0_outposts.json / sh_market_1.art` → `market_plaza`；bounds → `[-8,8,-8,8]`。
2. 清空旧 `anchors` 外部覆盖文件，或将其同步为这份新锚点；否则旧集市坐标会覆盖 layout。
3. seats → `[seat_1, seat_2]`，顺序与layout一致。
4. 服务端房间范围同步16×16 m；城市切换时设置 art.city_variant。
5. 应用已定33°、45°、宽6.72 m的室内镜头。审阅临时补丁留在忽略的 output 中，不提交。
6. 更新 test_p0_outpost 中旧 fruit_shop/旧外部锚点/旧镜头与边界断言。此次原测试31项中30项通过；一个用例有7个旧合同断言失败，未修改测试去消除差异。

完整证据：[整场审阅](../../../docs/design/market-plaza-218-2026-11-08/README.md)。
