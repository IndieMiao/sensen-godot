# Plane 状态核对与交付补录（2026-09-16）

用户要求检查和更新 Plane 卡片，并补齐多人功能等缺失任务。项目为 Sensen Godot / SGODOT，
本次按本仓库的实际代码、QA、发布与交付记录核对。没有新增游戏功能、执行发布或改写玩家数据。

## 结果

- 分页核对原有 114 张卡；补建 11 张后为 125 张。
- 新卡 SGODOT-115～125 均为 Done，范围限定为描述中列明的实现、工程验证与交付。
- 更新 7 张原卡，保留全部原始描述并在前面追加带日期的实际进展。
- 回读 18 张新增/更新卡的状态、证据与父子关系；其余 107 张的标题、状态、优先级、父任务、
  类型、成员和标签逐项比对无变化。独立社交应用分支及旧 Cancelled 项没有被重新判定完成。

## 新增卡片

| 卡片 | 内容 | 状态 |
| --- | --- | --- |
| [SGODOT-115](https://plane.sensenjoy.cn/zili/projects/47d11337-c390-4b42-8b05-ef60fa2633f7/issues/1d16413f-5ac4-46b1-b9ec-c6acbed9b052) | 【联机】多人空间、私有矿井与组队（0.10.0） | Done |
| [SGODOT-116](https://plane.sensenjoy.cn/zili/projects/47d11337-c390-4b42-8b05-ef60fa2633f7/issues/69c319de-dfb8-462d-9d9c-78ce1da0e423) | 【联机】跨地区队伍汇合与私有农场授权（0.10.1） | Done |
| [SGODOT-117](https://plane.sensenjoy.cn/zili/projects/47d11337-c390-4b42-8b05-ef60fa2633f7/issues/fff07377-bdef-411d-8681-f0f2d4f084d0) | 【联机】同步实际保存装扮并清理复用角色配饰（0.10.2） | Done |
| [SGODOT-118](https://plane.sensenjoy.cn/zili/projects/47d11337-c390-4b42-8b05-ef60fa2633f7/issues/3e1b27f7-6190-4573-b0e5-291db8ae97d0) | 【UI修复】按钮/卡片起手拖动可滚动，统一 12 处界面（0.10.3） | Done |
| [SGODOT-119](https://plane.sensenjoy.cn/zili/projects/47d11337-c390-4b42-8b05-ef60fa2633f7/issues/327f8bf4-4ee7-44a0-b6b7-95b1393fc8c9) | 【UI修复】队伍面板固定关闭、外部关闭与邀请码复制提示（0.10.4） | Done |
| [SGODOT-120](https://plane.sensenjoy.cn/zili/projects/47d11337-c390-4b42-8b05-ef60fa2633f7/issues/a4b5a03b-a2bd-466b-aed5-03a3fdaac845) | 【玩法】矿井怪物与实时武器战斗（0.8.0） | Done |
| [SGODOT-121](https://plane.sensenjoy.cn/zili/projects/47d11337-c390-4b42-8b05-ef60fa2633f7/issues/2b6f0e2b-609e-4556-9d9f-45fdea4b8032) | 【战斗修复】沿障碍边缘保留有效移动（R2 / 0.8.1） | Done |
| [SGODOT-122](https://plane.sensenjoy.cn/zili/projects/47d11337-c390-4b42-8b05-ef60fa2633f7/issues/e086e23e-1b09-42a5-a564-e1e94fbb523f) | 【战斗修复】死亡自动返农场与低延迟命中反馈（R3 / 0.8.2） | Done |
| [SGODOT-123](https://plane.sensenjoy.cn/zili/projects/47d11337-c390-4b42-8b05-ef60fa2633f7/issues/23dc9307-105a-44c5-8c10-1b48bd06387c) | 【战斗表现】宝剑仅在每次挥砍时显示（R4 / 0.8.3） | Done |
| [SGODOT-124](https://plane.sensenjoy.cn/zili/projects/47d11337-c390-4b42-8b05-ef60fa2633f7/issues/ab6d5edb-434f-4abb-8d66-a4307d3cb4fc) | 【玩法/地图】矿井双通路、随机战利品、精英强化与右侧缩略图（R5 / 0.9.0） | Done |
| [SGODOT-125](https://plane.sensenjoy.cn/zili/projects/47d11337-c390-4b42-8b05-ef60fa2633f7/issues/3d0cf090-3284-4292-a4f7-873fe5f84814) | 【QA】Android 后台 CPU 核查与统一测试会话清理 | Done |

116、117、119 归属 115；120 归属既有矿井卡 111；121～124 归属战斗卡 120。
未创建新状态、标签或模块。所有新卡包含源文档路径、验证边界、发布信息及
[带截图的 Slack 审核稿](https://gensenapp.slack.com/docs/T07R7K03WQP/F0C28EPNXAM)；
用户尚未审核该文档，未把“已发送审核”当作“已验收”。

## 原卡更新

| 卡片 | 状态 | 原因 |
| --- | --- | --- |
| [SGODOT-111](https://plane.sensenjoy.cn/zili/projects/47d11337-c390-4b42-8b05-ef60fa2633f7/issues/92db2da0-c250-4932-a2b8-bc17d63b23d8) | In Progress | 已实现并纳入线上预览；原卡明确要求的自然玩家观察缺少完成证据，Todo 调整为 In Progress。 |
| [SGODOT-112](https://plane.sensenjoy.cn/zili/projects/47d11337-c390-4b42-8b05-ef60fa2633f7/issues/7d19e8fa-47b3-49d4-b8a2-e20623e2904a) | In Progress | 已实现并纳入线上预览；原卡明确要求的自然玩家观察缺少完成证据，Todo 调整为 In Progress。 |
| [SGODOT-113](https://plane.sensenjoy.cn/zili/projects/47d11337-c390-4b42-8b05-ef60fa2633f7/issues/3ce7c3d9-0bc9-4787-8583-7b849e9f2585) | In Progress | 已实现并纳入线上预览；原卡明确要求的自然玩家观察缺少完成证据，Todo 调整为 In Progress。 |
| [SGODOT-114](https://plane.sensenjoy.cn/zili/projects/47d11337-c390-4b42-8b05-ef60fa2633f7/issues/0e4db8f8-5383-4df9-95b1-b1b9d613823d) | In Progress | 已实现并纳入线上预览；原卡明确要求的自然玩家观察缺少完成证据，Todo 调整为 In Progress。 |
| [SGODOT-32](https://plane.sensenjoy.cn/zili/projects/47d11337-c390-4b42-8b05-ef60fa2633f7/issues/bbab47e1-8d7c-4928-9d5c-75526d563212) | Done | 七条劳作及挥手具备实际 clip；本次 8 项动画守卫通过。 |
| [SGODOT-36](https://plane.sensenjoy.cn/zili/projects/47d11337-c390-4b42-8b05-ef60fa2633f7/issues/7fc95e4f-1207-4087-aeaa-fef73f772df7) | In Progress | 同出口 300 个安装登录已修复，原要求中的客户端 429 明确提示仍待补。 |
| [SGODOT-106](https://plane.sensenjoy.cn/zili/projects/47d11337-c390-4b42-8b05-ef60fa2633f7/issues/d5b67568-aac1-4ef4-b293-0440d344e1e9) | In Progress | 追加当前交付和新卡索引，保留地域经营设计/样板/自然玩家观察的独立未完成范围。 |

111 的剩余项为玩家自主定位矿口/下一层并为明确用途再次采集；112 为自主查清材料数量/属性/用途并使用或交付；
113 为解释装备/道具选择并观察效果；114 为比较至少两份委托并自主选择行动。

跨地区汇合没有被等同于 108 的地域互补生产和异步交换。107 的评审、109/110 的自然观察与回访，
以及双端性能、16 KB、离线冷启动等各自范围，均没有被当前多人上线记录自动关闭。

## 证据

主要依据：`docs/qa/multiplayer-public-release-2026-09-16.md`、
`party-travel-public-release-2026-09-16.md`、`appearance-sync-2026-09-16.md`、
`scroll-ui-2026-09-16.md`、`party-panel-2026-09-16.md` 及 9 月 14–15 日对应功能报告。

动画卡另查当前 `assets/avatar/base/anim_placeholders.json`、实际 rig 和
`tests/farm/test_anim_placeholders.gd`；本次 8 项通过，0 错误/失败/孤立节点。
匿名登录卡查 `server/src/http/app.ts`、`server/test/http/proxy_rate_limit.test.ts` 及客户端错误文案。

原始快照、计划、返回值和回读报告保存在 `output/plane-sync-2026-09-16/`。
