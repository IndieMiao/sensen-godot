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

## 4. 真机结果（iPhone 15，iOS 真机，bundle com.sensen.mapg3）

待填：从设备拉取 `Documents/lifecycle_probe.json` 后补。

```
xcrun devicectl device copy from --device 0FAD60D2-1CFE-5883-A1A2-849346019F6C \
  --domain-type appDataContainer --domain-identifier com.sensen.mapg3 \
  --source Documents/lifecycle_probe.json --destination /tmp/lifecycle_probe.json
```

| 动作 | PAUSED | RESUMED | FOCUS_OUT | FOCUS_IN | 备注 |
|---|---|---|---|---|---|
| 切到桌面再回来 | | | | | |
| 下拉控制中心 | | | | | |
| 通知横幅 | | | | | |
| 键盘弹出/收起 | | | | | 键盘高度读数、输入框是否被挡 |

## 5. 对后续任务的约束（待真机结果确认后定稿）

- WsClient：以真机确认的 PAUSED/RESUMED 为断连/重连触发点。
- KeyboardAvoider：iOS 键盘动画期高度读数是否跳变，决定要不要做平滑。
