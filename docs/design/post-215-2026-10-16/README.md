# SGODOT-215 · 驿站摆设改稿

刘备，2026-10-16。基于 `wp-3d-scene 4c287f6d`；运行时参考固定为 `farm-dev f8c3391c`。依据 Stark 第二版、火舞标注、SGODOT-218 制作清单，以及上官婉儿本轮最终修订。

## v1.2 最终修订

- **费用板只由现有 `post.anchors.json.props` 摆放**：从本 PR 的 layout 删除 fare_board；正式 anchors、费用板 GLB 和位置 `(-3.208,1.65,-1.65), yaw 90` 全部保留。审阅场景读取同一 prop，只放一份。
- **Pip 回到右侧**：`npc_pip=(2.3,0.08,0.8)`、`stand_pip=(1.65,0.08,0.6)`，沿用现行位置，站在邮袋/包裹架一侧。三位 NPC 与出口在 360×800 / 43° / 6.72 m 下，两两足部和名字条最小距离均 **74.84 px**。
- Sam 人物位置保留 `(1.2,0.08,-1.5)`。原 `stand_sam=(1.2,0.08,-0.8)` 在柜台碰撞盒内；建议接近点改为 `(1.85,0.08,-1.35), yaw -90`，从右侧通道接近。实际胶囊验证中央→右通道→Sam 全程通过。
- **招牌无字**：原文字是 10 段网格，共 7,460 面，已删除；红色拱牌和信封原几何、法线、位置保留，剩 **776 面**。红牌上还有文字烘焙 AO，因此把红牌 UV 改取自身左上方的干净红色色块，消除残影。信封 UV 不变。
- **不改任何图集像素**：干净取样中心为 PNG 左上原点 `(690.5,1259.5)`，glTF UV `(0.337158203125,0.614990234375)`；周围 9×9 原像素范围 RGB `[159,53,46]` 至 `[166,56,48]`。此处仅取样，无写入；不是擦改原图集。修改区域 `[]`、修改像素 0、PNG SHA-256 不变，因此费用板和农场邮筒的共享纹理保持原样。
- 罗盘地毯保持实际 **2.20 m**。原 1 m 入口路线、桌面中心和使用站位复核通过。

## 保留的摆设改稿

- 复用现有 Post Office；墙、地板、门、柜台、信件格/信件、挂钟、红邮筒、包裹架及库存的网格和位置保持一致。
- 盖章台经批准移到左侧 `(-0.68,0.082,2.30)`，原 mesh 字节不变；凳子位于 `(1.05,0.087,2.60)`。银白壶身、深色盖咖啡壶、白杯、印章/印台、空白摊开的护照本与小绿植合为 `stamp_desk_set`。保留原信件及桌下箱，原桌面冲突小件移除；桌垫用原图集干净色块避免旧 AO 残影。
- 2.20 m 米色/蓝灰罗盘毯位于 `(1.62,0.083,1.00)`。门上原壁灯加两盏新壁灯，共三盏；后台加桌灯，日光与环境参数不变。
- 左前和门旁包裹来自现有包裹/邮袋，保留原 UV；左前布袋等比 0.6。移除电脑、杂志架、冲突长条地垫；保留门垫，不放自行车。
- 世界地图省略：左墙已被费用板、招牌、门框、告示占据，放不下完整地图。

## 图集、预算与验证

`room_albedo_ao.png` SHA-256：`dbae34e9aaeb7553c7264ef841e939ba43b6d462ad60eb18ba1e2132021ffbd9`。

套件 layout 含实例和共享植物：**155,770 triangles / 40 surfaces**。加现有 anchors 费用板为 **156,444 triangles / 41 surfaces**；预算低于 200k / 60。新件均单 mesh / surface，`.import` 为 `gltf/texture_map_mode=1`。

- `validation.json`：632 项实际 GLB/UV/哈希/交叠检查及 91 项 Godot 导入、站位、路线、像素距离、截图检查，共 **723 项通过**。
- 原招牌嵌墙接触与基线一致，单独记录于 `preexisting_pairs`；没有新增跨道具穿插。桌垫仅在实测台面 `y=1.097` 接触，原桌下箱装配接触单列。
- 使用半径 0.21 m、高 1.745 m 胶囊检查 NPC 与接近点、进门到柜台、中央和 Sam 右侧通路；1.00 m 宽、高 1.745 m 检查盒随转弯方向旋转，入口两段扫掠通过。桌前边 z=1.66192，通道净宽 1.02384 m。
- v1.2 招牌生成脚本重复执行后，Post Office 目录 56 个 GLB 全部字节一致；图集不变。之前 8 件新增资产的完整生成复现见 v1.1 记录。
- 实际 Godot 4.7.2 / Vulkan Mobile / AMD RADV VANGOGH 窗口渲染；没有手机性能验收。

## 建议挂点（正式 anchors 由程序改）

| 挂点 | world XYZ（m） | yaw |
|---|---|---:|
| npc_pip | (2.30, 0.08, 0.80) | 90 |
| stand_pip | (1.65, 0.08, 0.60) | -90 |
| npc_sam | (1.20, 0.08, -1.50) | 180 |
| stand_sam | (1.85, 0.08, -1.35) | -90 |
| npc_keeper | (-0.40, 0.08, -1.40) | 180 |
| use_stamp_desk | (-0.68, 1.097, 2.30) | — |
| stand_stamp_desk | (-0.68, 0.08, 1.29) | 0 |
| spawn | (-2.60, 0.08, 1.29) | -90 |
| exit | (-3.30, 0.08, 1.29) | — |
| badge_exit | (-3.20, 2.45, 1.29) | — |

保留 anchors.props 的费用板；`use_fee_board=(-3.158,1.65,-1.65)` 保持原值。Pip、Sam、Sigrid 用运行时真实 NPC 部件，Pip scale 0.88；审阅图人物朝镜头展示造型，正式 yaw 按挂点语义。

## 两张补图与复现

本轮仅重出 `SGODOT-215_POST_v1_2_post_npc_positions_360.png` 和 `SGODOT-215_POST_v1_2_post_sign_detail.png`。前者三位真实 NPC 同场；后者隔离展示实际招牌 GLB，无遮挡。旧图仅留档，最终站位/招牌以 v1.2 为准。

```sh
blender -b --factory-startup --python tools/art/build_post_215.py
blender -b --factory-startup --python tools/art/revise_post_sign_215.py -- --verify-repeat
python tools/art/arrange_post_215.py
blender -b --factory-startup --python tools/art/verify_post_215.py
python tools/art/prepare_post_215.py
godot --headless --path output/post-215/project --editor --import
godot --path output/post-215/project -- --post-revision
python tools/art/package_post_215.py --revision
```

生成源为 `tools/art/source/post_215/post_215.blend` 与 `post_office_sign.blend`，均有具名编辑对象；后者保留红牌、信封与折线，不包含文字。`sign-revision.json` 记录删字及 UV 取样。图集始终只读；旧房间源文件保留。窗口渲染使用独立审阅项目，不读写生产存档。

## 213 补图

`supplement-213/` 是另卡的补交材料。1 号灶放 Big Pot，使用 `farm-dev f8c3391c` 的 Basic Room、新灶、锅、保温柜 B 和最新锚点。镜头按运行时 `frame_all / focus` 公式、`cam_stove (-2.5,1.24,-2.435)`、`FOCUS_SIZE=0.42`、HUD 底边 98/800 至 0.29 的屏幕带复现；锅底 `(-2.5,0.98,-2.495)`。不带操作 UI，未改运行资产。运行审阅工程不加 `--post` 可复现此补图。

两张 PNG 与验证 JSON 已署刘备 id 上传并下载哈希核对，Plane 213 评论 `b3c45715-37f9-4509-98cb-0d4b29b26c51`。这项不改变 215 的范围。
