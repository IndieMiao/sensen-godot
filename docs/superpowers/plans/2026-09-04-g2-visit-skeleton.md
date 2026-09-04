# G2 访问骨架 —— 任务单

> 上游：`docs/product/map-farm-life-sim-direction.md` §3.3 / §8.4 / §11.2；方案 §4.3；
> spec `2026-09-04-g1a-farm-server-design.md` §7.5（DTO 与四种组合已定形）。
> 出口：D4 流程完整；访客态零写入；服务端不可用自动落到随包快照；退出恢复 100%。

## 0. 动工前发现的缺口（决定任务顺序）

| 缺口 | 后果 | 归入 |
|---|---|---|
| `FarmSession` 全部方法是**同步**的，真实 HTTP 传输却是协程 | 主流程接不上服务端；昨天 e2e 能过是因为绕开了 FarmSession | Task 1 |
| `farm.gd` 的 `session/predictor` 从未被赋值 | 选地 → Create Farm → 农场，全程零网络 | Task 1 |
| `farms` 表没有装扮列 | `NearbyEntry.avatar_ref` 无来源 | Task 2：由 farm_id 派生确定性外观 |
| 访客快照没有 `ready_at`（spec 故意不发） | `CropField.stage_of()` 算不出阶段 | Task 4：按 `ripe` 标志渲染 |
| 随包兜底快照与线上预置农场若是两座不同农场 | `record_visit_return.visited_farm_id` 对不上 | Task 2：预置农场用**确定性 UUID** |

## 1. 已有、不用再做

`visitorSnapshot / nearbyEntry / snapshotSlot`（dto.ts，130 行测试含四种组合矩阵）；`farm_snapshots` 表；`visit_access / location_visible` 列与两条 set 命令；`record_visit_return` 归约（D4 前返回 CHAPTER_LOCKED，客户端须静默吞掉）。

## 2. 已知雷区

| 雷 | 位置 | 规避 |
|---|---|---|
| `await` 非协程值只是警告不是错误 | GDScript 4 | FakeTransport 保持同步；所有调用点一律 `await`，测试也 `await` |
| TopPanel ≤220×64、SideToolbar 在右侧 | `test_map_ui.gd` | Nearby 面板走 BottomSheet，不碰顶栏与侧栏 |
| `enter_street_mode()` 无条件 `load_candidates()` | `map_poc.gd:529` | 有农场时改走 `_enter_farm_home()`，候选层不建 |
| `prop_count()==16`、相机公式、Exit 连接数==1 | `test_farm_scene.gd` | 访客模式只隐藏/追加，不改这些路径 |
| 动画守卫：未登记动作立刻红 | `test_anim_placeholders.gd` | `wave` 先进登记表再用 |
| 两个 DB 测试文件曾并行互 truncate | `vitest.config.ts` | 已串行；新增 DB 用例放进 conformance 或 concurrency 文件 |

## 3. 任务

### Task 1：会话协程化 + 全局 `Net` + 农场接线（1.0）
**Files:** 改 `modules/net/api_client.gd`、`farm_session.gd`、`tests/net/*`；新建 `modules/net/net_service.gd`（autoload `Net`）、`tests/net/test_net_service.gd`；改 `scenes/farm/farm.gd`、`scenes/map_poc/map_poc.gd`、`project.godot`。
- `ApiClient.request()` → `await transport.call(...)`；`FarmSession.login/ensure_farm/refresh/send` 全部协程。
- `Net`：启动 `boot()` = 登录 + `GET /farms/me`（404 正常）；暴露 `session`、`ready` 信号、`nearby(region_id)`、`snapshot(farm_id)`、`base_url` 可被 `user://server.txt` 覆盖；测试用 `Net.use_transport(callable)` 注入假传输。
- Create Farm：`await Net.session.ensure_farm(...)` 成功才 `push_instance`；失败给 Toast 且仍可离线进灰盒（保留 G0 行为）。
- `farm.gd::setup`：非访客且 `Net.session.farm_id` 非空 → 挂 session/predictor，`state_changed → _render()`，`offline_changed → hud.set_offline`。
**Acceptance:** `tests/net` 全绿（含 await 版）；选地建场后 `GET /farms/me` 有农场；`test_farm_scene.gd` 照旧过。

### Task 2：服务端 `nearby` / `snapshot` / 预置农场（1.5）
**Files:** 改 `server/src/http/{app,store,memory_store}.ts`、`server/src/db/pg_store.ts`；新建 `server/src/domain/presets.ts`、`server/src/http/avatar_ref.ts`、`server/tools/gen_presets.ts`；测试进 `test/http/app.test.ts` 与 `test/db/store_conformance.test.ts`。
- `GET /v1/nearby?region_id=` → `{region_id, count, entries[NearbyEntry]}`；只含 `visit_access='anyone'`、排除自己、按 `created_at` 排序（不按 `updated_at`——那会泄露活跃时刻）、上限 20。
- `GET /v1/farms/:id/snapshot` → 404 组合按 §7.5；**按槽取或建**：同槽复用；跨槽重算，`snapshot_revision` 只在 body 变化时 +1。
- `avatar_ref` = `"seed:" + farm_id 前 8 位`；预置农场 `preset_a/preset_b`。
- 预置：每城 2 座（`sh_b` 繁茂 / `sh_c` 初垦；`la_b` / `la_c`），系统玩家 `install_key_hmac="preset:<layout>"`，farm_id 为 `sha1("preset:"+layout)` 拼成的 UUID；状态用**真实归约器**跑脚本生成；启动时幂等播种。
- `tools/gen_presets.ts` 用同一函数产出 `assets/farm/presets/<layout>.json`（VisitorSnapshot 形状）。
**Acceptance:** 四种组合矩阵通过路由层复测；两套 Store 一致性套件加 nearby/snapshot 三条；预置播种两次不重复。

### Task 3：Nearby Farmers 面板 + 静态预览卡（1.0）
**Files:** 新建 `scenes/map/nearby_panel.gd`、`modules/avatar/seeded_outfit.gd`、`tests/map/test_nearby_panel.gd`；改 `map_poc.gd`。
- 有农场时进 `_enter_farm_home()`：不建候选层，侧栏加 `My Farm`，底部挂 `NearbyPanel`。
- 面板：标题 `Nearby Farmers · N`；横向卡片（`avatar_ref` → 种子 RNG 生成 AvatarConfig，卡上画色块 + 苗圃阶段字样）；选中一张 → 下方静态预览（蓝图 `preview.png` + `6 growing · 2 ripe · Sunny`）+ `Visit Farm`。同时只能选一张。
- 顶栏 `NearbyCount` 改显示服务端 `count`。
**Acceptance:** 360×800 不与顶栏/侧栏重叠；卡片 ≥44 高；文案英文；选中互斥。

### Task 4：只读访客实例（1.0）
**Files:** 改 `scenes/farm/farm.gd`、`farm_hud.gd`、`assets/avatar/base/anim_placeholders.json`；新建 `tests/farm/test_visitor_farm.gd`。
- `setup({visitor:true, snapshot, blueprint})`：标题 `Visiting · <avatar 短名>`；HUD 隐藏金币/种子/工具/Row，保留田况 chip（`weather_snapshot`）；加 `Wave` / `Stamp` 两键——本机动画，不发任何命令。
- `CropField.sync_snapshot(cells)`：`ripe → 成熟阶段`，`growing → 阶段 1`，`sown → 0`。
- 零写入：`_enqueue_cells()` 返回 0；`session/predictor` 为 null；FakeTransport 记录为空。
- `wave` 登记为占位（回退 idle + 挥臂 Tween）。
**Acceptance:** 访客实例内任何输入不产生命令；`test_farm_scene.gd` 全过。

### Task 5：随包兜底 + 返回恢复 + e2e（0.5）
**Files:** 改 `nearby_panel.gd`、`map_poc.gd`；新建 `modules/farm/preset_snapshots.gd`；扩 `tools/dev/g1_e2e.gd` → `g2_e2e.gd`。
- `Net.nearby()` 失败 → 面板副标题 `Offline · sample farms`，条目来自 `assets/farm/presets/`；单座快照失败 → 该卡用随包，其余照常。
- 返回：地图节点未销毁，选中与滚动天然保留；额外落 `user://ui_state.json {selected_farm_id}` 防冷启动丢失；返回时发 `record_visit_return`，CHAPTER_LOCKED 静默。
- e2e：A 建场并 `set_visit_access anyone` → B 登录 `nearby` 看到 A → `snapshot` 字段集精确 → A 改 `only_me` → B 再取 404。
**Acceptance:** 断网起动仍能列出预置并进入；线上 e2e 全绿。

## 4. 估算

Task 1 1.0 ｜ 2 1.5 ｜ 3 1.0 ｜ 4 1.0 ｜ 5 0.5 = **5.0 人天**（方案原估 4.5；多出的 0.5 是会话协程化这条 G1-B 缺口）。
