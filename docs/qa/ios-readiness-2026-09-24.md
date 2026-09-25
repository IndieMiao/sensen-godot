# Journey iOS / TestFlight / 真机就绪调查 · 2026-09-24

目标账号：`shaojie@gensen.app`。用户本轮要求调查当前版本打包、上传 TestFlight 及 iPhone 真机测试的环境、阻塞和可自动完成范围。

## 当前结论（2026-09-25）

**打包、真机连接、签名、TestFlight 上传和手机渠道安装均已完成。** 当前修复版为 `0.16.37 (3)`；选城黑屏的原生桥恢复修复通过旧版失败/新版通过的受控真机对照，实际 Release 二进制及最终 TestFlight 安装包的地图检查均通过。最终包冷启动/前后台/地图/拖动/缩放共 2 项测试、0 失败，当前身份和城市选择保留，临时 QA 包及 runner 已清理。build 3 于北京时间 12:38:46 上传、12:48 经手机 TestFlight 安装完成。见 [黑屏修复记录](ios-map-black-2026-09-25.md)。

Xcode GUI 中 `shaojie@gensen.app` / Gensen Admin 已登录。命令行账号列表为空、导出仍报 `No Accounts`，但 Organizer 可使用该账号的云管理分发证书，实际已成功上传。不需要再次要求用户登录来完成本次发布；命令行与 GUI 的账号状态不一致尚未修复。

已自动完成：正式 Gensen 应用身份配置、Godot 导出、原生编译和 Release 归档、图标不透明处理、定位用途说明补齐、开发/分发签名、原位安装和数据核对、XCTest 真机地图验证、TestFlight 上传及手机渠道检查。用户此前完成了 Apple 登录/双重验证、手机开发者模式/重启/解锁，以及 macOS 钥匙串授权。

仍有产品适配限制：iOS 游戏 POI 查询、目标城市样式、定位桥及 Godot 语音适配未完成；完整农场/钓鱼/矿坑和长期性能不在本轮基础地图验收范围。Mapbox 两个缺失 dSYM 警告影响原生崩溃符号化，未阻止上传。

[iOS 上传记录](ios-testflight-2026-09-24.md) · [定位用途说明记录](ios-location-purpose-2026-09-24.md)。以下保留 2026-09-24 初查及首次逐项解除阻塞的历史证据，不作为当前阻塞清单。

## 用户登录 Gensen、开启开发者模式后的进展

- 用户重启后，iPhone 14 Pro 实际返回 `developerModeStatus=enabled`、`ddiServicesAvailable=true`、`transportType=wired`、`tunnelState=connected`。查询已安装应用成功。
- Xcode 当前有登录账号，Gensen 团队 ID 为 **`XN4Z77ZX73`**。该账号同时有个人团队 `946LS6ZTGH`；本次明确使用 Gensen 企业团队。Gensen 开发证书显示姓名 `Zheyu Li`，证书 OU 为 `XN4Z77ZX73`；不能仅以证书显示名不等于邮箱判断账号错误。
- 用户提供 App Store Connect 截图：现有 Bundle ID **`app.gensen.maps`**、SKU `gensen-ios-maps-001`、Apple ID **`6815092667`**。据此使用现有应用身份。
- 用户截图中打开的是 `sensen-godot-v2-next/build/ios/sensen.xcodeproj`，并非本次 0.16.37 的隔离导出工程。没有修改该另一工作树；已打开本次正确的 `output/ios-readiness-20260924/export/sensen.xcodeproj` 供检查。
- 修正自动签名与 Release 强制 Apple Distribution 的冲突：构建/归档使用 Apple Development，App Store Connect 导出阶段自动选择分发签名。当前工作区 iOS 预设已设置 Gensen 团队、正式 Bundle ID 和 0.16.37 (1)；Android 的既有修改保留。
- 新增 `tools/ios/prepare_ios_signing.py`，对 Godot 导出工程配置自动签名、应用身份/版本、显示名，并生成本地 App Store 导出及 TestFlight 上传选项。只删除空的权限用途说明，未添加未实现功能的用途文案。
- Apple 已成功生成 `iOS Team Provisioning Profile: app.gensen.maps`，团队 `XN4Z77ZX73`，包含本次 iPhone 14 Pro，2027-09-24 到期。测试 runner 使用的同团队通配开发描述文件也已生成并包含该设备。
- 对正式 Bundle ID 查询所有类型的已安装应用，结果为空；后续安装不会覆盖该手机已有同标识应用。
- 新增独立 XCTest UI runner，覆盖冷启动、截图、切到后台和恢复前台；只做基础启动验证，不创建农场或执行资产操作。runner 自身编译也已进入签名阶段，尚未运行测试。

**当时的即时阻塞是 macOS 钥匙串私钥访问授权，后已由用户解除。** 正式应用与 XCTest runner 的 `codesign` 当时等待新 Gensen 开发证书，系统 `SecurityAgent` 已启动。用户在本机弹窗授权后，签名、真机基础测试、归档、分发 IPA 和上传均成功；未读取或索取密码。最新结果见顶部链接，不能将本节历史等待状态当作仍存在的签名阻塞。

证据与实现：

- [Gensen 签名准备状态](../../output/ios-readiness-20260924/gensen-signing-preparation.json)
- [正式应用开发签名构建日志](../../output/ios-readiness-20260924/xcode-release-device-signing.log)
- [独立真机测试 runner 构建日志](../../output/ios-readiness-20260924/device-ui-build.log)
- [安装前应用检查](../../output/ios-readiness-20260924/phone-existing-app-check.json)
- [签名配置工具](../../tools/ios/prepare_ios_signing.py)
- [XCTest 工程生成工具](../../tools/ios/create_device_ui_project.rb)
- [真机基础测试](../../tests/ios/JourneyDeviceUITests.swift)

后文账号/设备“未就绪”的记录保留为首次调查证据，不代表上述用户操作后的当前状态。原无签名构建日志保持不变，构建产物目录正被后续签名构建复用。

## 已实际验证

| 项目 | 结果 |
| --- | --- |
| 主机 | Apple Silicon / macOS 26.5.2 |
| Xcode | 26.6，build 17F113；命令行指向 `/Applications/Xcode.app/Contents/Developer`；首次启动检查通过 |
| SDK | iPhoneOS 26.5、iPhoneSimulator 26.5 已安装 |
| 真机调试支持 | `devicectl list preferredDDI --platform iOS` 返回 `isUsable=true`、`contentIsCompatible=true` |
| Godot | 4.7.2 stable；对应 iOS 导出模板存在 |
| 存储 | 系统盘约 128 GiB 可用；项目卷约 824 GiB 可用 |
| 发布基线 | 干净的 `sensen-godot-release-20260924` 工作树，commit `514fec6b1320313e335d4587b14de65e903b1e5c`；Android 发布版本 0.16.37 / 2026092405 |
| 当前源码导出 | `godot --headless --export-release iOS` 返回 0，生成独立 Xcode 工程；预设为 project-only |
| 真机编译 | `xcodebuild -configuration Release -sdk iphoneos -destination generic/platform=iOS`，显式关闭签名，返回 0 / `BUILD SUCCEEDED` |
| 原生地图依赖 | 使用已有锁定的 Mapbox Maps 11.29.1 / Common 24.29.1 / Turf 4.0.0 缓存；MapboxCoreMaps、MapboxCommon、Turf 均嵌入 `.app`，`otool -L` 中对应 `@rpath` 依赖均存在 |
| 签名检查 | 审计 `.app` 的 `codesign --verify` 明确返回未签名，符合本轮构建方式；不能直接安装或上传 |

复现了仓库的 `setup_ios_g3.sh` 原生代码/SPM 注入逻辑，输出改到独立调查目录。它的 Frameworks 文本替换锚点没有命中当前 Godot 模板，但 target 的 `packageProductDependencies` 生效，实际链接和嵌入均成功。因此**该锚点问题没有构成本轮编译阻塞**。

编译给出相机、相册、麦克风用途说明为空的警告；发布前需要按实际功能移除无用声明或补齐真实用途。UIKit `windows` 弃用等警告没有导致本次构建失败。

证据：

- [Godot 导出日志](../../output/ios-readiness-20260924/godot-release-export.log)
- [Xcode 真机 Release 编译日志](../../output/ios-readiness-20260924/xcode-release-unsigned.log)
- [完整编译命令](../../output/ios-readiness-20260924/unsigned-build-command.json)
- [编译与动态库检查结果](../../output/ios-readiness-20260924/unsigned-build-result.json)
- [独立导出工程](../../output/ios-readiness-20260924/export/sensen.xcodeproj)
- [无签名审计产物](../../output/ios-readiness-20260924/derived-data/Build/Products/Release-iphoneos/sensen.app)

## TestFlight 阻塞与未验证项

1. **目标账号尚无可用的本地登录证据。** Xcode 的 `DVTDeveloperAccountManagerAppleIDLists / IDE.Identifiers.Prod` 当前为空；没有发现目标账号的对应钥匙串条目。本机唯一有效代码签名身份是 `Apple Development: prismoshaojie@126.com`，证书团队为个人团队 `53LT77CV6R`，并非本次指定账号的已验证签名身份。
2. **没有本地可用的 Apple Distribution 身份或 App Store 分发描述文件。** 唯一描述文件是个人团队的 `com.sensen.mapg3` 开发配置，2026-09-29 到期，包含 iPhone 13 和旧 iPhone 15，不包含 iPhone 14 Pro。该个人团队配置不能用于 TestFlight。目标团队登录和权限具备后，可通过 Xcode 自动签名创建/取得所需配置；不能直接把本地缺少证书等同于云端没有证书。
3. **现有 iOS 预设仍是旧 PoC。** Team ID=`ABCDE12345`，Bundle ID=`com.sensen.mapg3`，版本=`0.1.0 (1)`，显示名=`SensenAvatar`，且 `export_project_only=true`。原有 `build/ios` PCK 为 9 月 22 日产物。本轮新生成的工程使用最新游戏源码，但保留上述旧元数据用于调查，不是正式 Journey 发布包。需要核对目标团队的正式 Bundle ID / App Store Connect 应用记录，设置 Journey 版本、合规且未占用的 iOS build number、用途说明和 App Store 导出方式。
4. **Apple 云端状态尚未确认。** Xcode 缓存中存在企业团队 `TALCYZ9Z82`（Vientiane Sensen (Shanghai) Technology Co., LTD），但缓存不能证明它属于目标账号或当前可用。需要用 `shaojie@gensen.app` 核实 Developer Program 会员、团队、上传权限和应用记录。当前浏览器连接列表为空，无法读取 App Store Connect。常见本地 API key 目录及相关环境变量也未发现可用配置；这不是“必须提供 API key”的结论，Xcode 登录也可建立发布通道。

账号登录、双重认证以及如实际出现的会员/协议确认需要用户在 Apple 界面完成。账号密码和验证码不需要写进项目或聊天。完成登录后即可继续核实云端信息；目前没有证据断言会员未开通、账号无权限或应用不存在。

## 真机调查

以下表格为首次调查时状态；用户随后重新接线的结果见本节后续记录。

| 设备 | 当前可证实状态 | 阻塞 |
| --- | --- | --- |
| iPhone 13，iOS 26.5，设备名 `iPhone` | Xcode 列表标记 available；已配对，开发者模式 enabled；CoreDevice 记录为网络连接 | 实际 `device info details` / `lockState` 返回设备未解锁，错误 10003 / RemotePairing 1016；不能视为可执行安装/测试 |
| iPhone 14 Pro，iOS 26.3，设备名 `shaojie的iPhone` | 存在配对记录；缓存显示开发者模式 disabled | 当前不可达；需连接、解锁，确认信任并开启开发者模式；所需开发描述文件尚未配置 |

首次查询时未取得目标设备可用的有线调试连接，本轮未在任何配对设备上安装或启动应用。iPhone 14 Pro 需在“设置 → 隐私与安全性 → 开发者模式”开启并完成手机端确认。这里的开发者模式要求针对 Xcode 直装调试；通过 TestFlight 安装测试无需开发者模式。

### 用户重新接线后的复查

用户表示重新连接一台 iPhone，要求检查这台设备。复查确认当前有线设备就是 **iPhone 14 Pro / iOS 26.3 / `shaojie的iPhone`**，以实际 wired 连接识别，不把另外两台历史配对设备当作本次测试目标。

- CoreDevice：`pairingState=paired`、`transportType=wired`、`tunnelState=connected`；Xcode 标记 `available=true`，无连接错误。
- 开发者模式仍为 `disabled`，`ddiServicesAvailable=false`；当前不能进行完整 Xcode 开发调试。
- 锁定状态查询成功，返回 `passcodeRequired=true`、`unlockedSinceBoot=true`；需在手机上解锁并保持可访问。
- Xcode 登录账号数仍为 0，目标账号的签名问题尚未解除。
- 本轮没有安装、启动或删除任何手机应用。

USB 核验修正：本机 macOS 支持的查询类型是 `SPUSBHostDataType`，并非首次使用的 `SPUSBDataType`。首次该命令的空结果不应单独用于判断未接线。复查使用 `SPUSBHostDataType` 和 IOUSB 注册表均检测到 iPhone，并与 CoreDevice 的 wired 状态相互印证。

[重新连接后的状态证据](../../output/ios-readiness-20260924/reconnected-iphone-status.json)。手机下一步需手动开启开发者模式，按系统提示重启并确认开启，然后解锁；Apple 账号登录仍是独立的签名前提。

现有 Apple 工具能支持签名就绪后的安装、启动、日志、崩溃和性能采集。当前项目没有 iOS 真机触摸测试 runner；不能把 `devicectl` 能启动应用等同于已具备完整触摸自动化。可以增加签名的 XCTest UI 测试 runner，通过点击、拖动、长按、捏合和截图验证游戏画布；需在实际设备上验证输入和结果，不能用模拟器结果代替真机验收。游戏资产操作仍应使用隔离测试账号，保留真实用户当前身份和存档。

另一个模拟器限制：当前 Godot 模板的 simulator XCFramework 元数据宣称 arm64/x86_64，但 `lipo -info` 显示库实际只有 x86_64。Apple Silicon 模拟器构建链尚未验证，可能需要更换/重编模板；该问题没有阻止本次 arm64 真机编译。

## 当前 iOS 功能缺口

- `MapBridgeIOS` / `MapUnderlay.swift` 目前实现 CREATE、CAM、VIS、LANG 和 READY，能提供旧版原生底图桥。
- `request_pois()`、`set_city_style()` 和 `start_location()` 未在 iOS 桥实现，继承基类的 unsupported / 空实现。因此 Android 当前的原生 POI、浅色城市底图样式和设备定位尚未在 iOS 达到一致能力；系统鱼塘目录等共享游戏逻辑不能据此一并判定失效，需分别验收。
- Apple LiveKit Swift 库已有代码，但缺少暴露 `GodotVoice` 的 iOS 适配层、导出集成及设备音频验证。现有游戏 `supported()` 会返回 false，不能宣称 iOS 组队语音可用。
- 新版农场、矿坑、鱼塘、Griffith、动画、地图返回、安全区与触摸交互尚未完成当前版本 iOS 真机验证。

源码依据：[iOS 地图桥](../../scenes/map_poc/map_bridge_ios.gd)、[地图基类](../../scenes/map_poc/map_bridge.gd)、[Swift 底图](../../tools/ios/MapUnderlay.swift)、[Apple 语音说明](../../native/voice/apple/README.md)。上述功能缺口属于完整体验验收范围；不应与账号登录/签名导致的打包上传阻塞混为一谈。

## 自动完成范围与最少人工步骤

- **已自动完成：** 工具链、签名元数据、描述文件、设备与 DDI、项目差距检查；从当前发布源码隔离导出；真机 ARM64 Release 无签名编译；原生动态库完整性检查。
- **不依赖 Apple 登录即可推进：** iOS 导出脚本整理、版本和发布配置草案、地图/语音平台适配、测试 runner 编写、编译排错。正式 Bundle ID / Team 的最终取值应依据已验证的账号应用记录。
- **账号与设备就绪后可以自动推进：** 自动签名、Archive/IPA、安装与启动、日志/截图及 XCTest 场景验证、问题修复、TestFlight 上传及处理状态查询。上传完成、Apple 处理完成、真机验收是不同阶段，应分别记录证据。
- **用户需要完成：** 在 Xcode Settings → Apple Accounts 登录 `shaojie@gensen.app` 并完成双重认证；用该账号进入 App Store Connect 以确认团队/应用权限；保持本次已连接的 iPhone 14 Pro 解锁，开启开发者模式并完成手机端重启/确认。Apple 自身的构建处理或外部测试审核不能由本地工具跳过。

建议执行顺序：目标账号与手机就绪 → 确认正式 iOS 应用身份并生成开发签名包 → 农场/地图/钓鱼/矿坑/后台恢复等真机基础验证和修复 → 按测试范围补齐原生能力 → 归档、分发签名、上传 TestFlight、核实处理结果。
