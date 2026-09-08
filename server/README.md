# farm-server

街角四季的权威状态服务。数值逻辑全部在这里，客户端不算钱（方案 D4）。

## 本地开发

数据库跑在局域网测试机 devserver（`192.168.124.53`）的容器里，本机不装 Docker 也不装
PostgreSQL。

```bash
# 首次：在 devserver 上起库
scp deploy/devserver-pg.compose.yml zhangshaojie@192.168.124.53:~/pg16-farm/compose.yml
ssh zhangshaojie@192.168.124.53 'cd ~/pg16-farm && echo "POSTGRES_PASSWORD=$(openssl rand -hex 16)" > .env && chmod 600 .env && docker compose up -d'

cp .env.example .env      # 填 DATABASE_URL / TEST_DATABASE_URL / TOKEN_PEPPER
pnpm install              # 在仓库根跑，workspace 会带上 blueprint-core
pnpm test                 # 154 个用例；没有 TEST_DATABASE_URL 时 DB 套件跳过
pnpm typecheck
```

国内直连 Docker Hub 拉 postgres 镜像会断（`short read: unexpected EOF`），compose 里
已改用 daocloud 镜像源。

## 跑起来

```bash
node --experimental-strip-types src/index.ts     # 需要 DATABASE_URL 与 TOKEN_PEPPER
curl localhost:3000/v1/healthz
```

启动时会校验全部在架蓝图，任一不过直接退出——不带病上线。

## 自由选址（SGODOT-37）

`POST /v1/farms` 接受可选的 `location: {"lat": 31.225, "lng": 121.485}`。
`layout_patch_id` 仍决定逻辑格、寻路和种植规则，位置只平移地图上的布局。
同一模板可用于不同玩家的独立位置；每位玩家仍只有一座农场，接口不提供迁移或覆盖已有农场的行为。

`GET /v1/regions` 返回 `farm_placement_version: 1`，以及每个地区的
`placement_bounds: [south, west, north, east]`。这是游戏支持的选址范围，
不是现实土地所有权或可耕种性判断；选址校验在边缘预留 300 米以容纳地图布局。
客户端必须确认服务支持该版本，再发送带位置的建场请求，防止旧服务忽略新字段。

迁移只新增可空的 `farms.location` JSONB 列，旧农场没有位置值，继续使用原蓝图位置。
主人回包始终包含已保存位置；附近列表和访客快照仅在 `location_visible` 为真时包含位置。
关闭位置展示即时覆盖同一时间槽中的缓存快照，不必等待 15 分钟。

本地设备验证使用独立数据库，避免测试套件中的 `truncateAll` 清空正在体验的存档。
数据库名通过 `DATABASE_URL` 指定，服务用 `PORT=3101` 启动后，可通过
`adb reverse tcp:3101 tcp:3101` 和客户端 `user://server.txt` 中的
`http://127.0.0.1:3101/v1` 连接。测试服务不需要发布到公网。

## 领域语义 1 → 2（SGODOT-41）

本次 `DOMAIN_VERSION` 从 `1` 升到 `2`，`STATE_SCHEMA_VERSION` 仍为 `1`。
新增的居民 `choice_memories` 为可选字段，章节仍使用已有的 `step_flags`，无需改表结构。
启动入口中的 `db/migrate.ts` 只负责幂等 DDL，**不会自动执行本次规则迁移**。
未迁移的旧农场对新命令继续返回版本不匹配；旧幂等键仍先查历史命令，返回原结果。

显式工具为 `tools/migrate_domain.ts`，仅接受独立设置的 `MIGRATION_DATABASE_URL`，
不会加载 `.env` 或回退使用 `DATABASE_URL`。内容版本从本次发布的内容文件计算；
设置 `ASSET_ROOT` 时与服务启动入口使用相同目录，否则使用仓库内容目录。

```bash
# 在 server/ 下运行；MIGRATION_DATABASE_URL 必须由执行环境显式设置。
pnpm exec tsx tools/migrate_domain.ts          # 默认 dry-run，无持久化写入
pnpm exec tsx tools/migrate_domain.ts --apply  # 明确提交迁移
```

JSON 报告列出 `eligible`、`already_current`、`blocked` 和 `migrated`。
仅当前 `content_version`、结构版本 `1`、领域版本 `1` 的农场进入迁移；
匹配当前内容的领域版本 `2` 农场列为已完成。未知领域版本、其他结构版本或任意内容不匹配
会给出农场 ID、实际版本和拒绝原因，并阻止**整批 apply**，不会只迁移其中一部分。
拒绝时进程退出码为 `2`，执行或连接异常为 `1`；成功预览/提交为 `0`。

发布顺序：先备份并停止旧版本的写入实例，用待发布版本的同一份内容执行预览，
核对目标农场与零 `blocked` 后显式 apply，成功后再启动领域版本 `2` 的服务。
不要在旧写入实例仍会继续建场的情况下完成切换。内容不匹配应调查发布内容和存档来源，
不能直接改写 `content_version` 来绕过门禁。

apply 在一个事务内先取得 `farms` 的 EXCLUSIVE 写入屏障，再按 ID 排序取得行锁。
普通 SELECT 仍可读取；新建农场、命令更新和其他迁移在写入窗口内等待。
已开始的写事务先提交后才被检查，避免漏掉并发插入或覆盖刚提交的状态。
锁等待超过 5 秒会失败并回滚，排查旧写事务后可重试。

迁移只更新 `farms.domain_version`，保留 `state`、乐观版本计数、时间戳、钱包、库存、
身份、选址、建场记录、访客快照以及历史 `commands` 的结果和旧版本字段。
不会根据旧库存、收获记录或已做过的对话推断新的 D0 次批播种证据或选择回顾记录；
缺少明确事实时由新领域逻辑保守处理。重复执行幂等，事务失败整批回滚。
领域版本 `2` 已接受新命令后，不可只把版本列改回 `1`；应使用经过审查的前向修复，
或按发布前备份执行完整恢复。

迁移真库回归位于 `test/db/domain_migration.test.ts`。只使用新建的独立
`TEST_DATABASE_URL`，数据库名须包含独立的 `test` 或 `migration` 段；
该套件会清理测试表，不能传入运行中的服务数据库。

## 庭院摆件存档（SGODOT-45）

`save_decorations` 通过既有命令端点原子替换整份庭院布置。仅完成工具或扩地购买后开放，
六件摆件免费，每种最多一件；空列表表示全部收起。命令仍受版本、幂等和主人身份校验保护。

```json
{
  "type": "save_decorations",
  "payload": {
    "props": [{ "anchor_id": "courtyard", "prop_id": "bench", "offset_q": [-4, 3] }]
  }
}
```

封套还需提供 `idempotency_key` 和 `base_version`。六个 `prop_id` 为
`bench / planter / lantern / fountain / sign / crate`，不接收旋转或额外私有字段。
`offset_q` 是庭院独立实例的 `[x, z]` 整数坐标，每单位 0.5 米，不能当作农田 `cell_id`。
共享内容表 `assets/farm/data/decorations.json` 定义合法区域、中央通道、固定布景避让和默认位置。
当前可用区域为 `x = -6..-3 或 3..6`、`z = 3..5`，排除 `abs(x) >= 5 且 z <= 3`，
任意两件中心间距至少 2 个量化单位。任一摆件非法时返回 422，原布置与版本不变。

主人状态使用可选 `state.decorations`；早期领域版本 2 存档缺少此字段时按空列表读取，
首次保存才写入，不在 GET 中补写数据库。新农场初始化为空列表。本变更不升级
`DOMAIN_VERSION` 或 `STATE_SCHEMA_VERSION`，不修改自动或显式迁移工具。
新增内容表参与 `content_version`；旧内容版本存档仍受现有门禁限制，不会自动改写版本。

访客快照复用已有 `props` 白名单，只包含 `anchor_id / prop_id / offset_q`，
按既有 15 分钟快照槽更新，不包含钱包、成长购买、库存或居民状态。
保存、重载、幂等、失败不覆盖和访客隔离回归在 `test/db/decorations_conformance.test.ts`，
同时覆盖内存 Store 与配置了独立 `TEST_DATABASE_URL` 的 PostgreSQL。

## 首周结局（SGODOT-43 / SGODOT-46）

`state.week_summary` 在 D6 章节完成且 `life_choices[6]` 已明确记录后生成。
共同场景先完成但第六次用途尚未选择时不生成，也不会默认把缺失选择当作出售。
不增加金币、物品、经验或关系；摘要记录首次满足条件时的真实状态，后续耕作与交易不改写它。

摘要包含 `id: first_week`、服务器时间 `completed_at`、玩家日 `completed_day`、
`wallet / xp / level`、已购买的 `growth_choice`、苗圃状态和三名居民的真实点数与阶段。
`choices` 只含已确认的 D1-D6 用途，`life_choice_count` 是其中 `gift` 或 `keep` 的数量。
达到内容表阈值 4 时 `life_priority=true`：`photo_variant=personalized`、
`journal_pages=[shared_harvest,familiar_faces]`、`next_week_clue=resident_seed_exchange`；
否则为合法出售结局：`photo_variant=standard`、空手写页列表、`next_week_clue=nursery_next_stage`。
手账仅追加一次 `kind=week_summary / key=first_week`，访客快照不包含摘要及其分支。

旧存档已满足条件时，GET 在克隆状态中按最后持久化动作时间确定性投影摘要，不写数据库；
下一条成功命令持久化同一摘要。失败命令、重复请求和跨日读取不能重复生成手账页。
摘要余额是完成时点的快照，可能与玩家之后交易后的当前钱包不同。

`test/db/chapter_conformance.test.ts` 覆盖工具/扩地 × 生活/出售四路线，
在上海及洛杉矶（含 DST）分别运行 MemoryStore 与 PostgreSQL HTTP 流程。
最终钱包分别为工具生活 305、扩地生活 145、工具出售 376、扩地出售 200。
最后一项沿用既有账本规则：D6 触及 100 金币摊位预算，2R 留在库存；
不能为了达到旧 PRD 的 216 数字超额结算。所有路线验证重登、幂等和摘要不提前锁定。

## 账号服务（SGODOT-76 / D2）

社交主线的账号：客户端用 Firebase Auth 登录（B1），服务端**每个请求**都用 Google 公开的
JWKS 校验 Firebase ID token（RS256），不另发自己的会话 token。自有 `user_id`（uuid）是主键，
Firebase uid 只是 `user_identities` 里的一条身份记录。`FIREBASE_PROJECT_ID` 不设时账号路由
一律 503，农场路由不受影响。

| 方法 | 路径 | 说明 |
|---|---|---|
| POST | `/v1/auth/firebase` | body `{id_token}` 或 Bearer；找或建用户，首次 201 |
| GET | `/v1/users/me` | Bearer = Firebase ID token；没登录过 404 `NO_ACCOUNT` |
| GET | `/v1/users/me/export` | CCPA / GDPR 访问请求：账号 + 身份 + 各模块导出，JSON 附件 |
| DELETE | `/v1/users/me` | 应用内删号（Apple 5.1.1(v)），幂等 |
| POST | `/v1/account/delete` | 站外 Web 删号页（Google Play 要求）：body `{id_token}` |

401 一律带 `reason`（`EXPIRED` / `BAD_SIGNATURE` / `UNKNOWN_KID` …），客户端据此决定刷新
token 还是重新登录。JWKS 按 `max-age` 缓存，未知 kid 触发一次强制刷新（60 s 冷却），拉不到
新钥匙时沿用旧钥匙。

删号级联：后续模块（资料 / IM / feed / 关注 / 位置 / 推送 token / 举报）通过 `AppDeps.accountModules`
登记 `del` 与 `export`；删号按登记顺序跑 `del`，任一失败整个 500 且用户保留。成功后删
`users` 行（身份级联）并写 `account_deletions` 墓碑（只有 uid 与时间，不留邮箱）。Apple 登录
的用户墓碑标 `apple_revocation = pending`，等拿到 Apple client secret（SSLAUNCH A6）后由队列
撤销 token。Firebase 侧的用户删除由客户端 / 网页自己用 Firebase 调用完成。

## 资料与关注（D4-a）

规则来自 `Gensen_US/en-us/Gensen-follow-feature-requirements.md` v1.2：单向关注无需批准、不能关注
自己、数量不限；互关即密友；取关只降级不通知；粉丝列表永远公开，「我关注的」可用隐私开关对他人
隐藏（关掉后别人看不到关注数与列表）；新粉丝聚合成带未读的入口。所有路由 Bearer = Firebase ID token。

| 方法 | 路径 | 说明 |
|---|---|---|
| GET / PUT | `/v1/users/me/profile` | 自己的资料；PUT 只改给了的字段：`display_name`(1–30) `handle`(3–20 `[a-z0-9_]`，唯一，可 null) `bio`(≤160) `avatar`(对象 ≤4 KB) `following_visible` |
| GET | `/v1/users/:id/profile` | `:id` = `me` / `@handle` / uuid；带 `relation` 与计数，`following_count` 受隐私开关 |
| PUT / DELETE | `/v1/users/:id/follow` | 关注 / 取关，幂等；自己 400 `SELF_FOLLOW`；不存在 404 |
| GET | `/v1/users/:id/following` | 别人的受隐私开关：403 `FOLLOWING_PRIVATE`；`cursor` / `limit`(≤50) |
| GET | `/v1/users/:id/followers` | 永远公开 |
| GET | `/v1/users/me/new-followers` | 最近关注我的人 + `unread_count`，读过即清 |

首次登录时随账号建默认资料（昵称 = 邮箱本地部分）。资料与关注通过 `accountModules` 登记了导出与
删号级联。陌生人「一条打招呼」的聊天限制归 D3 IM，用这里的 `relation` 判定。

## feed（D4-b）

图文动态 + 点赞 + 一级评论。**可见性照关注规则**：作者本人，或关注了作者的人；密友与单向关注同一
规则。时间线 = 我 + 我关注的人的动态，按发布时间倒序键集分页；评论按时间正序。不可见与不存在
都答 404。删除是软删（审核与举报要能回看）；删号时硬删。图片只存引用（R2 对象 key，D4-c 接
上传前客户端拿不到合法 key）。

| 方法 | 路径 | 说明 |
|---|---|---|
| POST | `/v1/posts` | `{idempotency_key, text?, images?:[{key,w?,h?}]}`；文字 ≤2000、图 ≤9、至少一样非空；重放 200 |
| GET | `/v1/feed` | 时间线；`cursor` / `limit`(≤50) |
| GET | `/v1/users/:id/posts` | 某人的动态；未关注 403 `FOLLOW_REQUIRED` |
| GET / DELETE | `/v1/posts/:id` | 单条 / 作者删（他人 403） |
| PUT / DELETE | `/v1/posts/:id/like` | 点赞 / 取消，幂等，回 `like_count` |
| GET / POST | `/v1/posts/:id/comments` | 一级评论；`{text}` ≤500 |
| DELETE | `/v1/comments/:id` | 评论作者或帖主可删 |

## 图片直传（D4-c）

`POST /v1/uploads` `{kind: post_image|avatar, content_type, size}` → 201 `{key, url, method: PUT, headers, expires_at, public_url}`：
客户端用返回的 `url` + `headers` 直接 PUT 字节到 R2（S3 兼容，SigV4 查询串预签名，10 分钟有效，
UNSIGNED-PAYLOAD），服务端不经手图片流量。key 形如 `u/<user_id>/<yyyymmdd>/<random>.<ext>`，发帖时
`images[].key` 必须在本人前缀下（否则 400 `SCHEMA` / `NOT_OWNED`）。支持 jpeg / png / webp / gif / heic，
≤15 MB。环境变量 `R2_*` 缺一则 503 `UPLOADS_NOT_CONFIGURED`。审核挂钩（D6）在发帖路径上接。

## 审核、举报、拉黑、封禁（D6 / E1）

08-30 调研 §5.5「可辩护最小配置」：发布前自动过滤 → 人工复审队列 → 举报 24h 处置。

- **前置过滤**：帖子与评论的文字过 OpenAI omni-moderation；命中 → 422 `MODERATION_REJECTED`（带 `categories`）；
  审核服务出错 / 没配 key → 放行但 `moderation_status = pending` 进人工队列；带图的帖子一律 pending
  （Rekognition 二道等 AWS 开户）。`hidden` 是举报或人工下架：除作者外都看不到。
- **举报** `POST /v1/reports` `{target_type: post|comment|user, target_id, reason, detail?}`；同一人同一目标只记一条；
  不同举报人达到 3 条自动隐藏内容（`auto_hidden`）。
- **拉黑** `PUT/DELETE /v1/users/:id/block`、`GET /v1/users/me/blocks`：双向不可见（资料 / 动态 / 评论都 404），
  拉黑时两个方向自动取关，关注被拉黑者 403 `BLOCKED`。
- **封禁**：所有需要登录的路由 403 `BANNED`；账号仍在（删号是用户的权利，封禁是处置）。
- **管理队列**（`ADMIN_USER_IDS`）：`GET /v1/admin/reports`、`POST /v1/admin/reports/:id/resolve {action: dismiss|remove_content|ban_user}`、
  `GET /v1/admin/review`、`POST /v1/admin/review/:type/:id {decision: approve|hide}`。gensen_admin 工单页后续套在这组接口上。

## IM（D3，自建）

消息落 PostgreSQL（D0「统一 Node + 现有 PG」，不引 Mongo）。每个会话有自己的 `seq`；每个用户有一条
**inbox 事件流**（用户级单调 `seq`），会话里的每条消息扇出成每个成员 inbox 里的一条事件。客户端只记
一个 `last_seq`：在线时 WS 推事件（下一步），断线回来 `GET /v1/im/sync?since=last_seq` 补拉。

| 方法 | 路径 | 说明 |
|---|---|---|
| POST | `/v1/im/dm` | `{user_id}` 找或建单聊；自己 400、拉黑 403 |
| POST | `/v1/im/groups` | `{title, member_ids}`（≤50）；成员须存在且未互相拉黑 |
| POST / DELETE | `/v1/im/groups/:id/members` · `…/members/me` | 拉人 / 退群 |
| GET | `/v1/im/conversations` | 我的会话，按最近消息倒序，带 `unread`、`peer`（单聊对方）、`peer_read_seq`（单聊对方已读到哪，群聊 null） |
| GET | `/v1/im/conversations/:id/members` | 成员列表：`{user_id, display_name, handle, avatar, joined_at, last_read_seq}`（群聊气泡昵称、「N 人已读」） |
| GET | `/v1/im/conversations/:id/messages?before_seq&limit` | 历史，seq 倒序 |
| POST | `/v1/im/conversations/:id/messages` | `{client_id, kind: text|image, text?, image?}`；同 client_id 重放 200 |
| POST | `/v1/im/conversations/:id/read` | `{seq}` 已读；单聊推 `read` 事件给对方 |
| DELETE | `/v1/im/messages/:id` | 发送者撤回（软删，推 `message_deleted`） |
| GET | `/v1/im/sync?since&limit` | inbox 事件（`message` / `read` / `conversation_created` / `members_added` / `member_left` / `message_deleted`）+ `latest_seq`；事件的 `seq` 是用户级序号，消息在会话里的序号叫 `message_seq` |

陌生人规则（Follow Feature Requirements §3.3）：双方都没关注对方时，先开口的人只能发一条直到对方回复
（403 `GREETING_LIMIT`）；拉黑双向：不能建单聊也不能发（403 `BLOCKED`）。文字过前置审核（D6）。
不是成员的会话一律 404。举报消息走 `POST /v1/reports`（`target_type: message`，只有会话成员能举报，已撤回的 404）；
3 个不同人举报同一条就自动撤回并推 `message_deleted`，管理员 `remove_content` / `ban_user` 处置同样撤回。

**在线通道** `GET /v1/im/ws`（WebSocket 升级，握手头 `Authorization: Bearer <Firebase ID token>`）：连上先收
`{type:'hello'}`，之后每条 inbox 事件推成 `{type, seq, …payload, event_at}`；上行只认 `{type:'ping'}`（回 `pong`），
业务都走 REST。鉴权失败关闭码 4401 / 4403（封禁）/ 4404（没账号）。服务端 30 s ping，两个周期没 pong 断开；
不做离线队列——断线后按 `last_seq` 走 `/v1/im/sync` 补拉才是权威。

## 测试分层

| 目录 | 内容 |
|---|---|
| `test/domain/` | reducer 每条命令的成功与失败路径、Grant 物化顺序、时间与派生 |
| `test/ledger.test.ts` | 四条路径只用公开命令跑出 PRD §7.5 的全部目标数字 |
| `test/matrices.test.ts` | 会话切分矩阵、天气轮换矩阵、高频 bot 上界 |
| `test/http/` | 鉴权五项、409 三种、三个 DTO 的精确字段与四种隐私组合 |
| `test/db/` | 真库：单写者、幂等并发、版本门控顺序 |

**账本数字对不上时改内容表或 reducer，不许改断言。**

## 构建镜像

构建上下文是**仓库根目录**，不是 `server/`：服务端 import workspace 包 `blueprint-core`。

```bash
docker build -f server/Dockerfile -t farm-server:dev ..
```

## 部署

```bash
# 1. 建 ECS（默认 dry-run，打印规格与预估月费）
KEY_PAIR=my-key SSH_ALLOW_CIDRS=1.2.3.4/32 deploy/provision-ecs.sh
KEY_PAIR=my-key SSH_ALLOW_CIDRS=1.2.3.4/32 deploy/provision-ecs.sh --apply

# 2. DNS（先查后建或改，重跑安全）
deploy/dns.sh <公网IP>

# 3. 部署（只接受 CI 产出的 release-manifest.json 里的 digest）
DEPLOY_HOST=farm@<IP> deploy/deploy.sh release-manifest.json
```

`.env.production` 放在本机（gitignored），deploy 时推上去并 `chmod 600`。

## QA 白名单

`QA_PLAYER_IDS` 是逗号分隔的 player_id。只有他们建的农场带 `qa` 标记，导演命令才生效；
客户端不能自设。正式农场调 QA 命令返回 403。

## 重置农场

只在开发环境可用，三个条件同时成立：DSN 主机在 `192.168.124.0/24` 或 localhost、
`ALLOW_RESET=1`、只删 `qa=true` 或版本字段不符的农场。生产 DSN 直接拒绝。

## 备份与恢复

`deploy/backup.sh` 每天 03:30 UTC 由 supercronic 触发：`pg_dump` → age 公钥加密 → 传 OSS。
私钥只在本机 `~/.config/sensen/farm-backup.key`，服务器上没有。

`deploy/restore-drill.sh` 是恢复演练：拉最近一份 → 本机解密 → 恢复到 devserver 的
`sensen_farm_restore` → 比对表行数、表数量、10 个农场的 state 哈希、`max(version)` → 删库。
脚本硬拒绝非 devserver 网段与非该库名的目标。

## 线上真机 QA（2026-09-04 起的流程）

线上只有香港这一套环境，没有 staging——QA 造出来的匿名账号与农场都会留在生产库里。

```bash
# 1. 打包装机（约 130 MB；设备用 adb devices 确认）
godot --headless --path . --export-debug "Android" build/sensen-g2-debug.apk
adb install -r build/sensen-g2-debug.apk          # -r 保留 App 数据（安装密钥、已选城市/蓝图）
adb shell pm clear com.sensen.avatarphase1        # 想要一个全新玩家 / 回到选地流程时用

# 2. 客户端默认连 https://farm.sensenjoy.cn/v1；要指到别的服务器，往 user:// 放一行 URL
adb shell run-as com.sensen.avatarphase1 sh -c 'echo http://192.168.124.53:3000/v1 > files/server.txt'

# 3. 观察
adb logcat -s godot:* GodotApp:*                  # 客户端
ssh farm@47.76.226.41 'cd /opt/farm && docker compose logs -f app'   # 服务端
```

**导演模式（加速时间）**：农场里长按标题 3 秒开面板 → 任意按一下 → 面板显示
`This farm is not a QA instance · player <id>` → 把这个 id 加进服务器白名单：

```bash
ssh farm@47.76.226.41 'cd /opt/farm && sed -i "s/^QA_PLAYER_IDS=.*/QA_PLAYER_IDS=<id1>,<id2>/" .env && docker compose up -d app'
```

app 容器重建后再按即生效；480x = 3 分钟走完一个玩家日。白名单只认 player_id，
`pm clear` 之后是新玩家，要重新加。

检查清单在 Plane SGODOT-33。

## 环境分离与 QA 账号（D8）

三套环境只靠环境变量区分，代码不分支：

| 环境 | DATABASE_URL | FIREBASE_PROJECT_ID | 图片 | 用途 |
|---|---|---|---|---|
| dev | 本机 / 局域网 PG（`sensen_farm_dev`） | `gensen-overseas-dev` | `UPLOAD_LOCAL_DIR`（本地目录） | 开发机 + 真机联调 |
| qa | QA 库（独立实例） | `gensen-overseas-dev` | R2 dev 桶 | 内测 / 演示包（B8），`QA_PLAYER_IDS` 白名单 |
| prod | 生产库 | 生产 Firebase 项目（SSLAUNCH D1） | R2 生产桶 + 自定义域 | 上架 |

各环境一份 `.env`（`.env.example` 是模板），部署时 `/opt/farm/.env`（chmod 600）。云区域与实例等 SSLAUNCH D5 定。

QA / 演示账号用 `pnpm seed:qa`（`scripts/seed_qa.ts`）：Firebase 邮箱密码账号 → `POST /v1/auth/firebase` 建映射 →
设 handle / 昵称 → 互相关注。幂等，可反复跑；内置 alice / bob / carol，也可传 accounts.json。

## 好友位置（B5）

| 路由 | 说明 |
|---|---|
| `PUT /v1/location {lat, lng, accuracy_m?}` | 上报自己的最新位置。客户端只在地图页可见时上报（When-In-Use），30 s / 25 m 节流；服务端只存最新一条（`user_locations`），不存轨迹。越界 400 `SCHEMA`。 |
| `DELETE /v1/location` | 停止分享：删掉自己的位置，好友立刻看不到。 |
| `GET /v1/friends/locations` | 互相关注的人（好友）的最新位置 `{items:[{user_id, display_name, handle, avatar, lat, lng, accuracy_m, updated_at}]}`。单向关注、被拉黑的人不下发；超过 24 h 没更新的不下发；最多 200 个。 |

未配置 `locations` 时三条路由 503 `LOCATION_NOT_CONFIGURED`。位置进删号级联与数据导出（`locationAccountModule`）。
非好友「附近的人」（E2 的降精度网格）本期不做。

## 推送（D7）

| 路由 | 说明 |
|---|---|
| `PUT /v1/devices {token, platform}` | 注册设备 token（`ios` / `android`）。token 唯一：同一台设备换账号登录时归属跟着换。 |
| `DELETE /v1/devices {token}` | 注销；只能注销自己名下的 token。 |

新消息落库后，会话成员里**不在线**（WebSocket 没连着）且不是发送者的人各收一条通知。
通知里**不放消息正文**，只有「谁发来一条消息 / 一张图」+ `conversation_id`，点开由客户端按 seq 补拉——
正文不经过 Google 的推送通道，锁屏也不泄露（E2）。已下架（hidden）的消息不推；
幂等重放（`created=false`）不重复推。FCM 回报失效的 token 会立即从表里删掉。

发送走 FCM HTTP v1，**不引 firebase-admin**：服务账号 JSON → RS256 assertion → OAuth2 access token（缓存到过期前 60 秒）
→ `POST /v1/projects/<id>/messages:send`。iOS 由 FCM 代投 APNs，所以只需在 Firebase 控制台挂 APNs key（SSLAUNCH A9）。
配置：`FIREBASE_SERVICE_ACCOUNT`（JSON 内容）或 `FIREBASE_SERVICE_ACCOUNT_FILE`（文件路径）；两者都没有时推送空转，
设备 token 照常收（便于先接客户端）。设备 token 进删号级联与数据导出（导出只给平台与时间，不给 token 本身）。

## 遥测（E2 / E4）

`SENTRY_DSN` 配了才上报未捕获异常；内容先过 `src/http/telemetry.ts` 的脱敏（URL 去 query，
经纬度 / 正文 / 昵称 / 邮箱 / token 一律 `[redacted]`）。没配就是空转，错误只留在进程日志里。

## 语音房（D5）

| 路由 | 说明 |
|---|---|
| `GET /v1/voice/rooms` | 开着的房间列表（最多 50） |
| `POST /v1/voice/rooms {title}` | 建房，建者即房主并自动上麦 |
| `POST /v1/voice/rooms/:id/join` | 进房，先当听众；返回房间状态 + 自己的 LiveKit token |
| `POST /v1/voice/rooms/:id/leave` | 离开；**房主离开即关房**（没人主持的公共麦是审核风险） |
| `POST /v1/voice/rooms/:id/stage {on, user_id?}` | 上下麦。自己上下自己；房主可带 `user_id` 请人下麦 |
| `POST /v1/voice/rooms/:id/mute {user_id, muted}` | 房主静音 / 解除；被静音的人立刻下麦且上不去 |
| `POST /v1/voice/rooms/:id/token` | 续一把 token（到期前换） |

**能不能说话由服务端签的 token 决定**：每次上下麦 / 被静音 / 续期都返回一把新的 LiveKit
access token，`video.canPublish` 就是麦克风闸门——客户端改本地代码也推不上流。房间状态
（谁在麦上、谁被静音）在我们库里（`voice_rooms` / `voice_room_members`），LiveKit 只当音频管道，
音频不经过我们、也不落库。麦位 8 个（含房主），房间 50 人。

签名不引 livekit-server-sdk：HS256 + video grant 一共二十行（`src/http/voice.ts`）。
配置：`LIVEKIT_URL` / `LIVEKIT_API_KEY` / `LIVEKIT_API_SECRET`，缺一则语音路由 503（SSLAUNCH D2 给正式 key）。
删号级联：本人建的房关掉、从别人的房里退出。

