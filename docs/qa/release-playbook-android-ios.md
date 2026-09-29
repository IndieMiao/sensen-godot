# Journey 发版手册：Android 独立 APK + iOS TestFlight

按 2026-09-29 0.17.9 实跑整理，每条命令都在本机（macOS，Godot 4.7.2，Xcode 26）验证过。
前提：代码已提交到发布分支；服务端已是目标版本（本手册只发客户端）。
产物目录约定：`output/<发布批次>/android/<版本代号>/`、`output/<发布批次>/ios/`（都在 .gitignore 里）。

## 0. 每次发版前先定下来的东西

| 项目 | 取值规则 | 0.17.9 实例 |
| --- | --- | --- |
| 版本号 | `0.MINOR.PATCH`，两端一致 | `0.17.9` |
| Android versionCode | `YYYYMMDDNN`，同一天递增，必须大于上一版 | `2026092906` |
| iOS build | 同一版本号内递增，一般从 1 起 | `1` |
| Android 版本代号 / releaseId | 一个词描述本次内容 | `roaming` / `roaming-20260929` |
| 源码提交 | `git rev-parse HEAD` | `f1e6be6` |
| 服务端 | `curl https://farm.sensenjoy.cn/preview/journey/v1/healthz` 的 `git_sha` | `accounts-google-20260929` |

## 1. Android：独立 APK

### 1.1 发布工程

`output/accounts-release-20260929/android/project/` 是一个**符号链接工程**：`assets/ modules/ scenes/ android/ icon.svg mapbox_token.txt` 都指向主仓库，只有 `project.godot` 和 `export_presets.cfg` 是自己的。
好处：主仓库改完代码，发布工程无需同步；发布工程的 preset 可以随便改版本号而不污染主仓库。
新建一个发布工程时照这个结构 `ln -s` 即可（`android/` 里已含 gradle 模板与 Google 登录插件，由 `tools/android/prepare_google_signin_plugin.py` 装好）。

### 1.2 改版本号

只改发布工程的 `export_presets.cfg`（四行）：

```
name="Android Roaming Landmarks Update"           # preset 名，导出命令要用
export_path="../roaming/sensen-journey-roaming-0.17.9.apk"
version/code=2026092906
version/name="0.17.9"
```

签名不用动：`package/signed=true` + 不填 keystore = Godot 用 `~/.android/debug.keystore`，
这就是 Journey 一直用的"正式"证书（SHA-256 `38771d94…8515673`），换了证书用户就不能原位升级。

### 1.3 导出

```bash
cd output/accounts-release-20260929/android
mkdir -p roaming
godot --headless --path project --import              > roaming/import.log 2>&1
godot --headless --path project \
  --export-debug "Android Roaming Landmarks Update" ../roaming/sensen-journey-roaming-0.17.9.apk \
                                                      > roaming/export.log 2>&1
```

- 用 `--export-debug`（不是 release）：debug 模板 + debug keystore，与历史版本证书一致。
- 日志最后一行 `cannot connect to daemon at tcp:5037` 是 Godot 想找 adb，无害。
- 约 2–3 分钟。

### 1.4 校验（发布前必做）

```bash
export JAVA_HOME="/Applications/Android Studio.app/Contents/jbr/Contents/Home"
BT=~/Library/Android/sdk/build-tools/37.0.0
$BT/apksigner verify --print-certs roaming/*.apk | grep 'SHA-256'   # 必须是 38771d94…
$BT/aapt dump badging roaming/*.apk | grep -o "versionCode='[^']*' versionName='[^']*'"
```

再用 Python `zipfile` 按 CRC 对比上一版 APK：正常只应变 `classes6.dex`、`assets/assets.sparsepck`、
改过的 `*.gdc` / json、`AndroidManifest.xml`（版本号）。多出别的文件要解释清楚。

### 1.5 发布到下载站（DMIT 美国 + 阿里云 OSS）

1. 复制上一版的 `publish-apk.mjs` 到本版目录，改头部常量：`folder`、`filename`、`releaseId`、
   `backendReleaseId`、manifest 里的 `version` / `versionCode` 与功能标记。`emulator_validation` /
   `physical_installation_verified` 按**实际做过的验证**填，不要抄上一版。
2. 写 `evidence.json`（sha256、bytes、certificate_sha256、version、versionCode、diff 列表）；脚本会断言它对得上 APK。
3. 先 `node .../publish-apk.mjs --check-only`（本地校验 + 服务端 healthz），再 `--publish`。
   脚本自己做：scp 到 DMIT 暂存目录 → `sha256sum -c` → `sudo install` 到 `/srv/sensen-downloads/farm/releases/<releaseId>-<sha前12>/` →
   `aliyun ossutil cp` 到 OSS → 两站全量下载比哈希 + Range 206 校验 + 公开 release.json / SHA256SUMS 逐字节比对。
4. 产出链接：`https://download-us.sensenjoy.cn:8443/farm/releases/<name>/<apk>`（主）、`https://oss.sensenjoy.cn/…`（备）。

需要：`ssh dmit-crs2ddcugh` 免密、`aliyun` CLI 已登录、Node。约 5 分钟。

## 2. iOS：TestFlight

### 2.1 发布工程

`build/ios-release/` 是 Godot 导出的 Xcode 工程 + 注入的原生桥，**跨版本复用，不要每次重导整个工程**：

- `sensen/MapUnderlay.swift`、`G3Spike.mm`（Mapbox 垫底地图 + UDP 桥）、`AppleSignIn.swift` + `sensen.entitlements`（Sign in with Apple）
- `sensen.xcodeproj` 里已挂 Mapbox SPM（mapbox-maps-ios 11.x）
- `ExportOptions-TestFlightUpload.plist`（app-store-connect / upload / automatic / XN4Z77ZX73）

第一次搭这个工程的方法见 `tools/ios/setup_ios_g3.sh`（导出 + 注入 MapUnderlay）→ `tools/ios/inject_apple_sign_in.py`；
之后每版只换游戏包和版本号。

### 2.2 重导游戏包（pck）

```bash
cp build/ios-release/sensen.pck output/<批次>/ios/sensen-<上一版>.pck    # 留底比对
godot --headless --path . --export-pack "iOS" build/ios-release/sensen.pck > output/<批次>/ios/export-pack.log 2>&1
```

用主工程的 iOS preset（`export_presets.cfg` 里的 include_filter 决定 json 等非资源文件是否进包）。
校验：用 Python 解析两份 pck 的文件表（格式版本 4：头部 `GDPC`，`dir_offset` 指向文件表，每项 path/offset/size/md5），
对比 md5 变化清单，应只有本次改动的文件 + `.godot/global_script_class_cache.cfg` / `uid_cache.bin`。

### 2.3 设版本号

```bash
python3 tools/ios/prepare_ios_signing.py --project build/ios-release/sensen.xcodeproj \
  --team XN4Z77ZX73 --bundle-id app.gensen.maps --version 0.17.9 --build 1 --display-name Journey
```

写入 pbxproj 的 `MARKETING_VERSION` / `CURRENT_PROJECT_VERSION`、自动签名、团队，并重写两份 ExportOptions。

### 2.4 归档

```bash
xcodebuild -project build/ios-release/sensen.xcodeproj -scheme sensen -configuration Release \
  -destination 'generic/platform=iOS' -archivePath output/<批次>/ios/sensen-0.17.9-1.xcarchive archive \
  DEVELOPMENT_TEAM=XN4Z77ZX73 CODE_SIGN_STYLE=Automatic > output/<批次>/ios/archive.log 2>&1
```

- 不加 `-allowProvisioningUpdates`：归档用本地已有的 Apple Development profile（Xcode GUI 建过一次），锁屏也能跑。
- Mapbox 从头编译时约 10 分钟；判断成败看日志里 `** ARCHIVE SUCCEEDED **`（管道会吞退出码）。
- 归档后核对：`Products/Applications/sensen.app/Info.plist` 的版本/build/bundle；`codesign -dv --entitlements -` 有
  `TeamIdentifier=XN4Z77ZX73` 与 `com.apple.developer.applesignin`；`sensen.app/sensen.pck` 哈希 = 2.2 导出的 pck。

### 2.5 上传 TestFlight（免 Xcode GUI、免解锁）

```bash
xcodebuild -exportArchive -archivePath output/<批次>/ios/sensen-0.17.9-1.xcarchive \
  -exportOptionsPlist build/ios-release/ExportOptions-TestFlightUpload.plist \
  -exportPath output/<批次>/ios/upload -allowProvisioningUpdates \
  -authenticationKeyPath ~/.appstoreconnect/private_keys/AuthKey_KQ7J86X34J.p8 \
  -authenticationKeyID KQ7J86X34J -authenticationKeyIssuerID fdc8f15b-4cb7-4ddb-a8ac-899e1e35ce4c \
  > output/<批次>/ios/upload.log 2>&1
```

- App Store Connect API 密钥（Key ID `KQ7J86X34J`，Issuer `fdc8f15b-4cb7-4ddb-a8ac-899e1e35ce4c`）是 Gensen 团队的，
  私钥只在本机 `~/.appstoreconnect/private_keys/`（600）。有它 CLI 就能云签发（Cloud Managed Apple Distribution）并上传，
  不会再报 `No Accounts`。
- 成功标志：日志 `EXPORT SUCCEEDED` / `Upload succeeded`；MapboxCommon / MapboxCoreMaps 两条缺 dSYM 警告是已知的。
- 上传后 Apple 处理 5–15 分钟；App `6815092667` 的内部群组 `GensenMap Internal` 自动获得新 build，测试员（Joey）
  会收到 TestFlight 通知，不用手动分发。可用 2.6 的脚本查处理状态。
- 若 CLI 仍失败，回退到 Xcode GUI Organizer，见 `docs/qa/ios-testflight-automation.md`。

### 2.6 查 TestFlight 处理状态（可选）

`/tmp/asc-venv`（pyjwt + cryptography）里用同一把 API 密钥签 ES256 JWT，
`GET https://api.appstoreconnect.apple.com/v1/builds?filter[app]=6815092667&sort=-uploadedDate&limit=3`，
看 `attributes.version` / `processingState`（`PROCESSING` → `VALID`）。脚本见 `tools/ios/asc_builds.py`。
注意：刚上传完的几分钟内列表里还没有新 build（Apple 先做包分析），不是上传失败；`Upload succeeded` 日志为准。

## 3. 发给 Joey

- **Slack**（DM `D0C1MHLA3GQ`）：`slack_get_file_upload_url`（文件名 + 精确字节数）→
  `curl -X POST "$URL" -H 'Content-Type: application/vnd.android.package-archive' --data-binary @apk`（URL 大小写敏感，用变量传）→
  `slack_complete_file_upload(channel_id=D0C1MHLA3GQ, initial_comment=更新说明)`。iOS 只需说明 TestFlight 版本号。
- **飞书**：`lark-cli drive +upload --as user --file <cwd 相对路径>/apk --json` → 拿 `file_token` →
  `lark-cli drive +member-add --as user --token <file_token> --type file --member-type openid --member-id ou_b06d5126517132988d3f21880509ecc6 --perm view --yes`
  → `lark-cli im +messages-send --as user --chat-id oc_5c5d2f0dc83fcff48ac8d402d7d94ea1 --text "…"`。
  `--file` 只收 cwd 相对路径。
- 消息模板（沿用 0.17.8）：版本号 + 本次更新要点（用户视角）+ 美国下载链接 + OSS 备用链接；iOS 一句"TestFlight 已上传 0.17.9 (1)，收到通知后更新"。

## 4. 收尾

- 在当次 QA 记录（`docs/qa/<批次>.md`）写：版本、versionCode/build、SHA-256、下载链接、源码提交、验证到哪一步（模拟器/真机/未验）。
- `evidence.json` 与 `release.json` 必须如实反映验证情况；0.17.8 曾把没做的模拟器验证写成 true，后来只能出更正。
- 主仓库不需要提交任何发布产物；只提交文档。
