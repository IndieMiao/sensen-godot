# 暖木室内场景 · 当前评审进度

2026-10-08：173正式挂点R2.2和175糕点小修R2.1已推送 `wp-3d-scene` / `wp-3d-scene-zhaoyun`，新实渲、角色录像、Plane附件和飞书回读已完成，两卡为Review。本轮合计 **72/72角色检查、57个Plane附件、11条飞书消息/媒体**。

| 卡片 | 当前结果 | 入口 |
|---|---|---|
| 172 | 前版美术已验收；用户重开Todo，只换共享粒子炉火 | [R2.1已验收美术](../standard_room_5-review21-2026-10-07/README.md) |
| 173 | Review；12个正式anchors通过工程校验，38/38新实渲测试，15秒录像 | [R2.2](../deluxe_room_10-2026-10-07/README.md) |
| 174 | Done；美术通过，未再改模型 | [R2.1](../farm_tools_store-2026-10-07/README.md) |
| 175 | Review；24件/11原型分层糕点、侧移盆栽、凹槽割纹，34/34新实渲测试，15秒录像 | [R2.1](../bakery-2026-10-07/README.md) |
| 176 | Done；R2已验收，27个Plane附件、6条飞书消息/媒体回读通过；邮筒UV变更已单独注明 | [R2](../post_office-2026-10-07/README.md) |
| 177 | 刘备，Done | [酒馆/铁匠铺](../tavern-forge-r2-2026-10-07/README.md) |
| 178 | 刘备，In Progress；制作共享粒子特效 | [酒馆/铁匠铺](../tavern-forge-r2-2026-10-07/README.md) |

173使用Arthur WP7-B正式 `layout.anchors` 契约；复用了工程原始 `check_room_anchors.gd`，结果12 anchors / 0 problems。175预算181,235总面/31,154植物预算面/40surface，三层顺序不同，粉黄白绿糕点可读，白掌不挡柜。

新增炉火统一要求另有依赖：刘备在178 R2.2先单独提交自包含 `assets/rooms/_shared/fx/fx_hearth_fire`，合入共享分支后，赵云复用到172/173/175。本次最终检查的共享远端尚无该目录；当前交付完成的是正式挂点与糕点反馈，没有声称粒子炉火已接入。172既有模型、图集与机位保留。

[逐卡验证和回读计数](review-progress-2026-10-08.json)。旧[首轮七场景总览](overview.jpg)和verification.json为历史初稿记录。各卡按最新附件复审；没有生产发布或游戏数据操作。
