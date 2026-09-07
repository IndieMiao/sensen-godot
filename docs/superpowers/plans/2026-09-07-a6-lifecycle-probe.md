# A6 生命周期探针 —— 实施记录（2026-09-07）

对应 Plane SGODOT-90（A6 前后台生命周期）与 SGODOT-89（A5 iOS 键盘避让真机项）。

## 1. 做了什么

- `scenes/app/pages/lifecycle_probe_page.gd/.tscn`：一个压栈式 AppPage，只在 debug 构建里从
  Settings 的「Dev: lifecycle probe」进入。监听并计数
  `NOTIFICATION_APPLICATION_PAUSED / RESUMED / FOCUS_IN / FOCUS_OUT`、
  `WM_WINDOW_FOCUS_IN / OUT`、`WM_GO_BACK_REQUEST`，每条带时间戳追加到
  `user://lifecycle_probe.json`，页面上实时显示计数、虚拟键盘高度、WebSocket 状态；
  带一个 LineEdit 用来触发键盘避让。
- `modules/app/app_routes.gd` 新增 `LIFECYCLE_PROBE` 常量；`settings_page.gd` 加 debug 专属入口。
- `tests/app/test_lifecycle_probe.gd`：通知计数、持久化、清空、非 debug 不暴露入口。

## 2. 为什么要一个探针页而不是直接写业务

WsClient 的 pause/resume、后续 IM 的「回前台补拉」、语聊的「后台保活」都押在
「APPLICATION_PAUSED / RESUMED 在 iOS 上何时来、来几次、和 FOCUS_* 的先后」这组事实上。
文档里的说法和真机行为常有出入，先用探针把真机事实钉下来，再写依赖它的代码。

## 3. 桌面侧顺带发现的事实

- 无头（`--headless`）进程里 `RenderingServer.frame_post_draw` 永远不触发；所以任何
  等这个信号的测试都只能在带窗口的 gdUnit 运行器里过。
- macOS 会把被其他窗口**完全遮住**的 Godot 窗口判成不可见并停止绘制。今天 Edge 盖住测试
  窗口后 `tests/scenes/test_bg_handoff.gd` 从 0.19 s 恶化到 5 min 超时。已改成
  `RenderingServer.force_draw()`（commit 863f02a），测试不再依赖桌面窗口层叠。

## 4. 真机结果（iPhone 13，iOS 26.5，Godot 4.7.2，bundle com.sensen.mapg3，2026-09-07 19:03–19:05）

用「iPhone 镜像」从 Mac 上操作：⌘1 回主屏 = 切后台；`xcrun devicectl device process launch`（不带
`--terminate-existing`）把后台进程唤回前台。四个循环，原始数据见同目录
`2026-09-07-a6-lifecycle-probe-iphone13.json`。

| 动作 | PAUSED | RESUMED | FOCUS_OUT | FOCUS_IN | WM_FOCUS_OUT | WM_FOCUS_IN |
|---|---|---|---|---|---|---|
| 切后台 → 回前台 ×4 | 4 | 4 | 4 | 4 | 4 | 4 |

每次的顺序与间隔都稳定：

- 切后台：`WM_WINDOW_FOCUS_OUT` → `APPLICATION_FOCUS_OUT`（+2 ms）→ `APPLICATION_PAUSED`（+600 ms 左右）。
- 回前台：`WM_WINDOW_FOCUS_IN` → `APPLICATION_FOCUS_IN`（+1 ms）→ `APPLICATION_RESUMED`（+30 ms 左右）。
- `WM_GO_BACK_REQUEST` 在 iOS 上从未出现（符合预期，那是 Android 的返回键）。

**结论：godot #115936 的 iOS 生命周期通知回归不影响本构建**（4.7.2 + iOS 26.5），WsClient 以
`APPLICATION_PAUSED / RESUMED` 作断连 / 重连触发点可以照用，不需要插件层桥 UIApplication 通知。
注意 PAUSED 比 FOCUS_OUT 晚约 600 ms：需要「立刻」反应的逻辑（暂停语音采集等）应挂 FOCUS_OUT。

键盘：镜像会话期间 Mac 键盘充当硬件键盘，iOS 不弹软键盘，`virtual_keyboard_get_height()` 恒为 0，
所以 A5 的 iOS 键盘避让要在手机上手点输入框验证；探针页现在会把见过的最大键盘高度写进
`lifecycle_probe.json`（`keyboard_max_px`），手点之后拉文件即可，不用盯屏幕。

另：国行 iOS 首次联网会弹「允许使用无线数据」系统弹窗，会挡住页面；提审用的非国行机型没有此弹窗。

## 5. 对后续任务的约束

- WsClient：`APPLICATION_PAUSED / RESUMED` 作断连 / 重连触发点，已验证可靠；语音采集类「必须立刻停」的逻辑挂 `APPLICATION_FOCUS_OUT`。
- KeyboardAvoider：iOS 键盘高度读数待手点验证（见上）。
