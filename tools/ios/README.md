# iOS 发布与真机工具

后续 iOS / TestFlight 自动化先读 [已验证流程与故障处理](../../docs/qa/ios-testflight-automation.md)。其中记录了 CLI 报 `No Accounts`、但 GUI 仍已登录时的 Organizer 回退方式，以及地图黑屏回归、实际 IPA 检查和当前设备数据保留要求。

| 工具 | 用途 |
| --- | --- |
| [prepare_ios_signing.py](prepare_ios_signing.py) | 为 Godot 导出工程设置团队、bundle、版本、自动签名、定位用途说明，以及导出/上传 ExportOptions；参数见 `--help` |
| [flatten_app_icons.swift](flatten_app_icons.swift) | 去除导出 AppIcon 的 alpha 通道，保留已有图像内容 |
| [create_device_ui_project.rb](create_device_ui_project.rb) | 生成独立 XCTest UI runner 工程；输入输出目录和团队 ID |
| [MapUnderlay.swift](MapUnderlay.swift) | iOS 原生地图桥，含 listener 失败恢复及前台窗口处理 |
| [AppleSignIn.swift](AppleSignIn.swift) | Sign in with Apple 原生桥（回环 UDP 46465），由 G3Spike.mm 拉起 |
| [inject_apple_sign_in.py](inject_apple_sign_in.py) | 把 AppleSignIn.swift 编入导出工程并加 `com.apple.developer.applesignin` entitlement；须在 MapUnderlay 注入之后跑，可重复执行 |
| [JourneyDeviceUITests.swift](../../tests/ios/JourneyDeviceUITests.swift) | 真机截图、基础地图手势和隔离地图恢复回归 |

`setup_ios_g3.sh` 是旧地图 PoC 导出入口；当前应用身份及签名元数据应按上述准备工具和发布流程重新核对。

本次成功交付记录：[iOS 黑屏修复与 TestFlight build 3](../../docs/qa/ios-map-black-2026-09-25.md)。上传回退曾借助本次 `output/` 下的单步 GUI 驱动完成；目前这些工具尚未组成通用无人值守发布器。
