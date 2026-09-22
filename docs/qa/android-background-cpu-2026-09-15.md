# Android 后台 CPU 与测试清理

2026-09-15。执行用户提供的 `~/projects/claude-destop/godot-background-cpu-brief.md`。

## 结论

**当前 R4 与当前战斗 QA 包未复现后台持续高 CPU。** 四组实测在切后台后的 5-35 秒测量窗口均低于 2%，
恢复前台保持同一 PID，画面正常。没有修改游戏运行逻辑、引擎帧率或原生生命周期代码，没有因此重发 APK。

说明中“8 个后台包、250% sys、内存和 swap 压力”的历史观测仍然有效，但本轮没有独立重现当时状态，
不能把原因归结为某项引擎设置或宣称已经修复其历史根因。测试流程缺少统一退出清理则已补齐。

## 实测方法与结果

目标是一直运行的 `emulator-5560`，AVD `Sensen_Journey_Fixes`，Android 16、4 核、约 4 GB 内存。
没有重启或退出模拟器。先停止全部 `com.sensen.*` 应用，再逐组运行；整个测量期间未更改应用代码或安装包。
线上包为 R4 `0.8.3-combat-online.20260915`，QA 包为前轮宝剑显隐验证包。

冷启动稳定 20 秒后测量 5 秒前台 CPU，随后 Home 或启动另一个 Godot 应用；
在切换后 0、5、10、30、35 秒读取同一个 PID 的 `/proc/PID/stat`，最后恢复前台并复查 PID 与截图。
矿井组先通过实际触控从地图进入农场和矿井，再开始采样。

CPU 采用 `100 * delta(utime + stime) / CLK_TCK / delta(uptime)`，`CLK_TCK=100`，
按单核 100% 表示。下表都是测量区间平均值，不把进程累计 CPU 时间或宿主 QEMU 占用当作应用即时占用。
设备页大小为 16384 字节，原始记录中的 `rss_pages` 不能按 4 KB 换算。

| 实际场景与切换 | 前台 5 秒 | 后台 0-5 秒 | 5-10 秒 | 10-30 秒 | 30-35 秒 |
| --- | ---: | ---: | ---: | ---: | ---: |
| 公共 Journey R4 城市选择页 -> Home | 19.44% | 0.40% | 0% | 0% | 0% |
| 战斗 QA 原生地图 -> Home | 26.19% | 0.40% | 0.20% | 0% | 0% |
| 战斗 QA 原生地图 -> 另一个 Journey 应用 | 24.21% | 0% | 0% | 0% | 0% |
| 战斗 QA 矿井第 5 层 -> Home | 25.35% | 0.60% | 0% | 0% | 0% |

Home 后 Activity 为 `STOPPED`；跨 Godot 应用时原 QA Activity 为 `PAUSED` 且窗口仍可见，CPU 仍为 0%。
四组恢复前台后的 CPU 为约 22%-25%，未卡死或重启。矿井恢复截图保持 HP 66/120、原楼层和场景。
`top -b -n 2 -d 1 -p PID` 的补充采样同样低于 2%（例如地图组为 0.0%、0.9%）。

最初尝试说明中的 `com.sensen.journeyqa`，但它在启动约 1.2 秒后主动退出：
日志显示 `Journey playtest server could not be reached`，随后引擎退出；这是旧测试服务未连接，
不作为 CPU 通过样本，也没有通过覆盖它的 APK 或修改旧存档来制造可测结果。

## 假设核查

| 说明中的假设 | 代码与实测依据 | 判读 |
| --- | --- | --- |
| 未启用低处理器模式 | 实际解包项目在同一引擎中读取到 `low_processor_usage_mode=false`；Android 四组后台仍低于 2% | 设置事实成立，未证实它是异常原因，不为此改动 |
| 未处理应用暂停 | GDScript 多处处理失焦；已有 `GodotMapPlugin.onMainPause()` 调用 `renderView.onActivityStopped()`，恢复时对应调用 `onActivityStarted()` | 当前暂停机制有效；不是本轮新增修复 |
| 自定义线程持续忙等 | 业务 GDScript 与插件未发现 `Thread`、`WorkerThreadPool` 或自建 Executor；引擎/SDK 仍有约 38-79 个线程，但进程累计 CPU 在后台不增长或仅增长少量 tick | 所测路径未发现忙等，线程驻留不等于持续执行；未排除历史状态 |
| 音频、网络持续运行 | 没有业务持续音频或 WebSocket 循环；HTTP 按操作发起，QA 观察器由 `_process` 周期发布，农场计时器是一次性标签回收；后台进程 CPU 接近 0 | 当前无证据支持此假设，未把正常异步组件删除 |
| wake lock / 常亮 | 公共包无 `WAKE_LOCK` 权限；后台 `dumpsys power` 的当前 `Wake Locks: size=0`。模拟器自身插电常亮设置与应用锁分开看待 | 当前无应用持锁证据；历史 acquire 日志不是仍持有的锁 |
| 不限帧或物理频率错误 | 实际解包配置的 `max_fps=0`、`physics_ticks_per_second=60`；原生暂停后 CPU 接近 0 | 未证明不限帧造成后台异常，物理频率为正常默认值 |

原生核查还读取了实际 Godot AAR 的字节码：`GodotVulkanRenderView.onActivityStopped()` 调用
`pauseRenderThread()`，`onActivityStarted()` 调用 `resumeRenderThread()`。
项目现有提前暂停处理源于 [9 月 8 日后台恢复修复](journey-device-fixes-2026-09-08.md)。
本轮没有构建空白 Godot 对照包，因为待解释的持续高占用尚未复现；不据此推断所有 Godot 默认配置都无问题。

## 结构化清理

新增 [测试会话入口](../../tools/android/run_test.sh) 与 [用法](../../tools/android/README.md)，并写入 `AGENTS.md`：

- 启动前 force-stop 目标包，解析其真实 launcher，确认启动成功。
- `trap EXIT/INT/TERM/HUP` 负责退出清理；正常结束、启动失败、测试失败与中断均停止应用。
- 整个测试命令在独立进程组中运行，清理时终止其辅助进程；保留原测试退出码，清理失败也会报错。
- 支持手动会话、`--wait` 有限时长、`-- COMMAND ...` 自动场景以及 `--clean-all`。
- `--clean-all` 只匹配 `com.sensen.*`；不卸载、不清数据、不停止 adb、不退出模拟器。
- 无交互输入的自动运行必须指定时长或命令，防止无期限空等。SIGKILL/宿主断电不能执行 trap，后续启动前清理覆盖残留。

9 项 Node 测试通过，覆盖正常、失败、启动失败、三种信号、清理范围、清理失败和输入检查。
另在实际模拟器分别验证正常结束、退出码 17 的测试失败、SIGINT、SIGTERM、SIGHUP：
五次均确认启动过应用、结束后应用 PID 消失、模拟器仍在线。完整矿井 CPU 场景也通过该入口执行并自动清理。

## 证据与边界

原始数据位于 `output/background-cpu-2026-09-15/`：
`summary.json`、四份 `*-report.json`、对应 Activity/top/meminfo/power/location 记录与前后台截图，
`packaged-settings.txt`、`godot-vulkan-lifecycle.txt`、`runner-tests.log`、`runner-device-report.json`。
`old-qa-launch-logcat.txt` 保留无效基线的退出原因。`capture.mjs` 是本次采样脚本。

没有真机性能样本，也没有重演 8 个旧版本长时间同时驻留至内存压力失控的条件。
如历史异常再次出现，先保存各进程版本、PID/线程 CPU、Activity 状态、当前唤醒锁与内存压力，
再清理，并针对当时真正消耗 CPU 的线程采样；仅凭当前未复现，无法完成历史根因的归因。
