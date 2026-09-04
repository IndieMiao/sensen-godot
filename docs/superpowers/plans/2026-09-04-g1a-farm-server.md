# G1-A 农场服务端 Implementation Plan

> 逐任务执行；每个 Task 独立评审后再进下一个。Task 之间的接口在「Interfaces」里钉死，不得临时改。

**Goal:** 在 `server/` 建立权威状态服务：纯函数领域层覆盖 PRD §6-§9 全部数值逻辑，七日账本四条路径以逐条命令脚本从 `create_farm` 走到 D6 并复现全部目标数字；Fastify + PostgreSQL 提供单写者、幂等、版本化命令接口；镜像按 digest 部署到新建香港 ECS，域名 `farm.sensenjoy.cn`。

**Design:** `docs/superpowers/specs/2026-09-04-g1a-farm-server-design.md` v4（经 Codex 三轮对抗评审）。本计划的每条规则都能在 spec 里找到出处；**遇到 spec 未覆盖的情况先停下问，不要自行发明规则**。

**Tech Stack:** Node 22 LTS、pnpm workspace、TypeScript（ESM/NodeNext/strict）、Fastify 5 + TypeBox、Drizzle ORM + PostgreSQL 16、luxon、pino、vitest、tsx；Godot 侧 gdUnit4。

## Global Constraints

- **领域层是唯一算数的地方。** HTTP 不碰余额，DB 不解释命令，reducer 不做 IO、不读 `Date.now()`、不读 env。
- **时间只采样一次**：拿到行锁后 `effectiveNow = max(sample(), clock.last_effective_now)`，此后 derive、reducer、日志、响应 `server_time` 全用它。
- **内容表是单一来源**：`assets/farm/data/*.json`，Godot 与服务端读同一份；`content_version = sha256(JCS([{name,content},…]))`，`name` 升序。
- **数字只写在内容表里**，代码里不出现游戏数值字面量（测试断言除外）。
- **账本断言不许改**：目标数字对不上说明内容表或 reducer 错了。
- TS 相对导入带 `.js` 后缀；每个包 `pnpm typecheck` 与 `pnpm test` 必须干净。
- 用户可见文案一律英文（见全局约定）；代码注释中文，写清「为什么」而非「做了什么」。
- 提交粒度：一个 Task 一次提交，信息首行 `feat(server): …` / `fix(blueprint): …`，正文写清踩到的坑。

## File Structure

```
pnpm-workspace.yaml · package.json（根，仅 workspace 脚本）
packages/blueprint-core/   types.ts parse.ts validate.ts canonical.ts fairness.ts golden/corpus.json
tools/geo_blueprint/       改为依赖 blueprint-core；新增 rechecksum/r2 输出
server/
  src/domain/  state.ts commands.ts reducer.ts handlers/*.ts content.ts time.ts derive.ts errors.ts version.ts
  src/http/    app.ts auth.ts dto.ts routes/{auth,regions,farms,commands,health}.ts
  src/db/      schema.ts apply.ts migrate.ts reset.ts
  test/        domain/ ledger.test.ts fixtures/ledger_*.json weather_matrix.test.ts sessions_matrix.test.ts
               highfreq.test.ts time.test.ts http/ db/
  deploy/      docker-compose.yml Caddyfile cloud-init.sh provision-ecs.sh deploy.sh smoke.sh
               backup.sh restore-drill.sh devserver-pg.compose.yml crontab
assets/farm/data/  crops.json weather_script.json xp.json relationships.json chapters.json
                   requests.json recipes.json economy.json
assets/blueprints/<id>/r2/   七份新 revision
.github/workflows/server.yml
```

---

### Task 1: `packages/blueprint-core` + r2 蓝图 + 公平口径

**Files:** 新建 `packages/blueprint-core/{package.json,tsconfig.json,src/{types,parse,validate,canonical,fairness}.ts,golden/corpus.json,test/*.test.ts}`；改 `tools/geo_blueprint/src/{writer,anchors,cli,pipeline}.ts` 与 `package.json`；改 `modules/blueprint/{blueprint.gd,fairness.gd}`；改 `tests/blueprint/{test_blueprint,test_fairness,test_ground_mesh}.gd` 与 `tests/fixtures/blueprints/fix_grid/r1/farm_blueprint.json`；新建 `assets/blueprints/*/r2/`；改 `assets/farm/data/regions.json`；新建根 `pnpm-workspace.yaml` 与 `package.json`。

**Interfaces:**
- `canonical(bp): string` 按 spec §5.1 文法，读 `cell_mm` / `play_area_mm` 整数字段；`checksum(bp) = sha256hex(canonical)`。
- `validate(bp): string[]`（空数组即通过），规则见 spec §5.2。
- `fairness(bp, grid): { far_bed_9_s, far_bed_12_s, walk_tour_9_s, walk_tour_12_s, tour_s }`。
- `golden/corpus.json`: `[{ name, blueprint, canonical, checksum } | { name, blueprint, reject: code }]`，≥8 组。

**Steps:**
- [ ] 建根 workspace（`packages/*`、`tools/geo_blueprint`、`server`），根 `package.json` 只放 `test`/`typecheck`/`build:image` 脚本。
- [ ] 写 `types.ts` 与 `parse.ts`：r2 蓝图新增权威整数字段 `cell_mm`、`play_area_mm`；旧浮点 `cell_m`/`play_area_m` 保留为派生展示值且不进 canonical。非整数、≤0、超 `[1,100000]` → `INVALID_NUMBER`。
- [ ] 先写 `test/canonical.test.ts` 与 `golden/corpus.json`（含 `cell_mm` 1000/2500/333 与四类拒绝样本），确认 RED。
- [ ] 实现 `canonical.ts` 与 `validate.ts` 至 GREEN。`validate` 必须在 checksum 之前跑。
- [ ] 实现 `fairness.ts`：新增第四畦指标；门槛为绝对秒（`far_*_s ≤ 12`、六蓝图 `walk_tour_*_s` 两两差 ≤ 5），删掉相对 spread。
- [ ] `tools/geo_blueprint` 改为 import 本包，删除自己的三份实现；`cli.ts validateAll` 用新门槛。
- [ ] 新增 CLI `build --revision 2`：从 `cache/` 的 OSM 响应重出七份到 `r2/`（几何不变），写 `cell_mm`/`play_area_mm` 与新 checksum、`report.json` 新字段；`r1/` 一个字节都不动。
- [ ] `regions.json` 的 `revision` 改 2。
- [ ] Godot 侧 `blueprint.gd` 重写 `canonical/verify_checksum` 并加载同一 `golden/corpus.json`（用 `FileAccess` 读 `res://` 下的拷贝或经 `.gdignore` 的相对路径，二选一，在 PR 里说明）；`fairness.gd` 逐字对齐。
- [ ] 更新 `fix_grid` fixture 与所有钉死 checksum 的测试。
- [ ] `pnpm -r test` 与 `tools/run_tests.sh` 全绿。

**Acceptance:** golden corpus 双端逐字节一致；七份 r2 通过 `validate` 与新公平门槛；r1 未被修改（`git diff --stat assets/blueprints/*/r1/` 为空）。

---

### Task 2: 内容表（8 张 JSON）

**Files:** 新建 `assets/farm/data/{crops,weather_script,xp,relationships,chapters,requests,recipes,economy}.json`；新建 `server/src/domain/content.ts` 与 `server/test/domain/content.test.ts`。

**Interfaces:** `loadContent(dir): Content`（TypeBox 校验，失败抛 `ContentError`）；`contentVersion(content): string`。`Content` 的类型定义即 spec §4.5 的表。

**Steps:**
- [ ] 逐张写 JSON，**每个字段带 PRD 行号注释**（用 `_note` 兄弟键，不进哈希的话要在 `content_version` 计算里明确排除；简单起见：注释单独放 `_notes` 顶层对象并**参与**哈希）。
- [ ] `crops.json`：R/L/C/H 时长 4/8/12/18 h、种子 4/6/8/10、售价 8/12/16/19、产量 1、`d0_tutorial_duration_ms: 180000`。
- [ ] `weather_script.json`：`["sunny","rain","sunny","sunny","rain","wind","sunny"]`、`care_action` 映射、`protected_slots: [0,1,5]`。
- [ ] `xp.json`：六来源与上限、阈值 `[0,40,80,120,160,220,290]`。
- [ ] `relationships.json`：三居民 `available_from_chapter` 0/1/5、阶段阈值（初见 0-14 / 相识 15-44 需首次见面 / 熟悉 45-89 需共同事件）、点数（对话 2、赠礼 6 每人 2 次、个人请求 15、共同活动 25）、赠礼清单（苗圃 {R}、小馆 {L,R}、修缮师 {H,L}）、`personal_story` 归属 D1 小馆 / D3 苗圃 / D5 修缮师、共同活动 D3 小馆 / D6 苗圃。
- [ ] `chapters.json`：七章 `min_facts`（PRD §9.3 逐字转成 flag 名）、`unlocks`、`grants`（D0 `{R:6 tutorial, L:3}`、D1 `{L:3}`、D2 `{C:2}`、D3 `{H:2}`、D4 `{H:2}`、D6 `{C:1,H:1,L:1}`）、`life_choice_crop` `[R,L,R,L,H,L]`（D1-D6）、`shared_events`、`subsidy`（D1 weather_story 20、D6 nursery_built 60）。
- [ ] `requests.json`：四条，见 spec §4.5。
- [ ] `recipes.json`：`salad{C:1,L:1}` 摊位价 36、`tea{H:1}` 摊位价 24、回购价 24。
- [ ] `economy.json`：初始 180、摊位 100/日（**含回购**）、工具 240、扩地 400、`expansion_seed_basket {R:3,L:3,C:3,H:3}`、补贴 20/60、回购 1/日、种苗包 `{R:3}` 首周上限 3。
- [ ] `content.ts` 做 TypeBox 校验与 `contentVersion`；测试：改任一字节 `content_version` 必变；缺字段必抛。

**Acceptance:** 8 张表校验通过；`content_version` 可复现；每个数值能指回 PRD 行号。

---

### Task 3: 领域层骨架（状态、命令 schema、时间、派生）

**Files:** `server/src/domain/{state,commands,time,derive,errors,version}.ts`；`server/test/domain/{state,time,derive}.test.ts`。

**Interfaces:**
- `createInitialState(args): FarmState`（spec §4.1 字段全集）。
- `Command` 联合类型 + 每条的 TypeBox schema（`additionalProperties:false`，数组 `minItems 1 / maxItems 12 / uniqueItems`）。
- `playerDayId(nowMs, tz): string`、`dayStart(day, tz): number`。
- `derive(state, now): Derived`。
- `DOMAIN_VERSION` / `STATE_SCHEMA_VERSION` 常量。

**Steps:**
- [ ] 先写 `time.test.ts`：04:00 两侧；LA 2026-11-01 两次 01:30（-07/-08 各一）；2026-03-08 春季跳时；上海无 DST。RED → 实现 `time.ts`（luxon）。
- [ ] 写 `derive.test.ts`：`ready_at` 为 null 不成熟；`ready_at <= now` 成熟；跨玩家日推进 `weather_day_index` 与 `field_condition`；`chapter_index` 到 6 冻结但天气索引继续。RED → 实现。
- [ ] 26 条命令的 TypeBox schema 与前置条件表（spec §4.2 全部字段；`set_location_visible`/`set_visit_access`/`give_gift`/`choose_nursery_appearance` 等必须写出完整 payload）。
- [ ] `errors.ts` 码表（spec §7.4）。

**Acceptance:** 时间与派生测试全绿；`commands.ts` 编译期穷尽（`switch` 缺分支即类型错误）。

---

### Task 4: reducer 农事命令（G1 客户端用的 9 条）

**Files:** `server/src/domain/{reducer,handlers/{farm,cells,seeds,settings}.ts}`；`server/test/domain/{cells,seeds}.test.ts`。

**Steps:**
- [ ] `reducer(state, cmd, ctx): Ok | Err`，纯函数，失败整体丢弃。
- [ ] `materializeDay()` **严格按 spec §4.2 三步**：推进时钟 → 只在真正开新章时先清 `bound` 再开章再发 Grant（`grants_issued` 幂等）→ 漏日不清。写判别性测试：D0 的 3L 若未播种，D1 开章时被清但随即发新的 3L；已播种的不受影响。
- [ ] `create_farm`（校验 checksum 与 revision，物化 D0）、`clear_cells`、`till_cells`、`sow_cells`、`apply_care`、`apply_optional_care`、`harvest_cells`、`buy_seeds`、`set_location_visible`、`set_visit_access`。
- [ ] XP 规则：首次清理 1/格、收获 2/株每日封顶 9、首次作物 8、当日照料完成 15、首次田况 5。
- [ ] 每条命令至少一条成功与一条失败测试。

**Acceptance:** 领域测试全绿；`sow → apply_care → 时间推进 → harvest` 全链路在测试里跑通。

---

### Task 5: reducer 经济/居民/章节命令 + 四条账本脚本

**Files:** `server/src/domain/handlers/{stall,cook,residents,requests,engineering,growth,claims,events}.ts`；`server/test/ledger.test.ts` 与 `server/test/fixtures/ledger_{tool,field}_{life,sell}.json`；`server/test/{weather_matrix,sessions_matrix,highfreq}.test.ts`。

**Interfaces:** 夹具行格式 `{ day: 0..6, session?: number, type, payload }`；runner 按 `day` 用 QA 时钟推进到该玩家日再逐条 apply。

**Steps:**
- [ ] 实现其余命令：`sell_at_stall`（顺序成交至 100，含回购占额，累加 `sales_facts`）、`sell_to_buyback_box`、`cook_dish`、`talk_to_resident`、`give_gift`、`resolve_life_choice`、`submit_request`、工程篮三条、`set_growth_intent`、`purchase_growth_choice`（固定篮 84 + 400 原子、reserved bed 置 `tilled`）、`choose_nursery_appearance`、`claim_subsidy`、`claim_seedling_pack`、`attend_shared_event`、`record_visit_return`。
- [ ] **写四条账本脚本**：从 `create_farm` 起只用公开命令，按 PRD §7.5 逐日复现。断言钱包 210/287/325/362/413/218/305、扩地 46/145、XP 49/95/128/179/230/268/301、关系 58/62/31、出售优先 376/216 与 52/50/19、两路账户价值 545。**数字对不上改内容表或 reducer，不改断言。**
- [ ] 天气矩阵：D2/D3/D4/D6 三种田况轮换 4 组，最终累计数字不变。
- [ ] 会话矩阵：同一脚本按每日 1/2/3 次会话切分，结果一致。
- [ ] 高频 bot：贪心策略（每日卖光、优先做菜、回购与种苗包按上限），断言 D6 账户价值 ≤ 981 并把实测值写进测试名。

**Acceptance:** 四条账本 + 两个矩阵 + 高频全绿。**这是本计划的核心验收点**。

---

### Task 6: HTTP + 鉴权 + DTO

**Files:** `server/src/http/**`；`server/test/http/*.test.ts`。

**Steps:**
- [ ] `buildApp(deps)` 便于 `app.inject`；pino 日志；全局错误处理器映射 spec §7.4 码表。
- [ ] 鉴权：`install_key` HMAC（pepper 从 env）；每 player ≤5 活跃 token（按 `last_used_at` 淘汰，插入与淘汰在同一事务）；90 天闲置过期；`DELETE /auth/token`、`DELETE /auth/tokens`、`POST /auth/rotate-install-key`（**同时需 token 与当前 install_key**，成功后撤销全部会话）；匿名端点 IP 限流 10/小时。
- [ ] 路由：`/regions`（只给 id/timezone/candidates）、`POST /farms`、`GET /farms/me`、`POST /farms/me/commands`、`/healthz`。
- [ ] 三个 DTO（`OwnerFarmView` / `VisitorSnapshot` / `NearbyEntry`）与 `VisitorProp`；四种隐私组合表；测试用 TypeBox 校验**精确字段集**而不是扫禁用键名。
- [ ] 响应 `server_time` 一律等于本次 `effectiveNow`。

**Acceptance:** HTTP 测试全绿，含鉴权五项、409 三种、三 DTO 精确字段、四种隐私组合。

---

### Task 7: PostgreSQL 存储与事务

**Files:** `server/src/db/**`、`server/drizzle/`；`server/test/db/*.test.ts`；`server/deploy/devserver-pg.compose.yml`。

**Steps:**
- [ ] 在 devserver `192.168.124.53` 起 `postgres:16` 容器（只绑该地址，volume `pgdata_farm`，建三个库与受限角色）。
- [ ] Drizzle schema 按 spec §8（含 `farm_creations.payload_hash`、`farm_snapshots` 的三个版本列）。
- [ ] `applyCommand()` **严格按 spec §7.3 伪代码的步骤顺序**：行锁 → 幂等查表与重放 → 版本门控 503 → 采样时间 → `base_version` 409 → derive → reducer → 写日志（含 rejected）→ 成功才 +1 版本，两种结果都推进 `last_effective_now`。
- [ ] `reset.ts`：三重条件 + 二次确认，生产 DSN 直接拒绝。
- [ ] 测试 A：20 并发同 `base_version` → 恰一条 applied；测试 B：按 409 换 key 重发 → 全部 applied、版本无空洞；同键并发只应用一次；不同农场并行。
- [ ] CI 起 `postgres:16` service，`CI=1` 且缺 `TEST_DATABASE_URL` 直接失败。

**Acceptance:** DB 测试在真库上全绿；CI 工作流绿。

---

### Task 8: 部署与备份恢复

**Files:** `server/{Dockerfile,.dockerignore,.env.example,README.md}`；`server/deploy/*`；`.github/workflows/server.yml`。

**Steps:**
- [ ] 多阶段 Dockerfile，构建上下文为仓库根。
- [ ] CI 构建并推 ACR，产出 `release-manifest.json {git_sha, image_digest, content_version, domain_version}`。
- [ ] `provision-ecs.sh`：`--dry-run` 先打印规格与预估月费**并等用户确认**；`--key-pair` 与 `SSH_ALLOW_CIDRS` 必填，后者为空即退出；cn-hongkong / `ecs.e-c1m2.large` / Ubuntu 24.04 / 40 GiB。
- [ ] DNS：查后 create-or-update，幂等。
- [ ] `deploy.sh` 只接受 digest；先 ACR login 再 pull/up；末尾跑 `smoke.sh`。
- [ ] compose：四个服务、healthcheck、`mem_limit`、日志轮转、`caddy_data` 卷；`backup` 用 supercronic 跑 `crontab`。
- [ ] `backup.sh`（pg_dump → age 加密 → OSS 只写子账号）与 `restore-drill.sh`（只接受 devserver 网段与 `sensen_farm_restore` 库名；比对表行数、迁移版本、10 农场 state 哈希、`max(version)`）。
- [ ] `README.md`：本地起服、连 devserver、跑测试、构建镜像、部署、QA 白名单、reset 农场。

**Acceptance:** `farm.sensenjoy.cn/v1/healthz` 200 且 TLS 有效；`smoke.sh` 与 `restore-drill.sh` 通过。

---

## 出口

- `pnpm -r test` 与 `tools/run_tests.sh` 全绿；CI 绿并产出 manifest。
- 四条账本、天气矩阵、会话矩阵、高频 bot、DB 并发测试全部通过。
- 线上冒烟与恢复演练通过。
- Plane：SGODOT-24 下八张子卡逐条关闭；SGODOT-28 关闭。

## 估算

Task 1 1.5 ｜ 2 0.5 ｜ 3 1 ｜ 4 1.5 ｜ 5 2.5 ｜ 6 1.5 ｜ 7 1 ｜ 8 1.5 = **11 人天**
