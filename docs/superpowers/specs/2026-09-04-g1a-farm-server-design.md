# G1-A 农场服务端（领域层 + 骨架 + 部署）设计 v3

日期：2026-09-04 ｜ 状态：v3，待 Codex 三审 ｜ 版本史：v1 → Codex 评审（5C/13I/3M）→ v2 → Codex 复审（关闭 8、部分 12、未关 1、新增 12）→ v3 逐条关闭 ｜ 上游方案：`docs/superpowers/plans/2026-09-03-map-farm-mvp-implementation.md` §3 D4 / §4.2 / §9 ｜ PRD：`docs/product/map-farm-life-sim-direction.md` v0.4 ｜ Plane：SGODOT-24 28 29 30 31

## 0. 一句话

在 `server/` 建权威状态服务：纯函数领域层覆盖 PRD §6-§9 全部数值；七日账本四条路径以**逐条命令脚本夹具**从 `create_farm` 走到 D6 并唯一复现全部目标数字；Fastify + PostgreSQL 单写者、幂等、版本化；镜像按 digest 部署到新建香港 ECS，域名 `farm.sensenjoy.cn`。客户端只做视觉预测。

## 1. 范围

**做**：`packages/blueprint-core`（类型、校验、canonical、公平，三方共用）· 领域层 · 四条账本夹具与三类矩阵测试 · HTTP v1 与鉴权 · PostgreSQL 存储与事务 · 三个 DTO 与隐私契约 · 部署与备份恢复 · devserver 开发库。

**不做**：Godot 玩法代码（G1-B）· `nearby`/`snapshot` 实现（G2，本 spec 只定 DTO 与开关）· 居民文本与布景（G3）· 装饰商店 · 跨内容版本在线迁移（G4）· 第一天节奏调整（SGODOT-31，时长全在内容表，届时只改数）。

## 2. 已拍板

| # | 决策 |
|---|---|
| ① | checksum 收紧并三方共用 `blueprint-core`；**输出 r2，r1 原样保留**（v3 修正，见 §5.4） |
| ② | 服务端永不下发经纬度/街名；快照仍带 `layout_patch_id`（MVP 折衷，SGODOT-29）；`location_visible` 默认 true；`visit_access` 默认 `only_me` |
| ③ | 公平口径绝对秒数且覆盖第四畦 |
| ④ | 新建 HK ECS 2C4G + `farm.sensenjoy.cn`；开发/测试库在 devserver `192.168.124.53` |
| ⑤ | 先服务端；领域层覆盖 PRD §7 全部 |
| ⑥ | 扩地第四畦到手即已清理已翻土，不计清理 XP |
| ⑦ | 料理上摊溢价：沙拉 36、茶 24；门口回购箱茶 24，**每玩家日 1 次且首周至多 1 次，不占摊位预算**（v5 订正，见 §4.4） |
| ⑧ | 安全线种苗包 = 3 枚绑定小萝卜，**首周至多 2 次**（v5 订正，见 §4.4） |
| ⑨ | D7+ 不开新章；田况按**独立的 `weather_day_index`** 循环（v3 修正） |
| ⑩ | 第一天节奏问题记录不解决（SGODOT-31） |

## 3. 架构

```
client ─HTTPS/JSON─▶ Caddy ─▶ Fastify ─▶ applyCommand() 事务 ─▶ domain（纯函数）
```

**四条铁律**

1. 只有 reducer 算数。
2. 时间在**拿到行锁后采样一次**，此后不再采样（§7.3 伪代码钉死）。
3. 内容表 `assets/farm/data/*.json` 是单一来源，两端共用；`content_version = sha256(JCS([{name, content}, …]))`，数组按 `name` 升序、`content` 为该文件的 JCS 规范化形式——文件名进入哈希输入，避免拼接歧义（Important 4 / O-I6）。
4. 领域层不做 IO，不读 `Date.now()`，不读环境变量。

### 3.1 目录

```
pnpm-workspace.yaml · package.json（根）
packages/blueprint-core/  types.ts parse.ts validate.ts canonical.ts fairness.ts golden/corpus.json
tools/geo_blueprint/      改为依赖 blueprint-core
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
.github/workflows/server.yml
```

Docker 上下文 = 仓库根；`.dockerignore` 只放行 `package.json pnpm-*.yaml packages/ server/ assets/farm/data/ assets/blueprints/*/r*/farm_blueprint.json`。

## 4. 领域模型

### 4.1 列 vs 状态

**身份与索引只在列**：`farms(id, owner_id, region_id, layout_patch_id, blueprint_revision, blueprint_checksum, content_version, domain_version, state_schema_version, version, qa, qa_clock, visit_access, location_visible, created_at, updated_at)`。

`state jsonb`（`schema_version` 在列上，不在 JSON 里）：

| 字段 | 内容 |
|---|---|
| `clock: { player_day_id, chapter_index, weather_day_index, field_condition, last_effective_now }` | `chapter_index` 到 6 冻结；`weather_day_index` 每个玩家日 +1 永不冻结（N-I2） |
| `wallet` · `inventory: { seeds[crop]:{bought,bound}, produce[crop], dishes[dish] }` | 初始 180 |
| `cells[cell_id]: { state: wild\|cleared\|tilled\|sown\|growing, crop, care_weather, care_done_at, ready_at, careful }` | 无 `ripe`，成熟是派生 |
| `beds_unlocked: 3\|4` · `tools:{row_tool}` · `growth_choice:{intent,purchase,locked_at,transaction_id}` | |
| `stall:{day,settled}` · `buyback:{day,tea_sold}` · `seedling_packs:{days[],count}` | 摊位 100/日；茶 1/日；种苗包见 §4.4 |
| `engineering:{reserved[],submitted[]}` · `nursery:{stage,appearance}` | |
| `residents[id]:{points,stage,first_met_day,talked_day,gifts_given,request_done,shared_event_done}` | |
| `chapters[n]:{status,activated_day,step_flags,grants_issued}` | `grants_issued` 是 Grant 幂等键 |
| `requests_done[]` · `life_choices[chapter]` · `sales_facts[chapter][crop]: qty` · `subsidies_claimed[]` · `handbook[]` | `sales_facts` 由 `sell_at_stall` 按当前章节与实际成交项累加，是 `resolve_life_choice(sold)` 的唯一校验依据（V3-I1） |
| `xp:{total,first_clear_cells[],first_harvest_crops[],first_weather[],first_recipes[],harvest_counted:{day,n},care_bonus_day}` | 等级派生 |

### 4.2 命令集

封套 `{ idempotency_key, base_version, type, payload }`；数组 `minItems 1 / maxItems 12 / uniqueItems`；整批原子。

| type | payload | 规则 |
|---|---|---|
| `create_farm` | `region_id, layout_patch_id, blueprint_revision` | checksum 匹配；一人一农场；物化 D0 |
| `clear_cells` / `till_cells` | `cell_ids` | 状态机推进；服务端不限每命令格数（`row_tool` 只是客户端手势便利，PRD L408）；首次清理 +1 XP/格 |
| `sow_cells` | `cell_ids, crop, lot: bought\|bound` | `care_weather = clock.field_condition`；`ready_at = null`；D0 首批 6R 用 180 s |
| `apply_care` | `cell_ids, kind` | `kind` 须匹配格的 `care_weather`；写 `care_done_at` 与 `ready_at`；当日全部已播格完成 → +15（每日一次）；首次该田况 +5 |
| `apply_optional_care` | `cell_ids` | 成熟前一次 |
| `harvest_cells` | `cell_ids` | 用 `derived.ripe_cells`；+1 产物/株；+2 XP/株（每日 ≤9）；首次该作物 +8；格回 `tilled` |
| `buy_seeds` | `crop, qty` | C 需 D2、H 需 D3 |
| `set_location_visible` / `set_visit_access` | | |
| `sell_at_stall` | `items[{kind,id,qty}]` | 作物 8/12/16/19、沙拉 36、茶 24；按 `items` 顺序成交至 100，返回 `settled/sold[]/unsold[]`；**不写生活槽**，但把实际成交项累加进 `sales_facts[chapter][crop]`（N-I11 / V3-I1） |
| `sell_to_buyback_box` | `qty:1` | 茶 24，1/玩家日，**占摊位当日预算**（V3-C1） |
| `cook_dish` | `recipe` | D3 起；首次 +10 XP |
| `talk_to_resident` / `give_gift` | | 每日首次 +2；赠礼 +6（每人首周 2 次），需线索与作物匹配 |
| `resolve_life_choice` | `chapter, choice: gift\|keep\|sold` | **唯一写生活槽的命令**；槽空才可写；校验对应事实已成立：`gift` 需 `residents[*].gifts_given` 含本章作物；`keep` 需库存有该作物；`sold` 需 `sales_facts[chapter][life_choice_crop] >= 1` |
| `submit_request` | `request_id, items[]` | 精确匹配 `requests.json`；每请求一次；原子 |
| `reserve_engineering` / `withdraw_engineering` / `submit_engineering` | `items[]` | D3 起；预留物不可售/赠/烹；提交原子 |
| `set_growth_intent` | `tool\|field` | D5 起 |
| `purchase_growth_choice` | `choice, transaction_id` | **无 `seed_order` 参数**：`field` 扣 400 + `economy.expansion_seed_basket`（固定 3R+3L+3C+3H = 84）并入库，reserved bed 三格置 `tilled`；`tool` 扣 240；原子；成功锁另一项（C1） |
| `choose_nursery_appearance` · `claim_subsidy` · `claim_seedling_pack` · `attend_shared_event` | | 见 §4.4 |
| `record_visit_return` | `visited_farm_id` | 只写 D4 flag |
| `qa_set_clock` / `qa_skip_days` / `qa_set_weather` | | 仅 `qa=true`；同封套同幂等；参数域见 §7.3 |

**Grant 与章节物化的原子顺序（N-C1，实现必须逐字照做）**：

```
materializeDay(state, derived):
  1. state.clock.player_day_id   = derived.player_day_id
     state.clock.weather_day_index += 跨过的玩家日数
     state.clock.field_condition = weather_script[weather_day_index mod 7]
  2. if 上一章 status == done and chapter_index < 6:
       a. 清空 inventory.seeds[*].bound        ← 先清，且只在真正开新章时清
       b. chapter_index += 1；chapters[n].status = active
       c. if not chapters[n].grants_issued: 发放 chapters[n].grants；grants_issued = true
  3. 不开新章时不动 bound（漏日不惩罚）
```

### 4.3 时间与派生

- `playerDayId(nowMs, tz)`：luxon 转城市时区，小时 < 4 归前一天。
- `derive(state, now)` → `{ player_day_id, weather_day_index, field_condition, chapter_index_next, ripe_cells[] }`；**读路径同样先取 `now = max(sample(), clock.last_effective_now)` 再 derive，但不写回**，因此 GET 结果不会因时钟回拨而倒退（O-I3）；`ripe = state=='growing' && ready_at != null && ready_at <= now`。GET 用它但**不落库不改版本**。
- 田况 = `weather_script[weather_day_index mod 7]`；`weather_day_index` 从 0 起每个玩家日 +1，与 `chapter_index` 解耦（N-I2）。
- `ready_at = care_done_at + crops[crop].duration_ms`。
- **正式农场时钟守卫**：`effective_now = max(sampled_now, clock.last_effective_now)`，回拨时记 `warn` 日志但继续（NTP 微回拨不应让农场不可用）；QA 农场回拨直接 422 `CLOCK_REGRESSION`（N-I6）。

### 4.4 数值不变量

- `account_value = wallet + (row_tool ? 240 : 0) + (beds_unlocked==4 ? 400 : 0)`。
- 摊位：作物与料理共用 100/玩家日。**门口回购箱不占这份预算**——PRD L544-547 自己把茶回购算在「居民请求」224 那一栏（30+45+55+70+24），摊位栏 381 不含它；且账本 D4 当天摊位 79 + 回购 24 = 103 会超 100，计入预算会让目标账本直接跑不通（v5 实测发现，v4 的写法是错的）。
- **高频上界**：闸门改为「回购**周上限 1 次**（PRD 全周恰好用一次）+ 种苗包**周上限 2 次** + 收紧空仓判定」。同一套宽松整数模型给出 **972 ≤ 981**（PRD L431 的 1.8×）；周上限 3 时是 982，只差 1 分越线，所以取 2。§9 的高频 bot 测试断言实测值并写进测试名。
- 绑定种子禁售禁赠；只在开新章时清零。
- 工程篮预留物不进入售/赠/烹。
- **安全线种苗包（N-I1 收紧）**：同时满足 ① `wallet < min(crops[*].seed_price)` ② 无任何 `produce` 与 `dishes` ③ 无 `growing`/`sown` 格 ④ 无任何种子（bought 与 bound）⑤ 无 `engineering.reserved` ⑥ 未达周上限。每玩家日至多一次，**首周至多 2 次**。
- 扩地：固定篮 84 金币，与 400 同一原子事务。

### 4.5 内容表

| 文件 | 关键内容 |
|---|---|
| `crops.json` | R/L/C/H 时长 4/8/12/18 h、种子 4/6/8/10、售价 8/12/16/19、产量 1；`d0_tutorial_duration_ms: 180000` |
| `weather_script.json` | `["sunny","rain","sunny","sunny","rain","wind","sunny"]`；`care_action` 映射；`protected_slots: [0,1,5]` |
| `xp.json` | 六来源与上限；阈值 `[0,40,80,120,160,220,290]` |
| `relationships.json` | 三居民 `available_from_chapter`（0/1/5）、阶段阈值、点数来源、赠礼清单（苗圃 {R}、小馆 {L,R}、修缮师 {H,L}）、`personal_story` 归属、共同活动归属 |
| `chapters.json` | 七章 `min_facts`（PRD §9.3 逐字）、`unlocks`、`grants`（D0 `{R:6 教学, L:3}`、D1 `{L:3}`、D2 `{C:2}`、D3 `{H:2}`、D4 `{H:2}`、D6 `{C:1,H:1,L:1}`）、`life_choice_crop`（D1 R、D2 L、D3 R、D4 L、D5 H、D6 L）、`shared_events`、`subsidy` |
| `requests.json` | `d0_tutorial_buyback{chapter:0, items:{R:3}, coins:30}`、`d1_bistro{1,{L:3},45,personal_story}`、`d3_nursery{3,{C:2,L:1},55,personal_story}`、`d5_restorer{5,{salad:2},70,personal_story}` |
| `recipes.json` | `salad{C:1,L:1}`、`tea{H:1}`；`stall_price 36/24`；`buyback tea 24` |
| `economy.json` | 初始 180、摊位 100、工具 240、扩地 400、`expansion_seed_basket {R:3,L:3,C:3,H:3}`、补贴 20/60、回购 1/日、种苗包 `{R:3}` 上限 3 |

## 5. 蓝图核心包

### 5.1 canonical 逐字节文法

```
<layout_patch_id>|<format>|<revision>|<grid.x>,<grid.y>|<cell_mm>|<play_area_mm>
|<walkable>|<cultivable>|<buildable>|<visual>
|spawn:i,j;house:i,j;storage:i,j;well:i,j;exit:i,j;beds:<畦0>/<畦1>/<畦2>;reserved:<畦>
```

- **源数据直接存整数毫米**（N-I3 / V3-I5）：r2 的 `farm_blueprint.json` 新增权威字段 `cell_mm` 与 `play_area_mm`（正整数），canonical 只读它们；旧的浮点 `cell_m` / `play_area_m` 保留为展示用派生值且**不进 canonical**。这样既不依赖 JSON 解析器保留数值词法，也不存在舍入或 tie-breaking。非整数、≤0、超出 `[1, 100000]` 一律 `INVALID_NUMBER` 拒绝。
- `layout_patch_id` 仅 `[a-z0-9_]{1,32}`；`format` 为正整数；mask 每行仅 `[01]` 且行长 = `grid.x`、行数 = `grid.y`；坐标为非负整数且 < grid。
- 畦格式 `i,j,i,j,i,j`（三格，按存储顺序）；`reserved` 同。
- UTF-8 → sha256 → 小写十六进制。
- `golden/corpus.json` ≥ 8 组：`cell_mm` 取 `1000 / 2500 / 333`，含 reserved bed，含每类拒绝样本（`0.0005`、`1e0`、`grid` 不匹配、坐标越界）。vitest 与 gdUnit 加载同一文件。

### 5.2 校验先于 checksum

`validate(bp)` 两端都跑且在 checksum 之前：mask 尺寸与字符集；坐标整数在界内；锚点在 walkable 上且从 spawn 可达；畦格在 cultivable 上、三格相邻、互不重叠、与 reserved 不重叠且可达；`cultivable` 计数 = 12。Godot 侧失败返回 null 并 `push_error`；服务端启动时任一蓝图不过 → 进程退出码 1。

### 5.3 三方共用

`packages/blueprint-core` 新建；`tools/geo_blueprint` 与 `server` import 之；`modules/blueprint/blueprint.gd` 按 5.1 重写 `canonical/verify_checksum` 并加载同一 golden corpus。

### 5.4 输出 r2，不改 r1（I10 / N-I4，v3 修正 v2 的原地重写）

管线 `pnpm cli build --revision 2` 从缓存的 OSM 数据重出七份到 `assets/blueprints/<id>/r2/`（几何完全一致，只是 canonical 变了）；`assets/farm/data/regions.json` 的 `revision` 改 2；`r1/` 原样留在库里不动，满足 PRD §4.5「revision 不可变」。客户端 `farm_choice.json` 存 `{layout_patch_id, revision}`；启动时与 `regions.json` 的当前 revision 比对，不一致即视为失效并回到选城页（**主动失效**，不依赖加载失败，V3-I2）。服务端只接受 `regions.json` 当前 revision，旧 revision 建农场返回 422 `STALE_REVISION`。G0 交接文档补一节说明 r1 停用但保留。

## 6. 公平指标

| 指标 | 门槛 |
|---|---|
| `far_bed_9_s` / `far_bed_12_s`（含 reserved） | 各 ≤ 12 s |
| `walk_tour_9_s` / `walk_tour_12_s` | 六份两两差各 ≤ 5 s |
| `tour_s` | 只报告 |

实现在 `blueprint-core/fairness.ts`，`fairness.gd` 逐字对照；`report.json` 增字段；PRD §4.4 改文。

## 7. HTTP v1

Base `https://farm.sensenjoy.cn/v1`；所有响应含 `server_time`；每路由 TypeBox 完整 request/response schema、`additionalProperties:false`。

### 7.1 鉴权（I1 / N-I5）

- 客户端首装生成 128 位随机 `install_key`，存 `user://`。
- `POST /auth/anonymous { install_key }` → `HMAC-SHA256(pepper, install_key)` 查/建 player，签发新 opaque token（32 字节随机，库存 sha256）。**每 player 至多 5 个活跃 token**，超出按 `last_used_at` 淘汰最旧；token **90 天闲置过期**。匿名端点按 IP 限流 10 次/小时。
- `DELETE /auth/token` 撤销当前；`DELETE /auth/tokens` 撤销全部会话。
- `POST /auth/rotate-install-key { current_install_key, new_install_key }`（**同时需要有效 token 与当前 install_key**）：换绑并撤销**包含调用者在内的全部** token，客户端随即用新 key 重新登录。两个凭据都要求，泄露者仅凭 key 无法抢先换绑（V3-C2）。
- **明示限制**：匿名账户在 `install_key` 与设备同时丢失时**不可恢复**，这是 MVP 接受的取舍；正式账号体系（Firebase）在 G4/海外版接入，届时提供邮箱恢复。
- 相对方案 D4「JWT」的变更理由：opaque token 可即时撤销、无时钟偏差、无密钥轮换设计；海外版接 Firebase 时在 `/auth/firebase` 换发同种 token。

### 7.2 路由

`POST /auth/anonymous` · `DELETE /auth/token` · `DELETE /auth/tokens` · `POST /auth/rotate-install-key` · `GET /regions`（只给 `id, timezone, candidates[{layout_patch_id, revision}]`）· `POST /farms` · `GET /farms/me`（`OwnerFarmView` + `derived`）· `POST /farms/me/commands` · `GET /healthz`（`ok, db, git_sha, content_version, domain_version`）。

### 7.3 命令端点

```ts
await tx(async (t) => {
  const farm = await t.selectForUpdate(farmId);                 // 1 行锁
  const hash = sha256(JCS({ type, payload, base_version }));    // 2 幂等身份先判（O-I4）
  const prior = await t.findCommand(farmId, idempotencyKey);    //   旧版本命令的重试要能拿回结果，
  if (prior) return prior.payload_hash === hash                 //   不能被下面的 503 挡住
    ? replay(prior)                                             //   applied 与 rejected 都重放
    : err(409, 'IDEMPOTENCY_MISMATCH');
  if (farm.content_version !== CONTENT_VERSION ||               // 3 新命令才做版本门控
      farm.domain_version  !== DOMAIN_VERSION ||
      farm.state_schema_version !== STATE_SCHEMA_VERSION)
    return err(503, 'VERSION_MISMATCH');                        //   （N-I7 / V3-I4）
  const effectiveNow = max(sample(), farm.state.clock.last_effective_now);  // 4 唯一时间源
  if (base_version !== farm.version)                            // 5 不落日志
    return err(409, 'VERSION_CONFLICT', { state, version, server_time: effectiveNow });
  const derived = derive(farm.state, effectiveNow);             // 6 同一个 effectiveNow
  const r = reducer(farm.state, cmd, { now: effectiveNow, derived, blueprint, content });
  await t.insertCommand({ ..., outcome: r.ok ? 'applied' : 'rejected',
                          effective_now: effectiveNow, content_version, domain_version });
  // 7 无论 applied 还是 rejected 都推进 last_effective_now（O-I3）；rejected 时单独 UPDATE 该字段，
  //   farms.version 不变；响应的 server_time 一律等于 effectiveNow（O-M1）
  if (r.ok) await t.updateFarm({ state: bumpClock(r.state, effectiveNow), version: farm.version + 1 });
  else      await t.bumpClockOnly(farmId, effectiveNow);
  return r.ok ? ok(r) : err(422, r.code);
});
```

**客户端重试协议**（写进 `server/README.md` 与 G1-B spec）：网络超时 → 同 key 原样重发；收到 `VERSION_CONFLICT`（未落日志）→ 用新 `base_version` 并**换新 key** 重发；已落日志的 applied/rejected → 改 payload 或 base 必须换新 key。

**建农场幂等**：`farm_creations(player_id pk, idempotency_key, payload_hash, farm_id)`，比较 hash；相同 → 重放，不同 → 409 `IDEMPOTENCY_MISMATCH`（I2）。

**QA 时钟**：`qa_clock = { real_anchor_ms, virtual_anchor_ms, scale }`，`virtual(t) = virtual_anchor + (t − real_anchor) × scale`。每次 QA 修改都先把当前 virtual 写成新锚点再改参数。`scale ∈ [0.1, 100]`、`days ∈ [1, 30]`，越界 422 `BAD_QA_PARAM`；`qa_set_weather` 拒绝 `protected_slots`（PRD L459）。正式农场调 QA → 403。

### 7.4 错误码

`400 SCHEMA` · `401 UNAUTHENTICATED` · `403 QA_ONLY` · `404 NO_FARM` · `409 VERSION_CONFLICT / IDEMPOTENCY_MISMATCH / FARM_EXISTS` · `422` 领域码（`CELL_NOT_CULTIVABLE WRONG_STATE WRONG_CARE NOT_RIPE INSUFFICIENT_FUNDS INSUFFICIENT_ITEMS CHAPTER_LOCKED STALL_BUDGET BOUND_SEED ALREADY_CLAIMED LOCKED_CHOICE REQUEST_MISMATCH REQUEST_DONE SLOT_TAKEN NOT_AVAILABLE BUYBACK_LIMIT PACK_LIMIT CLOCK_REGRESSION BAD_QA_PARAM`）· `503 VERSION_MISMATCH`。

### 7.5 隐私契约（C4 / N-I12 / N-M1）

| DTO | 字段 |
|---|---|
| `OwnerFarmView` | 身份列 + `state` 全部 + `derived` |
| `VisitorSnapshot`（G2） | `farm_id, layout_patch_id, blueprint_revision, snapshot_revision, snapshot_taken_at, cells[{cell_id, state, crop, ripe}], nursery{stage,appearance}, props[VisitorProp], weather_snapshot`；`location_visible ? region_id : 省略` |
| `VisitorProp` | `{ anchor_id, prop_id, offset_q }`（量化偏移），**禁止任意 JSON** |
| `NearbyEntry`（G2） | `farm_id, avatar_ref, nursery.stage`；`location_visible ? region_id` |

**四种组合**：

| `visit_access` | `location_visible` | Nearby | 直接快照（持 farm_id） | `region_id` |
|---|---|---|---|---|
| `only_me` | true | 不出现 | 404 | — |
| `only_me` | false | 不出现 | 404 | — |
| `anyone` | true | 出现 | 200 | 附带 |
| `anyone` | false | 出现 | 200 | 省略 |

**快照节流（N-I12 / V3-I3）**：快照**按固定时间槽生成，与主人是否操作无关**——`snapshot_taken_at` 恒为 15 分钟整槽（`floor(now/15min)`）；访客请求时若当前槽无快照则**当场用农场最新状态生成该槽的快照**并写入，同槽内的后续请求一律返回同一份。因此 `snapshot_taken_at` 与 `snapshot_revision` 的变化只反映槽的推进与内容差异，不暴露主人的操作时刻；最大陈旧时间即 15 分钟。首次快照在首个访客请求时生成。`OwnerFarmView` 不受影响。

## 8. 存储

```sql
players        (id uuid pk, install_key_hmac text unique, created_at, last_seen_at)
tokens         (id uuid pk, player_id → players, token_hash unique, created_at, last_used_at, revoked_at)
farms          (id uuid pk, owner_id uuid unique → players, region_id, layout_patch_id, blueprint_revision int,
                blueprint_checksum, content_version, domain_version, state_schema_version int,
                version int not null default 0, state jsonb not null,
                qa bool default false, qa_clock jsonb,
                visit_access text default 'only_me', location_visible bool default true, created_at, updated_at)
farm_creations (player_id uuid pk → players, idempotency_key uuid, payload_hash text, farm_id uuid, created_at)
farm_snapshots (farm_id uuid pk → farms, snapshot_revision int, snapshot_taken_at bigint, body jsonb,
                blueprint_revision int, content_version text, domain_version text)  -- 版本不符即重建（O-I5）
commands       (id bigserial pk, farm_id uuid → farms, idempotency_key uuid, base_version int, type text,
                payload jsonb, payload_hash text, outcome text, result jsonb,
                effective_now bigint, content_version text, domain_version text, applied_at,
                unique (farm_id, idempotency_key))
```

**单写者**：同农场行锁串行；20 并发同 `base_version` → 恰一条 applied，其余 409（测试 A）；按 409 更新版本换 key 重发 → 全部 applied，版本无空洞（测试 B）。

**版本策略（I4 / N-I7）**：`content_version` 与 `domain_version` 写进 farms 与每条 commands。启动时进程持有当前两值；命令端点遇到不匹配的农场 **503 fail closed**，不静默换规则。MVP 不做在线迁移；`src/db/reset.ts` 只在 ① DSN 主机在 `192.168.124.0/24` 或 `localhost` ② `ALLOW_RESET=1` ③ 只删 `qa=true`，或 `content_version` / `domain_version` / `state_schema_version` 三者任一与当前进程不符的农场（V3-I4） 三条同时成立时执行，先打印数据库指纹与将删数量再要求二次确认。生产 DSN 直接拒绝。

## 9. 测试

| 层 | 覆盖 |
|---|---|
| blueprint-core | golden corpus 双端一致（含拒绝样本）；`validate` 每条规则各一反例；公平四指标 |
| 领域 | 每命令成功/失败；派生成熟；**Grant 顺序**（先清后发、漏日不清、`grants_issued` 幂等）；请求精确匹配与一次性；`resolve_life_choice` 唯一写槽且校验事实；茶 1/日；摊位部分成交与边界；绑定种子；工程篮；扩地固定篮原子；章节每日一章、漏日续章、D6 冻结但 `weather_day_index` 继续；时钟守卫两种农场行为不同 |
| 账本 | **逐条命令脚本夹具** `fixtures/ledger_{tool,field}_{life,sell}.json`（每行 `{day, type, payload}`），从 `create_farm` 起只用公开命令，断言钱包 210/287/325/362/413/218/305、扩地 46/145、XP 49/95/128/179/230/268/301、关系 58/62/31、出售优先 376/216 与 52/50/19、两路账户价值 545 |
| 天气矩阵 | D2/D3/D4/D6 三种田况轮换（4 组），账本数字不变，只 `care_weather` 与首次田况 XP 时点变 |
| 会话矩阵（I12） | 同一账本脚本按每日 1 / 2 / 3 次会话切分执行，结果一致（PRD Gate 2） |
| 高频 | 贪心 bot（每日卖光、优先做菜、回购与种苗包按 §4.4 上限）D6 账户价值 ≤ 981，实测值写进测试名 |
| 时间 | 04:00 两侧；LA 2026-11-01 两次 01:30（-07/-08）；2026-03-08 春季跳时；连续 `qa_skip_days` 跨 DST；`scale` 边界 |
| HTTP | 鉴权（5 token 上限、闲置过期、撤销全部、轮换 key、限流）；schema 400；409 三种；重放 applied 与 rejected；建农场 hash 不同 → 409；QA 403 与保护槽；三 DTO 精确字段与四种隐私组合；503 版本不匹配；`/healthz` |
| DB | 测试 A/B；同键并发只应用一次；不同农场并行；**CI 必跑**（workflow 起 `postgres:16` service；`CI=1` 且缺 `TEST_DATABASE_URL` 直接失败） |
| 线上 | `smoke.sh`：healthz → auth → create → 三命令 → 重启 app → 状态在；`restore-drill.sh`：从最近备份恢复到临时库，比对**表行数 + 迁移版本 + 10 个农场的 state 哈希 + max(version)** |

## 10. 部署

### 10.1 镜像与云（N-I8 / N-I10）

- CI（`.github/workflows/server.yml`）以仓库根为上下文构建，推 `registry.cn-hongkong.aliyuncs.com/sensen/farm-server`，并产出 `release-manifest.json { git_sha, image_digest, content_version, domain_version }` 作为 artifact。
- `deploy.sh` **只接受 digest**（从 manifest 读，不接受 tag）：先用受限 RAM 用户 `docker login` 私有 ACR，再 `compose pull && up -d`，最后 `smoke.sh`。compose 里所有镜像写 `@sha256:`。
- `provision-ecs.sh`：cn-hongkong、`ecs.e-c1m2.large`、Ubuntu 24.04、40 GiB ESSD Entry、按量付费、5 Mbps 按流量；**`--key-pair` 必填**（脚本创建或选择已有）；安全组 80/443 全开，22 只放 `SSH_ALLOW_CIDRS`（**必填，为空直接退出**）；`cloud-init.sh` 建非 root 用户 `farm`、装 Docker、关闭密码登录、装 fail2ban。先 `--dry-run` 打印规格与预估月费，经用户确认再执行。
- DNS：先 `DescribeDomainRecords` 查 `farm`，无则 `AddDomainRecord`、有则 `UpdateDomainRecord`（幂等）。
- compose：`app`（healthcheck `/healthz`、`mem_limit 1g`）、`postgres`（volume `pgdata`、`mem_limit 1.5g`）、`caddy`（volume `caddy_data`）、`backup`（`supercronic` 跑 `deploy/crontab`，03:30 UTC）；全部 `logging: json-file max-size 20m max-file 5`。

### 10.2 备份与恢复（N-I9）

`backup.sh`：`pg_dump -Fc` → `age -r $AGE_RECIPIENT` 加密 → `ossutil cp` 到 `sensen-farm-backup`（cn-hongkong，14 天生命周期规则）；本地留 2 份。密钥：`AGE_RECIPIENT` 公钥在 `.env`，私钥 `age` identity 只在本机 `~/.config/sensen/farm-backup.key`（不上服务器）；OSS 用只写 RAM 子账号，恢复用另一只读子账号。`restore-drill.sh` 在本机解密并恢复到 devserver 的 `sensen_farm_restore`，比对表行数、迁移版本、10 个农场的 state 哈希与 `max(version)` 后 `DROP DATABASE`——脚本硬编码只接受主机在 `192.168.124.0/24` 且库名恰为 `sensen_farm_restore`，其余一律拒绝（O-I7）。

### 10.3 开发库

devserver `192.168.124.53`：`deploy/devserver-pg.compose.yml` 起 `postgres:16`，只绑该地址，volume `pgdata_farm`，库 `sensen_farm_dev` / `sensen_farm_test` / `sensen_farm_restore`，角色 `farm` 限 `192.168.124.0/24`。本机不装 Docker / PG。

## 11. 仍由我定的假设

1. 赠礼线索映射由账本逐笔归属反推（§4.5）；PRD 未给完整表。
2. 居民 `available_from_chapter` = 0 / 1 / 5。
3. **`attend_shared_event` 与 `record_visit_return` 只靠章节前置门控，不发一次性 capability**（I6，明确接受的风险）：居民场景在客户端播放，服务端本就无法验证「真的参与过」，令牌只能证明「服务端曾允许」，而章节前置已经提供同等强度；MVP 无排行与交易，伪造收益仅是自己提前解锁。若 G3 引入排行或跨玩家奖励，再改为服务端签发 capability。
4. 服务端 `now` 在行锁后采样，不信客户端时间。
5. 快照节流 15 分钟；G2 可按体验调整，但不得取消节流。

## 12. PRD / 方案修订清单

PRD L534 补「门口回购箱计入摊位每日预算」· PRD §4.4 公平门槛改绝对秒并覆盖第四畦 · L317/L808/L936 位置口径改两开关 · §7.2 与 L567/L570 补扩地免清理 · L511 料理摊售 36/24、L534 回购 1/日 · L587 种苗包 3R 且首周 ≤3 次 · §6.6/§9.1 D7+ 田况按独立索引循环、不开新章 · 方案 §3 D4 鉴权改 opaque token · 方案 §6 L229 田格改「逻辑 1 m，视觉放大在 G1-B」· 方案 §9 目录新增 `packages/blueprint-core` 与根 workspace · G0 交接文档补 r1 停用保留、启用 r2。

## 12.5 移交给任务单的实现契约（2026-09-04 用户选定路线 B）

三轮 Codex 评审后仍未在本文档内展开、但**必须在实施任务里作为带验收标准的交付物**的四项。它们是实现产物而非设计决策，写进文档会与代码里的同一份数据重复并漂移：

| 交付物 | 归属任务 | 验收标准 |
|---|---|---|
| 8 张内容表的完整 JSON（`crops/weather_script/xp/relationships/chapters/requests/recipes/economy`） | Task 2 | schema 校验通过；`content_version` 可复现；每个字段有 PRD 行号注释 |
| 26 条命令的完整 TypeBox schema 与前置条件（O-I1） | Task 3 | `additionalProperties:false`；每条命令至少一条成功与一条失败测试 |
| 四条逐条命令账本脚本 `test/fixtures/ledger_{tool,field}_{life,sell}.json` | Task 5 | 只用公开命令、从 `create_farm` 起；断言 §9 全部目标数字；**任一数字对不上即视为内容表或 reducer 有误，不许改断言** |
| 关系/章节/补贴的精确点值与 `min_facts`（O-I2） | Task 2 与 Task 5 | 由账本脚本反向验证：关系 58/62/31 与 XP 301 必须由脚本跑出而非硬编码 |

Codex 三审剩余的 #1 / #7 唯一性质疑由此关闭：**唯一性由测试证明，不由文档证明。**

## 13. 出口

`pnpm -r test` 全绿（四条账本、天气与会话矩阵、高频、DB）· `tools/run_tests.sh` 全绿 · CI 绿并产出 manifest · `farm.sensenjoy.cn/v1/healthz` 200 且 TLS 有效 · `smoke.sh` 与 `restore-drill.sh` 通过 · `server/README.md` 齐备 · Plane SGODOT-24 子卡关闭、28 关闭。

## 14. 估算

| 项 | 人天 |
|---|---:|
| `blueprint-core` + 决策①③ + r2 重出 + golden corpus | 1.5 |
| 领域层 | 3.5 |
| 账本脚本夹具 + 三类矩阵 + 高频 | 1.5 |
| HTTP + 鉴权 + DB + 幂等/版本/时钟 + DTO + 快照节流 | 2.5 |
| 部署（ECS、DNS、ACR digest、compose、备份恢复、CI）+ devserver | 1.5 |
| **合计** | **10.5** |

v1 估 8 → v2 估 9 → v3 估 10.5；增量全部来自两轮评审要求的确定性、鉴权生命周期、隐私节流与可执行部署闭环。
