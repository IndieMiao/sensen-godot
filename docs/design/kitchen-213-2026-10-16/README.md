# SGODOT-213 · Basic Room 三口灶角

刘备，2026-10-16。依据 Stark 第二版、[不知火舞标注](reference-huowu.png) 与 SGODOT-218 3D 制作清单 v1.1 的 213 节；[原图](reference-stark.png) 只参考造型。只交 wp-3d-scene 审阅；上官婉儿技术检查、不知火舞画面验收、用户批准后合并。

以三个并排炉眼替换原高烟囱壁炉，移除 layout 中的旧 kettle，增加左墙调味架及无字红封面菜谱书。墙、地面、窗、门、长凳的 GLB 与 layout 条目逐字节保留；anchors 未改。书的封面为 0.35 × 0.45 m；挂绳另计。调味架 0.60 m 宽、四罐，固定原位置与朝向。

## 落位与接入

- `kitchen_range_3.glb`：原点为灶体地面中心，+Z 朝前，scale 1；layout 位置 `(-2.05, 0.082, -2.53)`、yaw 0。相对旧 hearth 向前 4 cm，给后墙踢脚线留净空。砌体 1.35 W × 0.60 D m；锅的支撑平面 local Y=0.898 / world Y=0.980 m。整件含排烟管的尺寸见 validation，不能把排烟管高度当灶面高度。
- 水槽原网格不改，向 +X 移 0.14 m 到 `(-0.33,0.082,-2.62)`；台面用具、其上原 wall_shelf 和 shelf_plant 同移 0.14 m。水槽顶板与新灶水平净距 0.06 m；上方旧搁板随水槽移后完全处于新灶 X 范围之外。三口灶上方不加搁板。
- `spice_rack.glb`：`(-2.83,1.72,-1.575)`、yaw 90、scale 1。它已在新 layout 中，接入时须移除旧 anchors 中 `from: wall_shelf, scale: 0.47` 的借用实例，避免重复；`use_spice_rack` 不变。
- `cookbook_wall.glb`：`(-2.96,2.32,-1.38)`、yaw 90。按可读性优先，在窗与保温柜间较高的空隙挂书，避开低处调味架；无文字、数字和图标。
- 保温柜 B 案仍是 anchor 位置 `(-2.85,0.082,-1.69)`、yaw 90、scale 1；本 PR 不复制或改写柜子资产/锚点。
- 2、3 号的“盖板”按定稿图解释为**炉眼顶部圆铁盖**：独立 MeshInstance `lid_2` / `lid_3`。默认两片可见，解锁后隐藏；前方拱形炉口不关闭。Lv4 开 2 号，3 号由服务端灶数控制。审阅普通锅+大锅状态隐藏 `lid_2`。
- 1 号火焰复用原 `fire.glb`，位置跟 `fire_1`；2、3 号挂点预留。火焰与炉内木柴相交为正常效果，验证明确区分这类接触与砌体穿插。
- 锅依赖 [#434](https://github.com/IndieMiao/sensen-godot/pull/434)，审阅脚本固定读取提交 `ddcd8b3c5b70aded6676d15a51d8bb6851010854` 的模型与 import 脚本。本 PR 不重复提交锅资产。Basic 原锅底高度 1.377 m 作废；普通锅和大锅直接放到下表 socket，不加 Y 偏移。

| 空节点 | 世界坐标 X, Y, Z（米） |
|---|---|
| stove_1_top | -2.5000, 0.9800, -2.4950 |
| stove_2_top | -2.0500, 0.9800, -2.4950 |
| stove_3_top | -1.6000, 0.9800, -2.4950 |
| fire_1 | -2.4725, 0.2320, -2.5350 |
| fire_2 | -2.0225, 0.2320, -2.5350 |
| fire_3 | -1.5725, 0.2320, -2.5350 |

`fire_N` 的 X 偏移 0.0275 m 用来居中原 fire.glb 的不对称轮廓，不是炉眼偏心。哪吒按新锅位重写 use/drop/badge/cam/stand；此 PR 无 anchors、程序逻辑或等级行为变动。

## 图集与旧阴影

仍用 Basic Room 原 2048² `room_albedo_ao.png` 和共享材质，新件每个可切换网格一个 surface，粗糙度 0.8；新件无照片木纹、文字和描边。铁件、木架、米白、绿罐沿用旧 atlas 现有色块；红书/红辣椒使用未被任何原 GLB UV 或 9 px 周边占用的 16×16 色块。没有新增运行时纹理。

原 atlas 烘进了旧高烟囱的接触阴影，移除模型后留下明显残影。因此用原/新实际 GLB 场景分别烘 AO，将线性空间 new/old 比值只应用到后左厨房目标 UV 岛（墙、地面及移动道具）。原色细节、UV 和网格保留，新增道具采样点保护不变；源目录留有确定性 delta 和烘焙脚本。验证保证 atlas 每个像素都能从原图 + 记录的 AO delta + 红色色块完整重建，区域外不变。这是随道具替换清理旧阴影，没有重新设计墙面。

## 审阅与验证

`SGODOT-213_KITCHEN_v1_*.png` 都来自 Godot 4.7.2 Vulkan Mobile / RADV VANGOGH，Blender 5.2.2 LTS 源模型。三口灶正面、3/4、侧面；真实 Basic Room 整间和灶台角；另有 Lv1 盖板态、调味架/菜谱书近景及 6.72 m 游戏取景。

整间图为原生 360×800、俯角 43°、房间默认偏航约 40.3°，沿用房间套件 10.75 m 全景宽度以容纳整间；额外 6.72 m 图明确标为游戏取景，不代替整间图。近景 3.45 m。旁边为真实默认 Avatar，保温柜使用真实 B 案，1 号普通锅、2 号大锅。

[validation.json](validation.json) 含导入后顶点尺寸/面数、实际 GLB 三角面 BVH、灶面支撑射线、三口大锅并排检查、侵入正控、构件保全、图集差分和连续重建哈希。仅把灶脚与原地板的 0.5 mm 支撑接触、火焰与指定木柴的接触记为合法；不豁免火焰穿砌体。

桌面渲染和几何验收资料，不宣称物理手机性能或已接入农舍游戏逻辑。

## 复现

在仓库根目录：

```sh
blender --background --factory-startup --python tools/art/build_kitchen_213.py
python tools/art/prepare_kitchen_213_review.py
godot --headless --path output/kitchen-213/project --editor --import
godot --path output/kitchen-213/project
blender --background --factory-startup --python tools/art/verify_kitchen_213.py
python tools/art/verify_kitchen_213_atlas.py
```

最后一个 Python 命令需要 Pillow、NumPy。渲染要在可用桌面 DISPLAY 下运行；截图通过 SubViewport 保证真实输出尺寸。隔离项目不读取账户/保存，也不改 anchors。

普通 build 使用已记录的 `tools/art/source/kitchen_213/atlas-ao-delta.npz`，三个 GLB、atlas、layout、stats 均可字节一致重建。只有改变遮挡布局时才重新烘 delta：

```sh
blender --background --factory-startup --python tools/art/rebake_kitchen_213_ao.py
python tools/art/prepare_kitchen_213_ao_delta.py
blender --background --factory-startup --python tools/art/build_kitchen_213.py
```

命名可编辑源文件：`tools/art/source/kitchen_213/kitchen_213.blend`；契约：同目录 `contract.json`。原 Basic Room 全量生成器会重建旧版 layout，不能用于替代此增量生成器。
