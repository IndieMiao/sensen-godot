# iOS 定位用途说明修复 · 2026-09-24

## 当前状态（2026-09-25）

该元数据修复已合入黑屏修复版 **`0.16.37 (3)`**，成功上传 App Store Connect，并已在 iPhone 的 TestFlight 显示为可安装。实际上传 IPA 的定位用途说明、Gensen 分发签名、版本和游戏 PCK 均已核对。build 2 只保留历史归档，不再作为待上传版本。

命令行仍报 `No Accounts`，但用户 Xcode GUI 账号已登录；使用 Organizer 的云管理分发签名成功完成 build 3 上传。详见 [最新上传记录](ios-testflight-2026-09-24.md) 和 [黑屏修复记录](ios-map-black-2026-09-25.md)。下文是 build 2 的历史修复与当时阻塞。

## Apple 邮件确认的问题

用户提供的邮件针对 Gensen / Apple ID `6815092667` / `0.16.37 (1)`，内容为：

> Although delivery was successful, you may want to correct the following issues in your next delivery.
>
> ITMS-90683: Missing purpose string in Info.plist
>
> The Info.plist file for the “sensen.app” bundle should contain a NSLocationWhenInUseUsageDescription key with a user-facing purpose string.

Apple 同时说明，外部 SDK 引用敏感 API 时，即使应用暂未使用这些 API，也仍需要用途说明。本项目原生地图链接 Mapbox，build 1 的归档/IPA 确实没有该键。

邮件明确本次投递成功，build 1 在用户后续截图中也已显示绿色“准备测试”。**该邮件不能作为 TestFlight 邀请缺失的原因证据。** 邀请发出、收件和接受状态仍需独立核实。

[用户提供的邮件正文](../../output/ios-location-purpose-20260924/apple-itms-90683-user-mail.png)。该图仅为相关 Apple 邮件正文，不含用户此前邮箱列表中的无关邮件内容。

## 已完成的修复

- 保持市场版本 `0.16.37`，iOS build number 增至 **2**。
- 在 iOS 导出预设中设置 `privacy/location_usage_description`。
- [导出准备工具](../../tools/ios/prepare_ios_signing.py) 对未提供定位用途说明的 Godot 导出工程补齐 `NSLocationWhenInUseUsageDescription`，保留已有非空说明。
- 当前说明为：`Your location helps Journey select a nearby city and center the map when you use location features.`
- 不增加 Always/background 定位权限，不主动请求系统定位，也不声称 iOS 定位桥已实现；本次修复是发布元数据。
- build 2 使用独立输出目录，保留 build 1 的 IPA、归档和上传证据。游戏源码仍来自发布提交 `514fec6b1320313e335d4587b14de65e903b1e5c`。

## 验证和新的发布阻塞

**build 2 归档成功，尚未完成 App Store 导出或上传。**

- `xcodebuild archive` 返回 0 / `ARCHIVE SUCCEEDED`。
- 实际归档 `Info.plist` 已回读：`CFBundleIdentifier=app.gensen.maps`、`CFBundleShortVersionString=0.16.37`、`CFBundleVersion=2`，定位用途说明非空且与预期一致；没有新增其他 Location 权限键。
- 游戏 PCK 与 build 1 的真机测试版本完全相同，SHA-256：`84cd47e37b1845062ff11e931afcef8c11e9730fc5dd9cebae20317a6dd6c7d7`。本次未重复无关的完整玩法测试，也未更新手机上的 build 1。
- App Store 导出于本机时间 2026-09-24 23:35 返回 70，明确报 **`No Accounts`** 和 **`No signing certificate "iOS Distribution" found`**。
- 随后实时核实 Xcode 的 `DVTDeveloperAccountManagerAppleIDLists / IDE.Identifiers.Prod` 数量为 **0**，而首次成功上传时曾为 2。Gensen 团队缓存和开发证书仍在，但本机没有可用于此导出的分发私钥身份；首次成功分发依赖 Xcode 登录后的发布签名通道。不能用缓存团队或开发证书替代当前缺失的登录状态。
- 已要求用户检查 Xcode Settings → Apple Accounts 中的 `shaojie@gensen.app`，按实际状态恢复登录。没有修改账户存储、恢复历史登录列表或请求用户在聊天中提供密码。

当时计划恢复登录后导出 build 2；后续已由包含同一元数据修复的 build 3 替代，并通过已登录的 Xcode Organizer 完成分发。不要再次上传 build 2。

证据：[准备记录](../../output/ios-location-purpose-20260924/preparation.json) · [归档结果](../../output/ios-location-purpose-20260924/archive-result.json) · [归档日志](../../output/ios-location-purpose-20260924/archive.log) · [分发导出失败结果](../../output/ios-location-purpose-20260924/app-store-export-result.json) · [分发导出日志](../../output/ios-location-purpose-20260924/app-store-export.log)
