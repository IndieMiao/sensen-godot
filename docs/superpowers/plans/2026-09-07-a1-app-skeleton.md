# A1 架构骨架：路由表 + Tab 壳 + 会话 / API client / WebSocket 封装（实施记录）

- 日期：2026-09-07 ｜ 分支：`feat/next-feature` ｜ Plane：SGODOT-88 ｜ 上游：`2026-09-07-dev-task-breakdown.md` §3 A1、`../specs/2026-08-30-overseas-refactor-research.md` §3.1
- 性质：实施记录 + 交接。**未提交**；自动化全绿；未装机。

## 0. 结论

| 项 | 结果 |
|---|---|
| 全量测试 | **672 例 / 82 套件，0 errors / 0 failures / 0 orphans**（`tools/run_tests.sh`） |
| 新增测试 | `tests/app` 17 例（路由表 4、启动决策 4、壳 9）；`tests/net` 新增 36 例（AuthSession 11、WsClient 12、ApiClient +7、NetService 农场门控归入 test_boot） |
| 旧断言改动 | 两处「主场景是城市选择页」改为「主场景是 boot.tscn，城市选择页保留 `--qa-scene=city` 入口」（`tests/ui/test_app_router.gd`、`tests/scenes/test_city_select.gd`） |
| 无头冒烟 | `godot --headless --path . --quit-after 8`（boot → login）、`++ --qa-scene=shell`、`++ --qa-scene=login` 无 SCRIPT ERROR |
| 未做 | Android / iOS 装机（随 R 模块 B1 CI / B2 / B4 一并做）；A6 iOS 生命周期通知真机验证仍是独立卡 |

## 1. 做了什么（对照 A1 卡）

**路由表** `modules/app/app_routes.gd`（class `AppRoutes`）：BOOT / LOGIN / SHELL 三个整场景；四个 Tab（`map / feed / im / profile`，顺序即底栏）；压栈子页 SETTINGS / VOICE_ROOM。`AppRouter` 同步加了 `BOOT / LOGIN / SHELL` 常量、`go_to_login()` / `go_to_shell()`（切整场景前 `_clear_stack()`，否则压栈的设置页会盖住登录页）、`--qa-scene=login|shell|home`，返回表把三个新场景都归 `BACK_LEAVE_APP`。

**Tab 壳** `modules/app/app_shell.gd` + `scenes/app/app_shell.tscn`（class `AppShell`）：
- Tab 页懒实例化、只实例化一次，切换靠 `visible` + `process_mode`，页面状态天然保留；地图页无论当前 Tab 是什么都常驻（§3.1：将来垫原生 MapView，进出只是显隐）。
- `on_tab_shown()` / `on_tab_hidden()` 回调是 B5 接 `bridge.set_map_visible` 的挂点。
- 返回键：`AppRouter.handle_back()` 先问 `current_scene.handle_back()`；壳在非首页 Tab 时切回地图并消费，地图 Tab 时交还路由（回后台）。
- 当前 Tab 写 `UiState`（key `shell_tab`），冷启动恢复。
- 实现 `suspend()` / `resume()` 压栈协议：设置 / 语音房压上来时停处理并通知当前 Tab 页。

**页面基类** `modules/app/app_page.gd`（class `AppPage`）：纸色背景、`SafeAreaMargin`、标题栏（压栈页带返回按钮 → `AppRouter.pop_instance()`）、`body` 容器、`placeholder()`。六个页面脚本在 `scenes/app/pages/`（map / feed / im / profile / settings / voice_room），只填占位文案与入口按钮：地图页与我的页可进换装房（复用 avatar 模块）；我的页可压栈进设置与语音房；设置页可登出（`AuthSession.sign_out()` + `WsClient.close()` + `go_to_login()`）。

**启动决策** `scenes/app/boot.tscn`（现为 `project.godot` 主场景）：磁盘有会话 → 壳，否则 → 登录页；带 `--qa-scene` 时不干预。

**登录页** `scenes/app/login_page.gd`：邮箱 / 验证码 / Apple / Google 四个入口全部禁用，等 B1 / C1；调试构建多一个「Dev: continue offline」写入本地会话直通壳，让路由与压栈不依赖 Firebase 就能走通。

**会话状态机** `modules/net/auth_session.gd`（class `AuthSession`）：`SIGNED_OUT → SIGNING_IN → SIGNED_IN ⇄ REFRESHING`；`user://auth_session.json` 持久化；`needs_refresh()` 提前 60 s；`refresh()` 通过注入的 `refresher` 执行（B1 接 Firebase securetoken），瞬时失败保留旧会话、`fatal` 失败登出；时钟可注入。

**ApiClient** `modules/net/api_client.gd`：`token_provider`（每次请求现取，非空优先于静态 `token`）、`on_unauthorized`（401 给会话一次刷新，成功重发一次）、`request_idempotent()`（`idempotency-key` 头，传输层失败按同一把键重试，拿到任何 HTTP 响应即停）、`Response.code()` 统一错误码；`extra_headers` 参数；PUT / PATCH 动词。

**WebSocket** `modules/net/ws_client.gd`（class `WsClient`，Node）：`open / close / send / poll`；握手头带 Bearer；`connected / disconnected / message_received / resync_needed / state_changed`；`seq` 单调追踪；断线指数退避（1 s 起、30 s 封顶）；`NOTIFICATION_APPLICATION_PAUSED` 断开、`RESUMED` 重连并发 `resync_needed(last_seq)`；peer 可注入。

**Net autoload** `modules/net/net_service.gd`：挂 `auth`、`ws`；`bind_auth()` 把 token_provider / on_unauthorized 接到 `AuthSession`；农场匿名登录只在 `--qa-scene=city|farm|map|week` 时自动跑（`farm_boot_requested()`），测试进程不读磁盘会话。

## 2. 关键决定

1. **地图页常驻、其余页面纯 Godot 全屏**——直接落实 §3.1「避免谁是宿主的返工」；壳不知道原生桥，只给页面显隐回调。
2. **不改 AppRouter 的整场景机制**（`change_scene_to_file` + 实例栈），只加路由与「先问当前场景 handle_back」这一层；农场分支合并时以本分支路由壳为宿主、农场作为实例页面接入。
3. **ApiClient 保持向后兼容**：静态 `token` 字段与 FarmSession 用法不变，`token_provider` 返回空时回退，所以 32 条 FarmSession 测试零改动。
4. **Dev 直通只在调试构建**，且写的是本地会话（`provider = "dev"`），不会被当作正式登录。
5. **主场景切到 boot.tscn**：农场城市选择页降为 QA 入口；两条旧断言按此改写并写明原因。

## 3. 踩坑记录（对后续任务有用）

- **GDScript lambda 按值捕获局部变量**（Godot 4.7.2 实测：`n += 1`、`s = "new"`、信号连的闭包都改不到外面；Dictionary / Array 因为是引用类型可以）。在 gdUnit4 6.2.1 里，含这种赋值闭包的用例还会让**同一套件后面的用例不被发现**（api_client 13 例只跑 7 例、ws_client 12 例只跑 1 例，且无报错）。规矩：测试里可变状态放辅助类，Callable 用方法引用；探针脚本见本文件同日的会话记录。
- `Response.code()` 对传输层失败返回 `error` 文本，没有文本时返回 `TRANSPORT`，上层判断断网用这个而不是 `status == 0`。

## 4. 手工验收（待人工）

```bash
godot --path .                          # boot → 登录页 → Dev: continue offline → 壳
godot --path . ++ --qa-scene=shell      # 直接进壳
```
1. 四个 Tab 可切换，切换后回到前一个 Tab 内容保持（占位页无状态，B2/B3 有列表后再验）。
2. 我的 → 设置 → 返回按钮 / Android 返回键回到「我的」Tab；设置 → 登出 → 登录页，且没有残留的设置页盖在上面。
3. 动态 Tab 下按 Android 返回键 → 回地图 Tab；地图 Tab 再按 → 回后台不退出。
4. 杀进程重开：落在上次的 Tab；登出后重开：落在登录页。

## 5. 下一步（按拆解文档顺序）

A6 iOS 生命周期通知真机验证 → D0 后端栈决策（阻塞 D1/D2）→ B1 登录页接 Firebase Identity Toolkit REST（把 `AuthSession.refresher` 接到 securetoken，登录页四个按钮解禁）→ C1 原生登录插件 → A2 i18n。
