# Journey 真机手势与后台恢复修复

日期：2026-09-08。承接 [v6 真机验证](journey-physical-v6-2026-09-08.md) 留下的短间距缩放和 Vulkan 表面丢失问题。

## 结果

在 vivo V2509A、Android 16、1080×2344 上完成修复及复测。最终安装包的农场、庭院和原生地图均可缩放、拖动；14 次前后台往返后画面、输入、进程与存档正常。持久化 Godot 日志未再出现 `VK_ERROR_SURFACE_LOST_KHR`。这是该设备与所测路径的验证结果，不代表所有 Android 设备已覆盖。

## 实现

- `project.godot` 关闭 Android 原生 pan/scale 识别，同时启用 `disable_scroll_deadzone`。设备原生识别器的最小缩放间距约 27 毫米；只关闭原生缩放时，Godot 的默认拖动过滤仍会吞掉中心不动的对称捏合，两个设置需要配合。
- 农场和地点继续使用 `ScenePan` 的原始双指距离、焦点保持、惯性和弹性边界。地图补上原始双指缩放，并按触点 ID 管理手势；剩余单指不再触发平移，取消或失去焦点时清理状态，避免残留点击及惯性。桌面触控板事件仍可使用。
- Android 地图插件通过 Godot 的公开渲染生命周期接口，在 Activity `onPause` 提前暂停渲染，在 `onResume` 恢复。Godot 4.7 原先到 `onStop` 才暂停渲染，窗口表面此前可能已经销毁。覆盖只暂停、随后恢复而不经过另一次 `onStart` 的路径。
- QA 观察器增加地图镜头采样和农场当前缩放值，便于核对输入到达之后是否真正改变镜头。

## 真机证据

最终包共记录 26 次操作或截图、13 次手势、14 次后台往返，全部通过对应证据断言。

| 检查 | 结果 |
| --- | --- |
| 农场短间距缩小 | 起始约 418 px、终止约 146 px；缩放 1.4 → 约 0.711 → 0.8。重复了此前失败的间距级别。 |
| 庭院短间距缩小 | 起始约 419 px；缩放 1.4 → 约 0.711 → 0.8。 |
| 放大与宽间距缩小 | 农场、庭院短间距放大均有上限弹性并回到 1.4；约 780 px 的宽间距缩小均回到 0.8。 |
| 3D 拖动 | 农场偏移约 2.145 → 1.6，庭院约 2.150 → 1.6；采样含松手后的速度衰减。所有手势均未改变角色位置或存档。 |
| 地图手势 | 原始双指放大、缩小及单指拖动均有效，有松手后的惯性；缩放保持在 15–18，俯角保持 45 度。最短的一次起始间距约 108 px，也产生了缩放。 |
| 后台恢复 | 农场 4 次、庭院 4 次、地图 6 次，交替 Home 和任务列表。每次核对相同启动 ID、相同存档、恢复后的新采样；截图均显示场景内容，像素检查通过。 |
| 交互 | 地图抽屉按钮关闭、Android 返回关闭均正常，未覆盖底栏。庭院地面点击、居民身体点击、关闭对话和返回地图均有效。24 条移动采样为 `run`，动画时间推进，配置速度 3.75。 |
| 保存 | 覆盖安装保留安装标识。测试居民对话令 version 252 → 253，仅推进服务器时钟，其他完整状态一致；最终冷启动后完整 state JSON 相同。 |

## 自动验证

- 图形模式 Godot/GdUnit：17 个测试套件、126 项测试全部通过，0 errors / failures / skipped / orphans。报告 `reports/report_847/`。
- Android `testStandardDebugUnitTest`：6 项通过。该套件验证既有插件逻辑，渲染生命周期的修复结论来自上述真机循环。
- `output/journey-device-fixes-2026-09-08/verify-evidence.mjs`：手势方向、惯性、边界、人物及存档不变、恢复后的新采样、像素内容、跑步动画、重启和 APK 一致性断言通过。
- `git diff --check` 通过。Godot 导入扫描遇到既有 `build/ios/.../*.sample` 非资源文件报错，未作为本次脚本失败；最终测试发现及执行均无脚本错误。

## 失败试验与限制

- 首个试验包只关闭原生缩放，4 次捏合均未改变镜头，明确排除在最终通过计数之外。随后定位到 Godot Android 拖动死区，再补齐设置。
- 首个试验包使用 `SURFACE_LIFECYCLE_FOLLOWS_ATTACHMENT` 仍在 3 次后台往返中出现 Vulkan 错误；该策略已移除，最终实现采用提前暂停渲染。
- 最终进程的默认 logcat 主缓冲区未保留可用日志，不能据空输出认定无错误。渲染错误核对使用完整启动至重启前的持久化 `godot.log`；Activity 暂停、停止、恢复及表面销毁记录使用 `events` 缓冲区，另对两次后台往返实时采集。既有 `xr/shaders/enabled` 警告仍在。
- 附近公开农场为 0，未进入其他真实玩家的农场；农场与庭院覆盖了共用的 `ScenePan`，不把这当成访客模式全部通过。
- 本次是手势与后台恢复专项修复，不是新玩家首小时、留存、长时间性能或玩法已经足够好玩的证明。未重复上一轮完整制作、料理和探索任务流程。

## 构建与证据位置

最终 APK：`output/journey-device-fixes-2026-09-08/sensen-journey-device-fixes-v3.apk`。

SHA-256：`40d573f7bb7ce6a99968190a54e10b233772c79d32696d17d7f1d5a1c7bf6ab5`，与手机已安装 `base.apk` 一致。`v3` 是本次试验构建序号，游戏内容仍接续 Journey v6。

证据根目录：`output/journey-device-fixes-2026-09-08/`。重点文件为 `verification.json`、`resume-contact.png`、`restart.json`、`build-info.json`、`installation-check.json`、`godot-v3-before-restart.log`、`godot-final.log`、`logcat-v3-all.log` 和 `logcat-v3-live.log`。`evidence/` 保存操作前后状态、触控回执及截图；早期失败试验仍保留并单独排除。

手机最终停在地图页、抽屉关闭。QA 包 `com.sensen.journeyqa` 使用本机 `127.0.0.1:3119/v1` 服务和 ADB reverse，需要本机服务及 USB 连接；不是对外分发包。原包 `com.sensen.avatarphase1` 未改动。
