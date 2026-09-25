# iOS / TestFlight 自动化操作记录

本流程来自 2026-09-25 的实际交付：Gensen `0.16.37 (3)` 修复选城后地图黑屏，已上传、通过 Apple 处理、从 TestFlight 原位安装到 iPhone 14 Pro，并通过最终真机检查。后续自动化从本文件开始，按当次请求选择版本、归档和设备。

## 固定应用身份与每次需要发现的参数

| 项目 | 已确认值 / 取值规则 |
| --- | --- |
| Apple Account | `shaojie@gensen.app` |
| 企业团队 | Gensen / `XN4Z77ZX73`；该账号同时有 Personal Team，不能混用 |
| Bundle ID | `app.gensen.maps` |
| App Store Connect app ID | `6815092667` |
| 内部测试群组 | `GensenMap Internal` |
| 版本和 build | 从当次归档 `Info.plist` 回读，并与当次发布目标比较；不要固定为 build 3 |
| 手机 | 重新发现当前连接设备，确认名称、型号、系统版本、CoreDevice ID 和 Xcode UDID |
| 源码与产物 | 记录当前发布提交、原生桥源码摘要、PCK SHA-256、Release 可执行文件 UUID、最终 IPA SHA-256 |

2026-09-25 的 iPhone 为 iPhone 14 Pro / iOS 26.3。设备 ID、证书指纹、profile UUID、Xcode 窗口坐标及临时目录只属于当次环境，不能作为后续自动化的常量。

## `No Accounts` 的正确处理

### 已确认的现象与结论

同一用户、同一 `/Applications/Xcode.app` 下，命令行导出立即返回退出码 70：

```text
error: exportArchive No Accounts
error: exportArchive No signing certificate "iOS Distribution" found
```

`DVTDeveloperAccountManagerAppleIDLists / IDE.Identifiers.Prod` 的命令行读取结果为 0。但用户提供的 Xcode → Settings → Apple Accounts 页面明确显示 `shaojie@gensen.app`、Gensen、Admin；该正在运行的 Xcode 随后成功取得云管理分发签名并上传。

因此，上述偏好项为空只证明 CLI 读取的账号列表为空，**不能据此认定用户未登录或会话失效**。本次已验证的解决路径是使用已登录 Xcode 的 Organizer；CLI 与 GUI 不一致的底层原因尚未查明，不能记录成“重新登录修好了”。

### 自动化分支

| 观察到的证据 | 下一步 |
| --- | --- |
| CLI 导出成功 | 核对实际 IPA，继续既定上传流程 |
| CLI `No Accounts`，GUI 明确显示目标账号和 Gensen 团队 | 复用已有归档，转 Organizer 分发；继续本次已授权交付，无需重复要求登录 |
| 只有 CLI 账号数量为 0，尚未查看 GUI | 先核对所用 Xcode 路径、当前 macOS 用户及 GUI 账号页面；将 GUI 状态标为未知 |
| GUI 明确显示未登录或 Sign In Again / Session Expired | 请用户在 Xcode 完成本人登录和双重验证；密码及验证码由用户在系统界面输入 |
| 本机缺少分发私钥，但 GUI 能使用 Cloud Managed Apple Distribution | 继续云管理签名；本地 `security find-identity` 没有分发身份不是整个发布流程失败的充分证据 |
| GUI 也分发失败 | 保存实际错误和阶段，再处理对应原因；不要通过清空账号列表、覆盖偏好项或重建证书来试错 |

诊断时只记录账号存在性、团队、错误码与必要日志。不要输出整个 Xcode 账号存储、钥匙串内容或认证请求。

## 已验证的 Organizer 回退流程

前提是当前归档已编译、完成适当验证，并已核对应用身份与目标版本。保留失败的 CLI 日志，以区别“CLI 修复”与“GUI 回退成功”。

1. 打开当次归档：`open -a Xcode "$IOS_ARCHIVE"`。`IOS_ARCHIVE` 使用本次实际绝对路径。
2. 在 Archives 中核对所选归档的版本/build、`app.gensen.maps`、Gensen 和 arm64。
3. **Distribute App → Custom → Next → App Store Connect → Next → Upload → Next**。
4. 在选项页关闭 **Manage version and build number**，保留已验证的版本号；本次启用 **Upload your app's symbols**，未勾选 **TestFlight internal testing only**。未来分发范围依当次请求决定。
5. 选择 **Automatically manage signing**。编译/归档阶段使用 Apple Development；App Store 分发阶段由 Xcode 使用 Apple Distribution。
6. 在 **Review …ipa content** 页面核对团队、版本、bundle、云管理分发证书、store profile 和 entitlements，再继续 Upload。
7. 读取完成页与日志，保存上传结果。`Upload completed with warnings` 可能已上传成功，应逐项区分警告与失败。

本次成功签名是 **Cloud Managed Apple Distribution**，最终 IPA 身份为 `Apple Distribution: Gensen (XN4Z77ZX73)`。开发证书显示名是 Zheyu Li；判断依据是团队 OU / TeamIdentifier，不能仅凭显示名不同于邮箱改用个人团队证书。

### GUI 自动化约束与实现提示

- 使用当前可访问性树发现窗口、sheet 和按钮；有名称的按钮必须唯一且 enabled，再执行单步动作并读取新状态。
- Xcode 的部分分发方式按钮没有可访问性名称；遇到这种情况先截图并观察当前布局。不要重放上次窗口坐标、按钮下标或连续盲点 Next。
- AppleScript 枚举前先 `set elems to entire contents of ...`，然后 `repeat with e in elems`；直接遍历未求值的 `entire contents` 在本次返回过 `-1700`。
- 按钮交互可用 `osascript` 的 argv 传参；命令行用参数数组。不要把 JSON 字符串当作 shell 转义，也不要改写 `HOME` / `CFFIXED_USER_HOME` 来切换账号环境。
- 网络签名与上传阶段按界面进度读取，单次等待不超过 60 秒，并向用户汇报实际阶段。
- 如果系统明确弹出钥匙串私钥访问授权，用户完成本机授权后继续；本次已有“始终允许”授权时不重复索取。

当次辅助代码保存在 [Organizer 操作脚本](../../output/ios-map-black-20260925/xcode_distribution_ui.py)，用于追溯实现方式。它固定了 `Archives` 窗口名，并非通用无人值守上传器；后续实现需按当前语言和窗口状态发现目标。

## 分发成功需要分阶段记录

| 状态字段 | 充分证据 |
| --- | --- |
| `archive_succeeded` | 归档成功，实际 `.app` 的 bundle/version/build 与目标一致 |
| `distribution_signature_verified` | 对实际分发 IPA 严格验证签名，核对 Gensen 团队、`get-task-allow=false`、`beta-reports-active=true` 及无设备 UDID 限制 |
| `uploaded` | Xcode / Apple 明确返回 `Upload succeeded`，记录时间、应用身份与版本 |
| `testflight_available` | App Store Connect 或手机 TestFlight 明确显示目标 build 可供该测试员安装 |
| `installed_via_testflight` | 对目标 build 执行 TestFlight 安装并等待“打开”，结合设备版本回读确认 |
| `device_map_verified` | 对最终安装包执行冷启动、前后台恢复、选城、地图拖动/缩放；断言与截图复核均通过 |
| `current_data_preserved` | 当前数据的更新前即时备份与安装后、测试后回读一致 |
| `temporary_qa_removed` | 明确移除本次 QA 包 / XCTest runner，并保留最终正式应用 |

上传后显示 `Uploaded package is processing` 时，仅设置 `uploaded`。构建/群组就绪不等于测试员可安装；本次曾出现群组“正在测试”但测试员“无可用构建版本”。

TestFlight 安装中弹出“此 App 已经安装”属于确认阶段，不能把安装请求的 XCTest 返回 0 当作安装已完成。要继续核实安装后的“打开”和对应 build。CoreDevice 的 **`builtByDeveloper=true` 不能单独区分开发直装和 TestFlight**，本次两个渠道均观察到该值。

实际 IPA 应在分发临时文件清理前保存到本次输出目录。路径从本次 Xcode 分发日志发现，不重用旧 `XcodeDistPipeline.*` 路径。核对实际 IPA 的 PCK 与已验证归档一致，native UUID 与被测试的 Release 二进制一致；开发重签后的整包哈希无需与分发 IPA 相等。

## 真机数据和地图黑屏回归

### 数据保留

每次安装前重新列出原应用当前 Documents，备份现有身份/外观/偏好及其他非缓存文件并记录 SHA-256。本次只有 `install_key.txt` 和 `region_choice.json` 两个文件，后续不能假定文件数永远是 2。私有文件保存在本次私有目录，报告只记录必要元数据和摘要。

采用同 bundle、同团队的原位更新；安装失败时保留原应用和即时备份，不卸载来强行安装。安装后先回读数据再启动，测试后再次核对。数据不符时暂停真实账号的进一步启动/玩法操作并调查；不要自动恢复历史身份或农场。地图 QA 不确认生成农场、搬迁、购买或奖励。

### 黑屏证据与修复不变量

用户原始症状是角色、HUD 和选址框可见，但底图全黑且一直“正在加载地图”，原生地图控件不存在。先记录当前截图/可访问性树及可取得的日志，再做冷启动，否则会丢失失败进程的现场。本次原包重启后恢复，原始低层触发错误没有被捕获。

[MapUnderlay.swift](../../tools/ios/MapUnderlay.swift) 的修复需要保留：

- listener 异步 ready / waiting / failed / cancelled 状态处理，失败后按 1–4 秒有界间隔恢复；后台抑制启动重试，前台重检。
- 仅绑定 `127.0.0.1:46464`；重建时关闭旧 peer，接收错误终止该连接循环。
- 选择前台正常窗口，兼容旧 Godot 窗口路径；显示地图和恢复前台时重设透明合成。
- 样式实际加载后才返回 READY；记录加载错误类型时不输出地图 token。

对照测试使用独立 `app.gensen.maps.mapqa`，**首次启动前**将其自身 `Documents/server.txt` 指向 `http://127.0.0.1:9/v1`。先停止原地图进程以释放桥端口，然后由测试临时占用 UDP 46464，启动 QA、选城，再释放端口，验证无需重启即可恢复。旧代码必须在预期恢复断言处失败，修复代码才以同条件对照；无关签名/设备失败不能算旧版复现。

该受控场景证明 listener 恢复缺口及修复效果，不能据此宣称用户首次黑屏一定是端口冲突。还需用实际 Release 归档二进制隔离重签验证，并在最终 TestFlight 安装包检查地图。

可复用 [JourneyDeviceUITests.swift](../../tests/ios/JourneyDeviceUITests.swift)：

| 方法 | 前提 / 结果 |
| --- | --- |
| `testInspectJourneyCurrentScreen` | 保留当前画面，采集故障现场 |
| `testNativeMapRecoversAfterListenerFailure` | 仅用于已隔离且已安装的 QA 包，验证短暂端口失败后的恢复 |
| `testQAMapReentryForegroundAndGestures` | QA 地图已加载；覆盖返回选城、上海、前后台和手势 |
| `testColdLaunchAndForegroundRecovery` | 最终原应用冷启动及前后台恢复 |
| `testCityMapEntryAndGestures` | **先确认当前为已观察过的城市选择布局**；现有点击坐标来自 iPhone 14 Pro，不适用于任意页面/设备 |
| `testInspectTestFlightInbox` | 只读取当前 TestFlight 页面，不保证刷新、邀请、安装或目标版本存在 |

地图通过标准包含原生控件断言和实际瓦片截图复核；单纯应用仍在前台不够。冷启动测试与选城测试按所需状态串行执行；不要依赖 XCTest 自动排序。

## 相关警告与已知边界

- `ITMS-90683`：Mapbox 引用 CoreLocation API，实际 IPA 必须含非空 `NSLocationWhenInUseUsageDescription`。[prepare_ios_signing.py](../../tools/ios/prepare_ios_signing.py) 已补齐用途说明；它不等于实现了 iOS 定位功能。build 1 邮件明确投递成功，该警告不是邀请缺失的已证实原因。
- MapboxCommon / MapboxCoreMaps 缺失匹配 dSYM：本次仍出现，Apple 接受了上传，影响原生崩溃符号化。保留真实警告，不生成空 dSYM 掩盖。
- CLI / GUI 账号不一致：回退流程已实证成功，机制未修复；自动化必须记录选择的发布通道。

## 本次成功基准与证据

| 项目 | 2026-09-25 结果 |
| --- | --- |
| 版本 | `0.16.37 (3)` |
| 上传完成 | 北京时间 12:38:46，Organizer / Gensen 云管理分发签名 |
| TestFlight | 12:41 确认可安装，12:48 原位安装完成 |
| 最终设备测试 | 2 项通过、0 失败，地图/角色/手势和前后台截图复核通过 |
| 数据 | 更新前、安装后、最终测试后的当前身份和城市选择逐字节一致 |
| 上传 IPA | 87,815,746 字节；SHA-256 `4d57334dba9bd5c2b09caa67d7b7038dffeb311dcae1907d3b3d77941a92d73c` |

[完整黑屏事件与修复](ios-map-black-2026-09-25.md) · [首次打包/账号/邀请调查](ios-testflight-2026-09-24.md) · [上传结果](../../output/ios-map-black-20260925/testflight-upload-result.json) · [实际 IPA 验证](../../output/ios-map-black-20260925/app-store-package-validation.json) · [最终真机状态](../../output/ios-map-black-20260925/validation.json)

本文件保存可复用结论和流程；`output/` 中的归档、私有备份、日志、图片和一次性驱动按本机产物保存，后续运行应生成自己的证据，不能把上次结果直接算作本次通过。
