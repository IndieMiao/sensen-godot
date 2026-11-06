# 矿层摆件 v1

黄忠 / SGODOT-355。米制、Y up、+Z 正面，地面中心原点。均单 surface、顶点色、不投影、无动画、无碰撞。
`.glb.import` 挂现有 `res://assets/monsters/material_import.gd`，保留其 UID 和各 GLB 的 UID。

- `guard_arena.glb`：2,421 面，装配 `(4.9,0,-3.8)`；外框 6.889 × 4.353 m，6.0 × 3.6 m 椭圆净空；碎石 ≤0.23 m，两火把高 1.56 m，石碑高 1.15 m。整件无碰撞，后沿高件在世界 X 3.10–6.55，左后角圆收避开电梯。火把光由程序加。
- `elevator_station.glb`：2,394 面，装配 `(1.25,0,-6.75)`；底座 1.45 × 1.30 m，木板顶 Y=.17，总高 2.24 m，右侧灯柱计入外框后总宽 1.595 m。没有模型灯。
- `PlateAnchor`：空节点 `(0,.99,.515)`，identity basis，牌面朝 +Z，空白牌面 .50 × .30 m；牌面 Z=.510、背板前面 Z=.480，相差 .030 m，文字节点再留 .005 m。
- `LampAnchor`：空节点 `(.8,.73,.47)`，identity basis，程序挂指示灯；1.2 m 灯柱保留。

实际 bounds、尺寸、挂点和哈希见 manifest.json。源与审阅在美术分支 `tools/art/source/mine_kit_355/` 和 `docs/design/mine-kit-355-2026-11-02/mine_props/`。
