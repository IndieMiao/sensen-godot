# SGODOT-218 · 通用排屋 facade_generic v2

通用套由连续灰蓝屋顶改为八栋中性排屋，继续复用四个 `facade_generic_0..3.glb`。整墙不同色、相邻檐口错开0.4 m，矮山花/平顶/四坡打断连续屋脊；门窗仍为不可进入的布景，无文字。美术基线 `wp-3d-scene 76a363edf`，草稿交上官婉儿和不知火舞审核，之后由上官做farm-dev整合。未改程序或恶魔岛。

## 画面

- [开场三联：旧金山 / 通用 v1 / 通用 v2](opening-triptych.png)：每列原尺寸360×800，带P0 HUD、完全同机位，没有为展示排屋调远镜头。
- [整场俯视三联](overview-triptych.png)：同一独立美术机位/灯光，1000×1000原图各缩至500×500，长边1500px。不是玩家镜头。
- [通用 v2 远角](far_corner_generic.png) / [全景原图](overview_generic.png) / [开场原图](opening_generic.png)。

P0基于正式farm-dev `80800a3d2`，没有临时改它的房间/据点程序。yaw45°、pitch33°，默认视宽实测 **7.7061 m**（程序按农场人物投影尺度计算；layout.size仍为6.72），开场脚约y600。三列使用同一旧金山据点和本地fixture，只切换审阅实例的艺术变体，因此通用列HUD仍写San Francisco，不代表切换真实城市。v1使用原GLB及原文件映射。桌面Godot4.7.2 / Vulkan Mobile / RTX2060，不是真机/触控测试。

## 色板与面数

| 模块 | 整墙色 | 屋顶 / 色值 | 檐口 | 三角 | 同位置SF最低上限 | surface |
|---|---|---|---:|---:|---:|---:|
| generic_0 | 浅砂 `#C6B38C` | 矮山花 / `#786B5B` | 6.0 m | 4,589 | 5,125 | 1 |
| generic_1 | 红砖 `#AA7E65` | 平顶 / `#926A4B` | 6.4 m | 4,844 | 5,292 | 1 |
| generic_2 | 灰绿 `#969E8B` | 四坡 / `#786B5B` | 6.0 m | 4,588 | 5,125 | 1 |
| generic_3 | 石灰白 `#D9D5C8` | 平顶 / `#926A4B` | 6.4 m | 4,756 | 5,292 | 1 |

暖灰基座/门楣 `#A79C8B`，石色细框 `#E1D8C4`。四文件限制下采用四种整墙色，暖灰用于收边。没有粉、蓝、薄荷墙或二层凸窗。每栋保留原花箱，另配简单门楣、小雨棚或无字底板之一；装饰少于SF。含饰线最高≤6.5 m，主体进深2.5 m，4 m开间内模型宽约3.92–3.98 m形成分栋接缝。

四原型合计18,777三角；八次摆放 **37,554三角**，通用v1为38,880，SF为41,668。每件1 mesh / 1 surface、有COLOR_0顶点色，无新贴图，继续使用原哑光 `market_matte.tres`。[实测预算/UID/包围盒](verification.json) / [逐栋面数CSV](triangles.csv)。

## 骨架、文件表与保全

文件名、数量、局部原点、四份Godot生成的`.import` UID都保留（字符集a–y、0–8），没有新运行时UID。独立Blender检查对比原源：门扇/门框/门楣/门板/气窗/门把、三阶台阶及三组花箱的位置和尺寸完全一致；五扇窗的x和高度相同，仅把上窗外凸深度收回墙面。[源骨架证据](source-bone-check.json)。

原layout远角两栋都用generic_0。按交付允许“文件表变化”的口径，仅把 **西排generic引用0→1、1→2、2→3、3→0**，让转角也不同色、不同檐口高度；北排/SF引用和四文件列表不变。精确diff只有 `assets[facade_west_0..3].variants.generic` 四个字符串；除此之外layout逐字段完全一致，包含摆位/TRS、colliders、bone_contract、anchors、camera、navigation、boundaries、spawn、bench、instances与city_backdrop。源layout生成器同步四项映射，没有整场重排。

88份非目标房间资产/场景文件逐字节保留，包括SF、材质、所有`.import`、两变体远景及导航快照。运行时只变四个generic GLB、layout四个引用、shell_asset_stats四条统计。

## 验证

- 无缓存的独立集市艺术场景与所引用依赖项目：**247份输入、0 ERROR、0源文件改写**。SF/generic各8个单surface立面装配成功，碰撞形状/变换相同。此为本场景依赖项目，并非整仓未使用的FBX/Blender原料冷扫。[冷导入记录](cold-import.json) / [日志](cold-import.log)。
- 从三套实际碰撞重新构建运行时导航，**11,449格逐格一致、7,371格可走**；出口、所有交互站位、两个座位approach均可达。[运行时数据](runtime-review.json)。
- 当前原版 `tests/p0/test_p0_outpost.gd` **52项全过**，0错误/失败/跳过，含城市选择、开场、居民和座位顺序；没有改测试。[XML](gdunit-results.xml)。
- 四个GLB实际三角数均低于每个对应SF摆位，预算/材质/UID/骨架及非目标文件保全检查通过。

所有Blender/Godot调用都经共享 `flock ~/gs66-render.lock`，执行完退出。未做真机性能验收。

## 源与复现

`tools/art/source/market_plaza/market_plaza.blend` 保留命名墙、完整屋顶、贴墙窗、门、台阶和花箱；`generic_facades.py`定义配色和屋顶。`--generic-only`只导出四个generic GLB，其余资产统计保留。

```sh
flock ~/gs66-render.lock blender --background --factory-startup --python "$PWD/tools/art/source/market_plaza/build_market_plaza.py" -- --generic-only
python3 tools/art/source/market_plaza/verify_generic.py
```

`prepare_generic_review.py`建立output内的固定程序基线、独立用户目录、离线fixture审阅项目，只叠加艺术文件并逐字节核对程序；`generic_review.gd`拍三联/远角并重建导航；`verify_generic_import.gd`验证两套装配。源码目录已有`.gdignore`，不会污染游戏类扫描。
