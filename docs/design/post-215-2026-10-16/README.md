# SGODOT-215 · 驿站摆设改稿

刘备，2026-10-16。基于 `wp-3d-scene` 的 `4c287f6d`；实景、角色和 213 补图的运行时参考固定为 `farm-dev f8c3391c`。依据 incoming/post-215 的 Stark 第二版、火舞标注及 SGODOT-218 制作清单 v1.1 的 215 节。

## 最终摆设

- 复用现有 Post Office，墙、地板、门、柜台、信件格/信件、挂钟、红邮筒、包裹架及其库存的网格与布局逐项保持一致。
- **盖章台移到左侧已获上官婉儿在本次会话明确同意**：原 mesh 字节不变，位置从 `(0.31, 0.082, 1.64)` 改为 `(-0.68, 0.082, 2.30)`，yaw 仍为 0。原中央摆位无法容纳约 1.9 m 的地毯。凳子随使用面移到 `(1.05, 0.087, 2.60)`，留出入口和柜台通路。
- 完整 **直径 2.20 m** 的米色/蓝灰罗盘地毯在 `(1.62, 0.083, 1.00)`；八角星、内外环和四个方向小三角都是几何图形，无文字。
- 银白壶身/深色盖的咖啡壶、空心白杯、印章/印台、空白摊开的护照本、小绿植合为 `stamp_desk_set`。保留原信件叠和桌下纸箱；去掉冲突的原桌面包裹、秤、工具。旧桌垫含这些小件的烘焙阴影，改用同尺寸干净色块几何，原图集完全不动。
- 门上原壁灯加两盏新壁挂提灯，共三盏；移除电脑的位置增加后台桌灯。原日光和环境光参数不变，新暖色点光能量 0.22 / 0.22 / 0.12，无阴影；日光仍为主。
- 左前与门旁新增包裹堆，来自原 `parcel_shelf_stock` 的棕包裹、柜顶蓝包裹和 `mail_sacks` 的一个完整布袋。保留原 UV；只改为局部落地轴心，修正原自定义法线与面的少量不一致。左前布袋按 0.6 等比摆放，以免挤到门框与前沿。
- `counter_computer`、`magazine_rack`、长条 `front_floor_runner` 不再摆放；不放自行车。原门垫保留。
- **世界地图省略**：左墙已被已验收费用板、邮局招牌、门框和告示占据，无法在盖章台上方再放完整原地图。费用板为原来的七行横条模型，位置严格保持运行时批准值 `(-3.208, 1.65, -1.65)`、yaw 90，网格不变。

## 通道与交互复核（v1.1）

- 按上官婉儿 / 不知火舞补充：地毯扩大到实际 2.20 m，Pip 移出进出路线，桌面中心和使用站位同步写入 layout。
- 出口仍为 `(-3.3, 0.08, 1.29)`，原 spawn `(-2.6, 0.08, 1.29)` 不变。入门后由 `(-2.91, 1.29)` 稍转至 `(-2.65, 1.15)`（XZ），再沿 z=1.15 通向中央；实际物理扫掠用 1.00 m 宽、1.745 m 高的盒体，两段都通过。
- 桌前边 z=1.66192，距路线中心 0.51192 m，净宽 1.02384 m。Pip 半径 0.21 m 胶囊完全在通道之外，包裹和桌面物件没有侵入。凳子改到桌右侧，腾出入口和使用站位。
- Pip 与出口足部投影 46.65 px、名字条 57.37 px；与实际桌面中心交互点 66.32 px，均 ≥44 px（360×800 / 43° / 6.72 m）。
- 盖章台与费用板沿墙方向相隔 2.86 m，费用板位置、模型均不变；世界地图仍省略。

## 图集与预算

`room_albedo_ao.png` SHA-256：`dbae34e9aaeb7553c7264ef841e939ba43b6d462ad60eb18ba1e2132021ffbd9`。

**修改区域：空列表 `[]`，修改像素数 0，PNG 字节不变。** 新造几何以常量 UV 取现有色块，取样中心、原件来源、原件 SHA 和非黑/非空白边距在 `tools/art/source/post_215/atlas-swatches.json`。不新增贴图。费用板和农场邮筒的共享依赖不受影响。

整间含实例及原共享植物：**163,904 triangles / 41 surfaces**，低于 200k / 60。8 个新增/派生 GLB 各为一个 mesh、一个 surface；`.import` 全部 `gltf/texture_map_mode=1`。

| 新件/派生件 | triangles |
|---|---:|
| compass_rug | 784 |
| stamp_desk_set（含新桌垫） | 2,568 |
| post_wall_lantern | 848 |
| post_table_lamp | 696 |
| brown_parcel_reused | 1,168 |
| blue_parcel_reused | 1,276 |
| mail_sack_reused | 2,490 |
| packing_dressing_215（原信件与桌下箱） | 8,066 |

## 程序接入

本 PR 不改 anchors。`layout.json.suggested_anchors` 是建议值；程序负责正式 `assets/p0/outposts/post.anchors.json`。

| 挂点 | world XYZ（m） | yaw |
|---|---|---:|
| npc_pip | (-2.48, 0.08, 2.26) | 180 |
| stand_pip | (-2.48, 0.08, 1.65) | 90 |
| npc_sam | (2.45, 0.08, 0.85) | 180 |
| stand_sam | (1.75, 0.08, 0.85) | -90 |
| npc_keeper | (-0.40, 0.08, -1.40) | 180 |
| use_stamp_desk | (-0.68, 1.097, 2.30) | — |
| stand_stamp_desk | (-0.68, 0.08, 1.29) | 0 |
| spawn | (-2.60, 0.08, 1.29) | -90 |
| exit | (-3.30, 0.08, 1.29) | — |
| badge_exit | (-3.20, 2.45, 1.29) | — |

其他原挂点的建议值保持不变。**费用板现在已列入完整 layout；接入时须去掉 anchors.props 里同名费用板的重复实例**，仍保持 `use_fee_board (-3.158, 1.65, -1.65)`。不可把地图当费用板。

43° / 原套件 yaw（约 45.71°）/ 6.72 m / 原生 360×800 下，四点两两最小足部投影距离 **46.65 px**，名字条投影最小 **57.37 px**，均 ≥44 px。Pip、Sam、Sigrid 用 `f8c3391c` 的实际 NPC 造型，Pip scale 0.88。人物朝向在审阅中朝镜头，正式 yaw 按挂点语义使用。

## 验证与审阅图

- `validation.json`：导出 GLB 实际顶点/面数/UV/法线、原件与图集哈希、598 项检查；所有新件/移位件与套件、原共享植物的实际三角形 BVH 检查通过。桌垫在实测 `y=1.097` 台面接触，保留原桌下箱与桌体装配接触单列，未把整件交叠都豁免。
- Godot Mobile Vulkan（AMD RADV VANGOGH）的 94 项检查：实际导入后再次核尺寸、面数、surface，实放场景包含植物和重复实例。真实 0.21 m 半径 / 1.745 m 高胶囊检查站位及门→柜台、Pip、Sam、中央通道。仅桌面 Vulkan 审阅，未做 Android/手机性能验收。
- 复现检查：重跑生成脚本前后整个 Post Office 目录 **56 个 GLB 字节一致**（8 个新件及其余原件），共享 PNG 不变。
- `SGODOT-215_POST_v1_post_gameplay_43deg_360.png`：6.72 m 游戏比例，玩家在 spawn。这个比例不能同时容纳整间横向边界；另附原生 360 完整取景和 1200×1000 全景。
- `…post_full_room_360.png` / `…post_full_room_panorama.png`：完整套件。
- `…post_stamp_desk_detail.png`：咖啡壶、杯、印章、空白本、绿植及保留信件。
- `…post_npc_positions_360.png` / `…post_npc_positions_panorama.png`：三位实际 NPC；原生 360 图带名字条定位。

## 复现

在仓库根目录，Blender 5.2.2 / Godot 4.7.2：

```sh
blender --background --factory-startup --python tools/art/build_post_215.py
python tools/art/arrange_post_215.py
blender --background --factory-startup --python tools/art/verify_post_215.py
python tools/art/prepare_post_215.py
godot --headless --path output/post-215/project --editor --import
godot --path output/post-215/project -- --post
python tools/art/package_post_215.py
```

最后一步渲染必须开窗口；`--headless` 仅用于导入。源文件 `tools/art/source/post_215/post_215.blend` 保存具名编辑对象；旧整间 Blender 源文件保持不变。审阅工程独立 user dir，不读写线上存档。

## 213 补图

`supplement-213/` 是另卡的补交材料。1 号灶放 Big Pot，使用 `farm-dev f8c3391c` 的 Basic Room、新灶、锅、保温柜 B 和最新锚点。镜头按运行时 `frame_all / focus` 公式、`cam_stove (-2.5,1.24,-2.435)`、`FOCUS_SIZE=0.42`、HUD 底边 98/800 至 0.29 的屏幕带复现；锅底 `(-2.5,0.98,-2.495)`。不带操作 UI，未改运行资产。运行审阅工程不加 `--post` 可复现此补图。

两张 PNG 与验证 JSON 已署刘备 id 上传并下载哈希核对，Plane 213 评论 `b3c45715-37f9-4509-98cb-0d4b29b26c51`。这项不改变 215 的范围。
