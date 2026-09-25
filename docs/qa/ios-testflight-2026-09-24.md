# Journey iOS 打包、真机检查与 TestFlight 上传 · 2026-09-24

## 当前结果（2026-09-25）

**修复版 `0.16.37 (3)` 已通过 Gensen 上传、完成 Apple 处理，并经 TestFlight 原位安装到这台 iPhone。** 黑屏修复及定位用途说明均包含在 build 3；实测的 Release 二进制与上传 IPA 的 UUID 一致，游戏 PCK 与 build 1 一致。最终 TestFlight 包的冷启动、前后台恢复、地图/角色、拖动和缩放共 2 项测试通过、0 失败，截图已复核。身份和城市选择文件逐字节保留；QA 包及 runner 已清理。详见 [黑屏修复记录](ios-map-black-2026-09-25.md)。

用户提供 Xcode 设置截图，显示 `shaojie@gensen.app` 已登录、Gensen 团队角色 Admin。命令行导出仍报 `No Accounts`，其账号列表为空；这不能描述为用户没有登录。改用同一 Xcode 进程的 Organizer 分发成功取得 **Cloud Managed Apple Distribution**，于 **2026-09-25 12:38:46（北京时间）**返回 `Upload succeeded`。没有退出用户账号、修改账号存储或要求重新登录。命令行与 GUI 的账号状态不一致仍可另行排查，但已不阻塞本次上传。

实际上传 IPA 已从本次 Xcode 分发流水线保存并验证：87,815,746 字节，SHA-256 `4d57334dba9bd5c2b09caa67d7b7038dffeb311dcae1907d3b3d77941a92d73c`；Apple Distribution: Gensen，`get-task-allow=false`、`beta-reports-active=true`，没有设备 UDID 限制。应用 `app.gensen.maps`、版本 `0.16.37 (3)`、定位用途说明和资源 PCK 均正确。分发时关闭自动修改版本号，保留符号上传，未限制为 internal-only。

[上传结果](../../output/ios-map-black-20260925/testflight-upload-result.json) · [Apple 成功日志](../../output/ios-map-black-20260925/testflight-upload-success-evidence.log) · [上传完成截图](../../output/ios-map-black-20260925/xcode-upload-current.png) · [实际 IPA 验证](../../output/ios-map-black-20260925/app-store-package-validation.json) · [TestFlight build 3 页面](../../output/ios-map-black-20260925/testflight-after-build3-upload-attachments/testflight-inbox.png)

## build 1 的邀请和首次安装历史

build 1 在 2026-09-24 上传成功并完成 Apple 处理。用户创建 GensenMap Internal 并添加 `shaojie@gensen.app` 与 `joey@gensen.app`；先前出现构建正在测试、测试员却“无可用构建版本”的不一致，随后用户截图确认两人均为“已邀请”。具体解除关联问题的网页操作未独立核实。

早期手机 TestFlight 空列表和“兑换”按钮是历史观察。之后直接读取手机 TestFlight，已经确认 Gensen / `0.16.37 Build 1` /“打开”/兼容，此次 black-map 修复前确已完成 TestFlight 安装。不能仅凭 CoreDevice 的 `builtByDeveloper` 字段判断安装渠道。

`gensen.app` 的 MX 指向 Google；飞书连接没有对应邮箱，Gmail 未接入，未搜索收件箱/垃圾箱或代发邀请。Apple 的 ITMS-90683 邮件明确投递成功，缺少定位用途说明与邀请问题没有已证实因果关系。该元数据修复先归档为 build 2，后合入 build 3；不要再上传已被替代的 build 2。

[已邀请截图](../../output/ios-readiness-20260924/testflight-invited-20260925-user-screenshot.png) · [build 1 TestFlight 安装证据](../../output/ios-map-black-20260925/testflight-installed-source-attachments/testflight-installed.png) · [最初邮箱与邀请调查](../../output/ios-readiness-20260924/testflight-invitation-diagnosis.json)

以下签名、测试与 IPA 数值保留为 **2026-09-24 build 1 的首次交付记录**，当前 build 3 的结果以上文和黑屏修复记录为准。

| 身份 | 值 |
| --- | --- |
| 用户指定 Apple 账号 | `shaojie@gensen.app` |
| 团队 | Gensen / `XN4Z77ZX73` |
| Bundle ID | `app.gensen.maps` |
| App Store Connect Apple ID | `6815092667` |
| SKU | `gensen-ios-maps-001` |
| 版本 / build | `0.16.37 / 1` |
| 游戏源码基线 | `sensen-godot-release-20260924`，commit `514fec6b1320313e335d4587b14de65e903b1e5c` |
| 真机 | `shaojie的iPhone` / iPhone 14 Pro / iOS 26.3 |

用户截图中的 `sensen-godot-v2-next` 旧工程没有被修改。实际安装和归档使用当前 0.16.37 发布源码的隔离导出工程，应用身份、签名和权限清理通过本轮工具应用。

## 已解决的阻塞

- 用户登录 Gensen 后，企业团队开发证书和包含这台手机的开发描述文件均已取得。证书显示姓名为 Zheyu Li，团队 OU 正确为 `XN4Z77ZX73`；邮箱证书所属的个人团队没有被用于本次发布。
- 用户开启手机开发者模式并重启后，USB 配对、CoreDevice tunnel 和 DDI 服务均可用。
- 修正 Release 自动签名与强制 `Apple Distribution` 的冲突：构建/归档使用开发签名，App Store 导出自动取得 **Apple Distribution: Gensen (XN4Z77ZX73)** 分发签名。
- 用户完成 macOS 钥匙串私钥访问授权后，应用和 XCTest runner 均成功签名。
- iOS 预设从占位 Team ID / `com.sensen.mapg3` / `0.1.0` 更新为正式应用身份和版本。未更改 Android 发布身份。
- 删除导出工程中空的相机、相册、麦克风用途键，消除对应构建警告；没有添加未实现用途的权限文案。
- 导出图标带透明通道。使用图标原有中心颜色填充透明区域，保持尺寸和不透明绘制内容；全部 16 张 AppIcon PNG 已转为不带 alpha 的图像，1024px 图标检查通过。

## 真机验证与边界

在正式 `app.gensen.maps` 应用外使用独立 XCTest runner。安装前查询包括默认/商店应用在内的同 Bundle ID，结果为空；本次没有覆盖已有同标识应用。

两项 XCTest 执行成功，0 个测试失败，截图已人工复核：

1. 冷启动显示城市选择界面；切到后台再恢复前台，界面正常。
2. 从观察到的城市选择布局点击洛杉矶，显示原生 Mapbox 底图与 3D 角色；拖动后街区位置改变；双指缩放使界面 Zoom 16 → 17，选址框与地图比例同步变化。

冷启动首张截图出现 iOS 无线数据权限提示；恢复前台后的截图显示城市选择页，后续地图瓦片实际加载。没有把权限提示本身当作网络登录通过证据，也不声称本轮核实了完整服务器登录/农场结算。

本轮只选择本地城市并浏览新用户的农场选址地图，**没有点击“Generate farm here”、确认创建农场、搬迁、购买、钓获或改变资产**。完整农场、钓鱼、矿坑及语音未在这轮 iOS 真机中验收。没有把启动测试推广为完整玩法验收。

安装结果已回读为 `Journey / app.gensen.maps / 0.16.37 (1)`。手机保留开发签名版本及新产生的本地身份/偏好；测试结束后正常停止本轮 app 进程，移除本次创建的 XCTest runner。未卸载正式应用、恢复历史身份/农场，或更改手机显示设置。

- [启动/前后台测试结果](../../output/ios-readiness-20260924/phone-smoke-result.json)
- [地图手势测试结果](../../output/ios-readiness-20260924/phone-map-result.json)
- [地图进入截图](../../output/ios-readiness-20260924/phone-map-attachments/04-city-map-entry.png)
- [拖动后截图](../../output/ios-readiness-20260924/phone-map-attachments/05-map-after-drag.png)
- [缩放后截图](../../output/ios-readiness-20260924/phone-map-attachments/06-map-after-pinch.png)
- [安装回读](../../output/ios-readiness-20260924/phone-installed-readback.json)

## 分发产物和上传证据

- [App Store IPA](../../output/ios-readiness-20260924/app-store-package/sensen.ipa)：87,800,303 字节。
- SHA-256：`93ad1b77d45f1cc142a06f3beebb33df68709c29a9d83eab6b08cfa30179c5e5`。
- `codesign --verify --deep --strict` 通过；签名为 Apple Distribution: Gensen；`get-task-allow=false`、`beta-reports-active=true`，没有设备 UDID 限制列表。
- 手机开发构建、归档及 App Store IPA 的游戏 PCK 一致：SHA-256 `84cd47e37b1845062ff11e931afcef8c11e9730fc5dd9cebae20317a6dd6c7d7`。
- App Store 包使用同一游戏资源及原生源码；与先装到手机的开发版本相比，分发签名和 AppIcon 的 alpha 处理不同。不能声称手机直装的是 TestFlight 分发 IPA。
- 上传使用同一归档，通过 Xcode 已登录账号的发布通道，未向聊天中索取账号密码或创建额外 API Key。
- Apple 于本机时间 **2026-09-24 20:37:28** 返回上传成功并开始处理。后续用户截图确认上传处理“完成”，构建 1 关联 GensenMap Internal，状态“准备提交”，具备内测分发条件；测试员接收及安装待确认。

[分发包验证](../../output/ios-readiness-20260924/app-store-package-validation.json) · [上传结果](../../output/ios-readiness-20260924/testflight-upload-result.json) · [上传日志](../../output/ios-readiness-20260924/testflight-upload.log) · [总验证记录](../../output/ios-readiness-20260924/validation.json)

[App Store Connect TestFlight](https://appstoreconnect.apple.com/apps/6815092667/testflight/ios)

## 尚存限制

- **渠道状态以当前手机记录为准。** build 3 已上传、经本机 TestFlight 安装并通过最终地图检查。Joey 自己的设备安装未检查；没有另行代发邀请。
- **Mapbox dSYM 警告。** 上传接受了二进制，但提示 MapboxCommon UUID `6D22EF3C-09EC-3233-9756-DD825CFBE7D7`、MapboxCoreMaps UUID `C0622123-A07B-379D-9E58-87A33BAA20A0` 缺少 dSYM。已检查本机对应 SDK 缓存与源码包，未找到匹配符号；这影响对应原生崩溃的符号化，不构成本次上传失败。未生成虚假的空 dSYM 以掩盖警告。
- **iOS 平台适配仍有缺口。** 游戏自己的 POI 查询、浅色城市样式、设备定位尚未接入 iOS 桥；底图自身可见的 Mapbox 图标不能作为游戏 POI 查询已实现的证据。Godot 语音适配层未接入。真机选址页还观察到部分英文文案。
- **验证范围有限。** 当前只完成上述基础启动和地图手势检查；完整玩法、长期性能、音频、各尺寸与全部本地化仍需专项验收。

## 本轮可复用工具

- [签名和发布元数据准备](../../tools/ios/prepare_ios_signing.py)：配置自动签名，生成本地导出和上传 ExportOptions。
- [AppIcon 不透明处理](../../tools/ios/flatten_app_icons.swift)：仅处理导出的图标资源。
- [独立 XCTest 工程生成](../../tools/ios/create_device_ui_project.rb) 与 [测试源文件](../../tests/ios/JourneyDeviceUITests.swift)。工程生成依赖 `xcodeproj` Ruby gem，本机使用已有 Homebrew CocoaPods 环境，不安装额外全局包。
- 完整 Godot 导出、编译、归档、导出和上传命令保存在同一 `output/ios-readiness-20260924/` 目录的 `*-command.json` 中。

服务器继续使用既有 Journey 服务；本轮没有部署服务器或迁移游戏数据。外部交付范围仅为用户本次指定的 App Store Connect/TestFlight 上传。
