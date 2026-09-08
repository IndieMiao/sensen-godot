# 发布流程与版本管理（发布链 B7，SGODOT-72）

适用于海外社交主线（`feat/next-feature` → `main`）的客户端（Godot 双端）与服务端（`server/`）。
目标：任何一次装到别人手机上的包，都能在 5 分钟内回答「这是哪个提交、用什么版本的 Godot 导的、
服务端跑的是哪个镜像」，并且能退回上一版。

## 1. 版本号

| 端 | 字段 | 规则 |
|---|---|---|
| 客户端 marketing 版本 | Android `version/name`、iOS `application/short_version` | 语义化 `MAJOR.MINOR.PATCH`；Demo 期 `0.x`，提审前定 `1.0.0` |
| 客户端构建号 | Android `version/code`、iOS `application/version` | **单调递增整数**，两端同一个数；每次出可分发包 +1，不回退（Play / TestFlight 都拒收重复或更小的号） |
| 服务端 | 镜像 tag = git sha，部署只认 digest | 见 `.github/workflows/server.yml` 的 release-manifest |
| 内容 | `content_version`（healthz 返回） | 由 `assets/farm/data` 哈希得出，不手改 |

两端字段都在 `export_presets.cfg`；改号只改这一处，`tools/release/manifest.sh` 会读出来写进清单。

## 2. Tag 规范

- `v0.3.0`：正式版本，打在 `main` 上，与 marketing 版本一致。
- `v0.3.0-rc.1`：候选；TestFlight / Play 内测用这个号，转正时只补 `v0.3.0` tag 不重新构建。
- `demo-20261015`：投资人演示包（发布链 B8）。tag 名带日期，附注写演示剧本版本与预置账号批次。
- tag 一律 annotated（`git tag -a`），注释里写 release-manifest 的 `git_sha` 与两端构建号。

## 3. Changelog

`CHANGELOG.md`（仓库根，Keep a Changelog 格式）：每个 tag 一节，按 `Added / Changed / Fixed / Security / Compliance` 分组。
提交信息已经是「feat(app): …」体例，出版本时用 `git log --format='- %s' <prev>..HEAD` 起草再人工合并。
`Compliance` 一组单列：权限、隐私申报、删号 / 年龄门 / 同意版本号变化——提审备注（SSLAUNCH E9）直接引用它。

## 4. 发布清单（release-manifest）

- 服务端：`server.yml` 产出 `release-manifest.json`（git sha + 镜像 digest）。
- 客户端：`tools/release/manifest.sh <apk|ipa|.app…>` 产出 `release-manifest-client.json`：git sha / tag / 分支、Godot 版本、
  两端包名与版本号、每个产物的 sha256 与大小（`.app` 目录给整树指纹）。CI 的 Android 任务已自动附在产物旁。
- 两份清单一起归档到 tag 的 GitHub Release 附件；投资人包另抄一份到 SSLAUNCH E12 的装机记录里。

## 5. 出包步骤

### 5.1 发布前检查（缺一不出包）

1. `tools/run_tests.sh` 全绿；`server` 的 `pnpm -r typecheck && pnpm -r test` 全绿；CI `godot` / `server` 两条工作流绿。
2. i18n：`godot --headless --path . --script res://tools/i18n/extract_pot.gd -- --check` 通过。
3. **导出预设里去掉开发期钥匙**：iOS `additional_plist_content` 的 `NSAllowsLocalNetworking` 与
   `NSLocalNetworkUsageDescription`（真机连局域网服务用的，见 `2026-09-07-qa-flow-device.md` §6.1）。
4. `native/photo_picker` / `native/push` / `native/voice` 都有 `template_release` 版 iOS 静态库（各自 `build_ios.sh template_release`），`.gdextension` 指到它；
   四个安卓插件的 AAR 都跑过 `./gradlew copyAars`。
5. **16 KB 页对齐**：`tools/release/check_elf_alignment.py <apk|aab>` 全绿。Google Play 从 2025-11 起要求
   target Android 15+ 的应用满足这一条。⚠️ 已知不达标项见下方「已知阻塞」。
6. `config/firebase.json` 指向目标环境的 Firebase 项目；`mapbox_token.txt` 是目标主体的 token（SSLAUNCH D3 后换）。
7. 服务端 `.env` 是目标环境（prod / qa）的一套，`UPLOAD_LOCAL_DIR` 关掉、`R2_*` 四项齐。
8. 构建号 +1，marketing 版本按 §1；`CHANGELOG.md` 补齐当前节。
9. **应用身份不是占位**：`Brand.PLACEHOLDER` 为 `false`，且 `assets/brand/logo_mark.svg` 已换成正式标识。
   占位标识是个通用定位图钉，长得像"正常图标"，很容易带着出包。品牌决策 = SSLAUNCH B1，
   未拍板前这条必然拦住提审（E6 / R11，SGODOT-66）。换素材见 §5.1.2 与 `assets/brand/README.md`。

### 5.1.1 Mapbox 安卓依赖必须用 `-ndk27` 后缀的 artifact

Mapbox 同一个版本发两套产物：默认的 `com.mapbox.maps:android` 是 **4 KB** 对齐（NDK 26 编的），
带 `-ndk27` 后缀的 `com.mapbox.maps:android-ndk27` 才是 **16 KB** 对齐（11.7.0 起提供）。
名字看不出差别，扫一遍才知道——所以 §5.1 第 5 条那个脚本是必须跑的，别凭版本号判断。

本仓库两处都要写成 `-ndk27`，改一处漏一处会出现「AAR 对齐了但 APK 没对齐」：

- `native/map/android/build.gradle.kts` 的 `implementation`
- `addons/sensen_map/export_plugin.gd` 的 `_get_android_dependencies`（APK 的 Gradle 构建按它解析）


### 5.1.2 三端开屏：改一处会漏两处

开屏取值同源于 `modules/brand/brand.gd`（`Brand`），但引擎和导出器各读自己配置文件里的**字面值**：

| 端 | 实际读的地方 |
|---|---|
| Godot 引擎开屏 | `project.godot` → `[application]` 的 `boot_splash/*` 与 `config/icon` |
| iOS 启动画面 | `export_presets.cfg` → `[preset.1.options]` 的 `storyboard/*` |
| Android 12+ 系统开屏 | `export_presets.cfg` → `[preset.0.options]` 的 `launcher_icons/*` |

安卓侧**不要**改 `android/build/res/values/themes.xml`：那份 `GodotAppSplashTheme` 是导出时自动生成的
（文件头自己写着会被覆盖），而且 `android/build` 是 gitignore 的，重装模板即丢——同 B5 地图垫底
改成独立 AAR 的原因。它引用的 `@mipmap/icon_background` 与 `@drawable/splash_icon` 由
`launcher_icons/*` 和 `boot_splash/image` 在导出时生成，所以只改导出预设就够，不需要 `custom_theme_attributes`。

Godot 4.7 的 iOS 侧没有 `use_launch_screen_storyboard` 开关（storyboard 常开），按旧版文档写这个键是死键。

`tests/app/test_brand_splash.gd` 守护这三处不漂移：只改 `Brand` 忘了改配置、或反过来，都会红。

### 5.2 Android

```
godot --headless --path . --export-debug   Android build/sensen-demo-debug.apk    # 内测 / 演示
godot --headless --path . --export-release Android build/sensen.aab               # Play（发布链 B2 之后）
tools/release/manifest.sh build/sensen.aab > build/release-manifest-client.json
```
release 需要 upload keystore（发布链 B2，SSLAUNCH A7 到手后配），路径与口令只放本机 editor settings，不进仓库。

### 5.3 iOS

```
godot --headless --path . --export-debug iOS build/ios/sensen.ipa
xcodebuild -project build/ios/sensen.xcodeproj -scheme sensen -configuration Release -sdk iphoneos \
  -destination "generic/platform=iOS" DEVELOPMENT_TEAM=<team> -derivedDataPath build/ios/derived-cli archive \
  -archivePath build/ios/sensen.xcarchive
xcodebuild -exportArchive -archivePath build/ios/sensen.xcarchive -exportOptionsPlist tools/ios/ExportOptions.plist \
  -exportPath build/ios/export
tools/release/manifest.sh build/ios/export/sensen.ipa > build/release-manifest-client.json
```
`-derivedDataPath` 单独给一个目录，与 Xcode 图形界面共用会卡死。TestFlight 上传用 `xcrun altool` 或 Transporter（发布链 B4）。

### 5.4 服务端

合并到 `main` → `server.yml` 出镜像与清单 → `server/deploy/deploy.sh <digest>`（compose 拉指定 digest，跑 `smoke.sh`）。
数据库迁移在进程启动时自动跑（`migrate(pool)`），所以**先备份再部署**：`server/deploy/backup.sh`。

## 6. 回滚

| 出了什么事 | 怎么退 |
|---|---|
| 服务端新版本坏 | `deploy.sh <上一版 digest>`（清单里有）；迁移不可逆时用 `restore-drill.sh` 演练过的备份恢复，恢复前先停写 |
| TestFlight 包坏 | App Store Connect 里把该构建 **Expire**，测试员自动退回上一个可用构建；不要覆盖同号重传 |
| Play 内测包坏 | Play Console 暂停该轨道的发布（Halt rollout），再推上一版 AAB 作新版本号（Play 不允许版本号倒退，所以「退回」= 用旧代码重新出更大的号） |
| 客户端与服务端不兼容 | 服务端保持向后兼容一个版本：新字段可选、旧路由保留一个发布周期；`healthz.domain_version` 变了客户端弹强更提示（待做） |

每次回滚在 `CHANGELOG.md` 当前节加一条 `Reverted`，写明退到的 git sha / digest 与原因。

## 7. 责任与记录

- 出包人 = 打 tag 的人；tag 注释里写清单的 git sha 与构建号。
- 每个可分发包在 SSLAUNCH E12「投资人装机方案」下记一行：日期、tag、构建号、装到了哪几台设备。
- 提审用的正式包，额外在 SSLAUNCH E9 备注里贴 `Compliance` 一组的 changelog。
