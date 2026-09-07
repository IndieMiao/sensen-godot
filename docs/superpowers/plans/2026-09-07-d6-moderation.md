# D6 审核管线 + E1 服务端 —— 实施记录（2026-09-07）

对应 Plane D6（审核管线 + 工单后台）与 E1（UGC 四件套）的服务端部分。08-30 调研 §5.5「可辩护最小配置」：
发布前自动过滤 → 人工复审队列 → 举报 24h 处置 → CSAM SOP（申请制，SSLAUNCH）。

## 1. 决策

| 问题 | 决定 | 理由 |
|---|---|---|
| 审核服务挂了怎么办 | 放行但 `pending` 进人工队列 | 全站不能因第三方抖动发不出东西，也不能因此漏审；两边都占住 |
| 没配 key | `NullModerator`：不拦，全部 pending | 比「假装审过了」诚实；启动日志有告警 |
| 带图的帖子 | 一律 pending | 图片二道（Rekognition）等 SSLAUNCH D5 AWS 开户；先人工 |
| 举报阈值 | 不同举报人 ≥3 自动隐藏（`hidden`），等人工 | 24h SLA 不能全靠人盯；单人刷举报不触发 |
| 隐藏 vs 删除 | `hidden` 是状态，作者自己还能看到；删除是软删 | 申诉与回看都需要原文；作者能看到自己被下架 |
| 拉黑 | 双向不可见（资料 / 动态 / 评论 404）+ 两个方向自动取关 + 关注对方 403 | Apple 1.2「block abusive users」；不可见比「隐藏一半」好解释 |
| 封禁 | `account_bans`，所有登录路由 403 `BANNED`；删号仍允许 | 删号是用户的权利，封禁是处置，两者独立 |
| 举报表不做外键 | `target_id` 是 text | 目标被删后举报记录必须留（处置记录） |

## 2. 服务端（server/）

- `src/http/moderation.ts`：`TextModerator`（`OpenAiModerator` / `NullModerator`）、`decide`、`ModerationStore` 接口、
  校验、`moderationAccountModule`。`src/http/memory_moderation.ts`、`src/db/pg_moderation.ts`。
- feed 存储加 `moderation_status / moderation_categories`（approved / pending / rejected / hidden）、
  `setPostStatus / setCommentStatus / pendingReview`；时间线接受 `excludeAuthors`（拉黑双向）。
- `schema.sql`：posts / post_comments 加列 + 部分索引；新表 reports / blocks / account_bans。
- 路由见 server/README.md「审核、举报、拉黑、封禁」。管理接口用 `ADMIN_USER_IDS` 门禁；
  gensen_admin 的最小工单页后续套在这组接口上。
- 测试：`test/http/moderation.test.ts`（5）、`test/http/ugc.test.ts`（6）、`test/db/moderation_conformance.test.ts`（2×2）、
  feed 一致性新增审核状态一条；真库全部跑通。

## 3. 未做 / 依赖

- 图片审核（Rekognition）与 CSAM（PhotoDNA / Safer）接入位：SSLAUNCH D5 / D6。
- 客户端 E1：举报 / 拉黑入口（feed 卡片、资料页、IM、语音房）、EULA 零容忍强制同意、公开联系方式。
- 处置通知（被下架 / 封禁的人收到什么）与申诉：D7 推送后。
- IM（D3）的举报 / 拉黑复用这里的 `ModerationStore`。
