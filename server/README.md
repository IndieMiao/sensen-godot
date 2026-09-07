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
