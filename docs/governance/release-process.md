# 发版流程（sensen-godot / Gensen）

> 2026-11-20 切换导出的历史记录，不是新的批准或现行执行授权。〔…〕标示隐去的环境或身份信息；原件定位见[迁入说明](README.md)。

导出时间：2026-11-20 16:5x CST（奕星只读子代理整理）。**凭据只写存放位置和用途，不含任何内容。**

来源（只读）：PM 手册 3.5（发版）、3.14（每日版本）、4 补（11-05 / 11-09 / 11-10）；共享记忆 journey-apk-release-flow、ios-device-build-workflow、ios-sim-coldstart-check、feedback-ios-release-vs-android-debug、p0-demo-release-log、feedback-release-log-*、feedback-android-apk-via-feishu、project-mengtian-no-oss-test-apk-after-store、mengtian-handoff-2026-11-14（含到 11-19 的续节）；仓库 `tools/p0/build_demo_apk.sh`、`tools/p0/build_play_aab.sh` 与 `tools/p0/README.md`、`server/deploy/p0/README.md`（origin/farm-dev `6ed012f9`）；`pm/demo-daily/auth-daily.md`；`pm/plans/store-readiness/store-submission-blockers-1115.md`（11-18 更新版）。

## 0. 现状（切换时）

- 最后一个公开安卓版本 **0.3.10**（2026111301，11-13，OSS oss2）；iOS 最后一版 0.3.9 build 1（11-12，外部审核 11-13 通过）。
- **0.3.11 常规发布暂停**（用户 11-13「0.3.11 先暂停」）；11-15 起所有方案暂停、优先两店提审；11-17 起只做「上架提交」和「地理生成农场 SGODOT-499」。
- 第一个商店包 r1：tag `p0-play-0.3.11-r1`（farm-dev `4ff750733`），0.3.11 / 2026111401，AAB 在 `〔私有路径〕`，**等用户在 Play Console 手传内部测试（G1）**。
- 提审包 r2 还没出：要先过两道硬闸门（见第 3 节）。iOS 语音真机测试定在 **11-25 10:00**，测完再定首版带不带 iOS 语音。
- 499 动态农场演示包（GeoFarm r1–r4、3D 1902–1904）是独立 applicationId 的演示 APK，不进 OSS 正式渠道、不进 release-log（奕星判定），服务在 〔机器名〕 用 Quick Tunnel，保留到用户验收结束。

## 1. 角色

| 角色 | 谁 | 做什么 |
|---|---|---|
| 发版总控 | 奕星 | 定冻结、广播、合 PR、出发布授权（写授权文件）、对外发送、发版后改卡表报批 |
| 出包 / 冒烟 | 李元芳（10-27 起日更安卓出包 + 冒烟）、蒙恬（发布负责人：iOS、商店包、OSS、服务端复演、release-log） | 见下各步 |
| 审核 | 周瑜（主力）、苏烈（蒙恬的 PR） | 代码 / release-log PR |
| 正式服部署执行 | 迁移方运维会话（美西实例由其维护）；蒙恬准备复演和清单 | 部署前后报奕星 |
| 批准 | **用户本人** | 见第 4 节「需要人工」 |

## 2. 安卓

### 2A. 内部演示 APK（OSS 渠道，`com.sensen.p0demo`，上架前的日常发版）

| # | 步骤 | 自动 / 人工 |
|---|---|---|
| 1 | **冻结**：前一晚 21:00 左右奕星报「明天候选 + 待批 q 行」；当天 09:30 冻结（11-02 起改 A′：只放线上修复和小功能，没改动就不出包）。最后一个 PR 合完即冻结，冻结头（完整 SHA）发给出包人和测试员；冻结后合入的算下一版。客户端用 tag 钉住（如 `p0-v7-0.3.10-client`）。 | 人工（奕星） |
| 2 | 找大乔登记 Mac 重活窗口（Q 窗）；确认用户手机没插 USB（`system_profiler SPUSBDataType`）。 | 人工（出包人 → 大乔） |
| 3 | 冻结头全量测试：p0 + ui_kit 必须全过，其余套件按报告放行（headless 计时不稳的测试用窗口模式复跑）。 | 自动（脚本），人工判读（出包人；有疑问交周瑜） |
| 4 | 构建前置：`android/` 必须配好（Mapbox、LiveKit、插件、`mapbox_token.txt`），`android/build` 删过要重跑 `tools/android/setup_android_build.sh` 和 `tools/android/prepare_*_plugin.py`（google_signin / notify / voice / webview 四个）。缺了地图全黑（打包脚本 #178 起会拦）。 | 自动（脚本），人工确认 |
| 5 | 出包：`tools/p0/build_demo_apk.sh --server 〔服务地址已隐去〕 [--key-file …] --code YYYYMMDDNN --name x.y.z`（导出预设 **Android P0**，不是 Journey 的 Android 预设；versionCode `YYYYMMDDNN`，同日第二个包 `…02`，`…00` 只给演练；versionName 必须 `x.y.z`）。脚本用私有 adb 端口（默认 5071），`--export-debug`，证书是 debug keystore（SHA-256 前缀 `38771d94…`，所有正式包同一张，可覆盖安装）。 | 自动（脚本）；人工启动（出包人） |
| 6 | **Release 引擎冷启动检查**（11-05 起每次必做）：`〔私有路径〕` 用 `--export-release` 出预览包（`Android P0 Preview`，连预览服），在模拟器上冷启动两次。原因：安卓正式包是 debug 引擎，null 调用只报错；iOS 是 Release 引擎会直接崩。 | 自动 + 人工看结果（李元芳 / 蒙恬） |
| 7 | 模拟器冒烟：覆盖安装、旧客户端连新服、当版内容逐条看；连 〔机器名〕 上与正式服同镜像的空数据服。Mac 只用李元芳那台模拟器，第二台去 〔机器名〕。 | 人工（李元芳） |
| 8 | 服务端如有改动：〔机器名〕（〔地址〕）复演——数据 B 规定正式数据不落国内，复演改在美西隔离容器（`pm/plans/store-readiness/us-rehearsal-howto-20261112.md`）；含回滚演练。**改存档格式 / 需要迁移 / 提高最低版本必须先报用户批**；只加可选字段、SAVE_VERSION 不变的不算，但要在 q 行写明。客户端包进 OSS 前，不部署会让旧客户端出问题的服务端改动。 | 人工（蒙恬复演；奕星报批） |
| 9 | 部署美西：`server/deploy/p0/deploy-hk.sh --target us --expect-config sha256:<完整摘要> transfer <sha>` → `up <sha>` → `verify-internal` → `smoke`；回退同脚本 `up <旧 sha>`。香港已冻结（写入步骤默认拒绝）。 | 人工启动（迁移方运维执行，前后报奕星）；脚本自动校验 |
| 10 | 上 OSS：`tools/p0/publish_demo_apk.mjs`（只收 `com.sensen.p0demo`；拒绝 `…00` 演练号和带 dev cleartext 的包），传到不可变目录 `〔服务地址已隐去〕<YYYYMMDD>-<sha12>/`，同目录有 `release.json`、`SHA256SUMS`；脚本自带整包回读、Range 206、清单核对（回读超时可改核 OSS 的 CRC-64 + 清单逐字节一致）。0.2.14 及以前在 〔服务地址〕（原样保留）。 | 自动（脚本）；**需用户授权**——日更已有常驻授权（`pm/demo-daily/auth-daily.md`，用户 10-26 回「授权 ok」） |
| 11 | 提最低版本（如需要）：admin 接口设 min-version 和 update_url（指向 oss2 上每版一个新路径的说明页）。 | **需用户先批**；人工（蒙恬 / 运维） |
| 12 | 发用户：10-15 起不再 USB 装机。APK 链接 + SHA-256 + versionCode 发用户飞书 **bot 单聊**（>100 MB 走云盘链接或 OSS 链接）；用户自己装、自己拉起。 | 人工（奕星 / 小乔代发），日更在常驻授权内 |
| 13 | 版本更新 log：英文更新说明 + 安卓链接发飞书群「版本更新Log」，**`--as bot`**（11-04 起；不再私信 Joey；Slack 只在用户要求时发）；群说明逐句对 PR 改动文件。 | 人工（奕星 / 出包人），群发要用户授权或在当版授权内 |
| 14 | release-log：仓库 `docs/release/release-log.md` 加一节（蒙恬写，走 PR，周瑜或苏烈审，奕星合）；**不写人名、不写发送记录**；转好的 HTML 发用户 bot 单聊（Plane 页 10-13 起不再更新）。 | 人工（蒙恬 → 审 → 奕星） |
| 15 | 发版后：出「卡号 ｜ 当前状态 ｜ 建议状态 ｜ 理由」表给用户批，批了由子代理批量改卡。 | 人工（奕星，需用户批） |
| 热修 | `release/p0-<ver>-h1` = 冻结头 + cherry-pick 修复；versionName 不变、versionCode +1；服务端不动；同样要用户批 OSS。 | 人工 |

- **上架后（Play 正式上线那天起）不再自发 OSS 测试包**，统一走 Play 测试轨道 / 正式轨道（用户 11-12 上架二批 #8）。切换那天要和奕星确认群说明模板、gate 的 update_url 按渠道下发。
- 改光影 / 场景 / 3D 的 PR 要附同机位改前 / 改后帧率（模拟器相对差，发版前补一组真机）。

### 2B. Google Play 商店包（AAB，`app.gensen.maps`）

| # | 步骤 | 自动 / 人工 |
|---|---|---|
| 1 | 前置闸门（出**提审**包前两条都要满足，之前的商店包只进内部测试）：① 账号系统正式部署完成、q(320) 牌室每日输额上限在正式服生效（S4 用户批部署之后）；② `https://gensen.app/terms` 返回 200 → 哪吒把 `TERMS_LIVE` 改 true 的 PR 合进 farm-dev。另需账号整合分支 PR-A 合主干、网页删号页上线等。 | 人工（奕星核；用户批 S4） |
| 2 | 找大乔登记窗口。 | 人工 |
| 3 | 出包：`tools/p0/build_play_aab.sh --server <正式服地址> --name 0.3.11 --revision r2 --code <YYYYMMDDNN，必须 > 2026111401 且递增>`（#1076 已合）。导出 **Android Play** 预设，自检：签名证书指纹（checker 内固定）、权限、无 AD_ID、无 cleartext、无 QA 残留、16 KB 对齐、bundletool 校验；通过后原子拷到 `〔私有路径〕<ver>-play-<rev>.aab`（不覆盖旧 revision）。**脚本从不上传、不装机、不动服务器。** versionCode 台账 `output/p0-play/versions.json`（失败的导出也占号）。 | 自动（脚本）；人工启动（蒙恬） |
| 4 | 同一提交另出一个冒烟 APK（`P0_PLAY_FORMAT=apk`，地址烤隧道地址，因 release 包写不了 `p0_server.txt`）；给用户的 AAB 烤正式服地址。两个包同提交同号。 | 自动 + 人工（蒙恬） |
| 5 | 商店包冒烟（共两次；第 1 次 11-14 已过，在 16 KB 模拟器上）；第 2 次＝提审前终检（审核测试码 + 真登录各进一次、牌室加倍分牌、矿和明信片、屏蔽举报删号、两处条款链接实点、尽量用从内部测试装的分发版）。 | 人工（李元芳） |
| 6 | **上传 AAB：用户本人在 Play Console 网页手传**（新应用第一个包只能手传；Play 服务账号密钥被公司 Google 组织策略拦，提审前每个包都手传）。G1 → G2 回「应用签名证书 SHA-1」→ G3 建 Play 签名用的 Google 登录客户端。 | **需人工（用户）** |
| 7 | 填表 / 送审：Data safety、IARC（模拟赌博 Yes、追问全 No）、目标受众只选 18+、App access 填审核测试码、国家 / 地区（首批不上欧盟含法国、韩国不上），截图发回团队逐行核对后用户点送审。 | **需人工（用户）**；团队给答案（`pm/legal/store-2026-11/store-forms-1113.md`） |

## 3. iOS（TestFlight / App Store，Bundle `app.gensen.maps`，团队 XN4Z77ZX73）

| # | 步骤 | 自动 / 人工 |
|---|---|---|
| 1 | 同一冻结头、同一版本号；找大乔登记（iOS 出包与李元芳模拟器 / 亚瑟 iOS 模拟器错开）。 | 人工 |
| 2 | **出包前 Release 冷启动实测**（11-09 起）：`〔私有路径〕 pack/sign` → `xcodebuild … -configuration Release -destination "generic/platform=iOS Simulator" ARCHS=x86_64 … CODE_SIGNING_ALLOWED=NO build` → iOS **18.6** 模拟器（新建设备，每包一台）冷启动两次能进农场；录屏写 `/tmp`。storyboard 启动层模拟器看不到，要用户 iPhone 看。新场景上 iOS 前要有人在 iPhone 真机进一次。 | 自动（脚本）+ 人工判读（蒙恬 / 亚瑟） |
| 3 | 出包上传：`〔私有路径〕`（pack → sign → archive → upload）。archive 用打包专用钥匙串里的 Apple Development 身份；upload 用 App Store Connect API 密钥 + `-allowProvisioningUpdates`（Distribution 证书由 Apple 云端管理，本机没有）。 | 自动（脚本）；人工启动（蒙恬） |
| 4 | 查处理状态：`tools/ios/asc_builds.py` / `〔私有路径〕`（VALID 后进内部组）。崩溃日志可从 ASC betaFeedbackCrashSubmissions 取（`asc_get.py`）。 | 自动 |
| 5 | 内部组：日更版直接进 TestFlight 内部组（11-05～08 常驻，见 auth-daily）。外部组 `Gensen-ext-test`：用户 11-04「每周都加外部测试」——每周三一版由蒙恬加外部组并提交 Beta App Review，What to Test 先给奕星过目。 | 人工（蒙恬；外部组按用户 11-04 授权） |
| 6 | 上传那一刻告诉奕星，奕星请用户留意 App Store Connect 邮件（A4）；TestFlight 真机验证用用户本人 iPhone（A5）。 | **需人工（用户）** |
| 7 | 提审：用户在 App Store Connect 选 build、填隐私标签 / 年龄分级 18+（模拟赌博 Frequent）/ 审核信息（Sign-in required + 审核测试码）、出口加密问卷（S8：首批无需法国声明，11-25 语音取舍后做全包问卷再定 `ITSAppUsesNonExemptEncryption`，每个 TestFlight 构建也要申报）、ASC 交易者状态声明，选「手动发布」后送审。 | **需人工（用户）**；团队给答案 |

- 带新 entitlement（如 Sign in with Apple）的包、新建 provisioning profile 只能在 **Xcode GUI** 里签（CLI 报 No Accounts，GUI 登录有 2FA）。
- 证书换新 / 到期（现用身份 2027-09-24 到期）要重做钥匙串导入：必须在 Mac 自带 Terminal.app 里做（herdr / tmux / Claude 会话弹不出图形密码框），用户在屏幕上输登录密码。步骤见 `pm/ios-tf-356/build-keychain-plan.md`。

## 4. 需要人工的事（汇总）

| 事项 | 谁 |
|---|---|
| 日更 OSS 上传 + 发用户本人飞书 | 常驻授权（用户 10-26「授权 ok」），无需逐次问 |
| 发 Joey / 群「版本更新Log」以外的对外发送 | 用户每次明确要求 |
| 改存档格式、迁移、提高最低版本、部署会影响玩家的服务端 | 用户先批 |
| 手势 / 点击判定类改动合并 | 用户批（附短视频） |
| 未批 q 行对应的规则 | 不许进包 |
| Play 上传 AAB、填表、送审；App Store 选 build、填表、送审 | 用户本人 |
| 账号系统正式部署（S4）、四把钥匙保管安排（S1） | 用户本人 |
| vivo / iPhone 真机安装确认、TestFlight 真机 | 用户本人 |
| 证书 / 钥匙串重做时输登录密码；Xcode GUI 登录 | 用户本人 |

## 5. 凭据存放位置（只写位置，不含内容；均不打印、不复制、不发聊天）

| 凭据 | 位置 | 用途 / 备注 |
|---|---|---|
| Android debug keystore | Android 构建账号的调试签名库 | OSS / 预览 / dev 包签名；Google 登录客户端与它的证书绑定，换机必须恢复同一份 |
| Play 上传密钥 | 商店上传专用签名库（PKCS12） | Play AAB 上传签名（应用签名密钥由 Google 托管） |
| Play 上传密钥口令 | 登录钥匙串条目，服务名 `sensen.android.play-upload-keystore` | 脚本运行时读取；存放说明 `pm/plans/store-readiness/play-upload-key.md`；**用户定备份方式（S1）前不做任何副本** |
| iOS 打包专用钥匙串 | 发布账号的专用构建钥匙串 | 只放 Gensen 团队那张 Apple Development 身份；no-timeout 不自动上锁 |
| 打包钥匙串口令 | 发布账号受限的钥匙串解锁文件（0600） | `build_p0_ios.sh` archive 前解锁用；原搜索列表备份 `〔私有路径〕` |
| App Store Connect API 私钥 | 发布账号受限的 App Store Connect 私钥目录（.p8，0600） | `xcodebuild -exportArchive` 上传、`asc_*.py` 查询 |
| 客户端内置游戏口令（P0_KEY） | 环境变量 `P0_KEY` 或 `--key-file`（默认 worktree 下 `output/p0-deploy/key`） | 打进客户端包，读回时比对不打印；不是签名口令 |
| 正式服口令 / 配置 | 服务器上 `/opt/farm/p0/.env.p0`、`/opt/farm/p0/.env.backup`（600）；美西由迁移方维护的 `compose.production.json`（600） | 不入库 |
| 美西部署登录 | 迁移方的 ssh_config（`P0_US_SSH_CONFIG` / `P0_US_HOST`） | 部署脚本 `--target us` 使用 |
| Mapbox token | 构建时放进 Android 构建资产（`mapbox_token.txt`，由 setup / prepare 脚本配置） | 缺了地图全黑；不打印 |
| age 私钥、P0_ACCOUNTS_KEY | 待用户 S1 定保管方案（P0_ACCOUNTS_KEY 定之前不生成，上线后不能换） | 服务端备份解密 / 账号字段加密 |
| 飞书 CLI 身份 | `lark-cli --profile gensen`（bot 单聊发材料用 `--as bot`） | 报批、发包通知、release-log 文件 |

## 6. 常见坑

- 导出前 `android/` 没配好 → 地图全黑；测试员误用 Journey 预设曾造成「Licenses 空白」误报。
- `xcodebuild … | tail` 会吞退出码，看输出里有没有 `BUILD FAILED`。
- Godot `--export` 的 `[ DONE ] export` 带 ANSI 颜色码，grep 用 `DONE.*export`。
- 国行 iPhone 新装 App 首次会问「无线数据」，错过就一直离线：设置 → App → 无线数据选「WLAN 与蜂窝网络」。
- zsh 里别用 `path` 当变量名（会覆盖 PATH）。
- 云盘大包（>300 MB）回读失败一次即按上传大小一致收（用户 11-18 定）。
