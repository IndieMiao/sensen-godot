# 原生插件（C2 推送 / C3 选图 / C4 语音）

三件事在 Godot 里做不了，只能下到平台层：系统选图器、推送 token、实时语音。
三个插件同一套形状——**GDScript 只面向一个抽象（Bridge），工厂按平台给实现，给不出就返回 null，
上层降级而不是假装能用**。所以桌面跑测试、真机缺插件、插件缺依赖，都不会崩，只会少一块功能。

| 能力 | iOS | Android | 桌面 | 抽象 |
|---|---|---|---|---|
| C3 选图 | `native/photo_picker`（GDExtension，PHPicker） | `native/photo_picker/android`（Kotlin，Photo Picker） | DisplayServer 文件框 | `PhotoPicker` |
| C2 推送 | `native/push`（GDExtension，APNs token） | `native/push/android`（Kotlin，FCM token） | 无 | `PushBridge` |
| C4 语音 | `native/voice`（GDExtension）+ `tools/ios/SensenVoice.swift`（LiveKit） | `native/voice/android`（Kotlin，LiveKit Android） | 无（社区 godot-livekit，暂不带） | `VoiceBridge` |

单例名分别是 `SensenPhotoPicker` / `SensenPush` / `SensenVoice`。
**单例在不在 ≠ 能不能用**：桌面装的是空实现（有单例、`is_available()` 恒 false），
工厂会问一句再决定给不给桥。

## 构建

### iOS（GDExtension）

```
native/photo_picker/build_ios.sh [template_debug|template_release]
native/push/build_ios.sh
native/voice/build_ios.sh
```

每个脚本都是「编 godot-cpp → 编本扩展 → libtool 合成一个 `.a`」。godot-cpp 在 `native/godot-cpp`
（不进仓库，第一次要自己 clone），三个扩展共用同一份 `build_profile.json` 的类白名单，
所以不会互相触发重编。产物 `.a` **进仓库**（CI 与别的机器不重编）。

### iOS（Swift 侧，只有语音需要）

语音的音频链路在 `tools/ios/SensenVoice.swift`，用 LiveKit 的 client-sdk-swift，由
`tools/ios/setup_ios_g3.sh` 注入导出出来的 Xcode 工程（和 Mapbox 同一套注入逻辑）。
GDExtension 运行时用 `NSClassFromString("SensenVoiceCore")` 找它。

**为什么不做 Swift → C++ 回调**：Swift 类在 App target 里、GDExtension 在静态库里，编译期互不可见。
`VoiceBridge` 本来就约定了每帧 `poll()`，于是 Swift 只维护一个状态快照，C++ 每帧取一次、
与上一帧差分出信号。少一套函数指针注册，出问题也好查——快照打出来就知道卡在哪一档。

### Android（Kotlin 插件）

```
cd native/<name>/android && JAVA_HOME=<Android Studio 的 jbr> ./gradlew copyAars
```

产物 AAR 落到 `bin/`，由 `addons/sensen_<name>/export_plugin.gd` 在 Android 导出时塞进 Gradle。
Godot 插件 v2 靠 AAR 里 `AndroidManifest.xml` 的 `org.godotengine.plugin.v2.<Name>` meta-data 自注册。

## 各自还缺什么

### C2 推送

- **iOS**：拿的是 **APNs device token**（不引 Firebase iOS SDK；服务端 `src/http/apns.ts` 直连 APNs）。
  真机要拿到 token，provisioning profile 必须带 Push Notifications 能力、包里要有 `aps-environment`
  授权——需要付费开发者账号（SSLAUNCH A9）。没有时 `register_for_remote()` 走 `token_failed`，
  报「no valid aps-environment entitlement」，**这是预期，不是插件坏了**。
- **Android**：拿的是 **FCM registration token**。还要两样在应用侧：Firebase 控制台下发的
  `google-services.json` 放进 Android 导出模板的 `app/`，模板 `build.gradle` 加
  `com.google.gms.google-services` 插件。缺时 `FirebaseMessaging.getInstance()` 会抛，
  插件按 `token_failed` 回报，不崩。
- 服务端两条通道按 platform 分流，见 `server/README.md`「推送」。

### C4 语音

- 需要真的 LiveKit 服务与密钥（SSLAUNCH D2）：`LIVEKIT_URL` / `LIVEKIT_API_KEY` / `LIVEKIT_API_SECRET`。
  三项缺一服务端语音路由 503，客户端列表页会说「这台服务器还没开语音」。
- **麦克风闸门在服务端签的 token 上**（`video.canPublish`），不在客户端。上麦按钮只是请求；
  没有发布权限时 LiveKit 会拒，插件照实报 error，UI 保持静音。
- iOS 首次上麦弹系统麦克风授权（`NSMicrophoneUsageDescription` 已在导出预设里）。
  Android 的 `RECORD_AUDIO` 在插件 manifest 里，进房前运行时申请；**拒了也照样进房**，
  能听不能说——和「服务端没给发布权限」是同一种降级。
- 目前**只在前台工作**：没有申请 `UIBackgroundModes: audio`。切后台会断，回来重连。
  要做常驻语音再单独申请，那一项审核会被重点问。
- 桌面没有语音。要在 Mac 上联调得接社区的 godot-livekit GDExtension，本仓库暂不带。

## 安卓启动时那三行 GDExtension 报错是正常的

安卓包一启动会打三条 `No GDExtension library found for current OS and architecture (android.arm64)`，
分别对应三个 `.gdextension`。原因是安卓侧的能力来自 Kotlin 插件，`.gdextension` 里本就没有 android 条目。
**Godot 会强制把注册过的 `.gdextension` 打进包，导出预设的 exclude_filter 拦不住**（试过 `native/*`，无效），
所以这三行去不掉。判断插件到底有没有到位，看 logcat 里的 `GodotPluginRegistry`：

```
adb logcat | grep GodotPluginRegistry
# Initializing Godot plugin SensenPhotoPicker / SensenPush / SensenVoice
```

## 排查

- 真机上语音房显示「只能收听」→ 桥没给出来。依次看：`.gdextension` 的 `.a` 在不在、
  Xcode 工程里有没有 `SensenVoice.swift`（`setup_ios_g3.sh` 的注入是幂等的，工程已注入过就跳过，
  **重新导出后要重跑**）、LiveKit SPM 有没有解析成功。
- 推送一直没 token → 先看 `token_failed` 的 reason，多半是签名档没有推送能力。
- 桌面测试进程里这些单例都在、但都 `is_available() == false`，属正常。
