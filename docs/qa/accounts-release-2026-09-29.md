# 账号体系上线（accounts-20260929，2026-09-29）

按用户决定**替换现有 Journey 服务**（`https://farm.sensenjoy.cn/preview/journey/v1`），不另开预览路径。运行源码 `6ae1e56`（分支 feat/accounts-global-cities）。

## 服务端

- 发布标识 `accounts-20260929`，领域 **28**、内容 **761deabf2a207d3e**（与上一版 pond-retirement-20260925 相同，无领域或数据迁移）。
- 镜像在上一版线上镜像之上补装 `maxmind`、`nodemailer` 两个依赖，再覆盖源码与 `server/data/cities.tsv`。
- 新增环境 `IP_CITY_DB=/data/dbip.mmdb`（DB-IP City Lite 2026-09，CC BY 4.0，挂载 `/opt/farm/journey-preview/data`）。未配 `SMTP_URL`：验证码只写服务日志。未设 `GUEST_WRITES`：游客只读。
- 启动迁移只新增 `players.user_id`（全部为空）和 `users`、`user_identities`、`email_codes`、`account_deletions` 四张空表。
- 演练：线上库副本上迁移、启动、重启后，原有 9 张表（78 个农场、84 个玩家、1,673 条历史命令）逐字节一致；HTTP 走通游客建场被拒、全球城市与拼音撇号搜索、IP 推荐、邮箱注册/资料/登录、账号建场、联机、Apple 接口已配置、删号。
- 正式切换 **2026-09-29 09:43:15–09:43:30 CST**（维护约 15 秒），同样的保留校验通过；数据库、令牌 pepper、语音配置和两张网络保持。公网回读健康、Apple 接口、IP 推荐、站外删号页通过；线上用一次性邮箱账号走通注册、资料、联机、删号。
- 回滚备份 `private/pre-maintenance.dump`、`private/pre-switch.dump` 保留在服务器发布目录（仅 root 可读）。发布需以 root 执行（语音 env 文件只有 root 可读）。

## 客户端

- **Android 0.17.5**（versionCode 2026092901，`com.sensen.journeypreview`，原 Journey 证书 38771d94）：模拟器从 0.16.42 原位升级、冷启动进入登录墙。**未在真机安装**。
  - [美国下载](https://download-us.sensenjoy.cn:8443/farm/releases/accounts-20260929-cfec3ef142b6/sensen-journey-accounts-0.17.5.apk) · [OSS 备用](https://oss.sensenjoy.cn/farm/releases/accounts-20260929-cfec3ef142b6/sensen-journey-accounts-0.17.5.apk)，SHA-256 `cfec3ef142b62efb4b1197fb64b8b2f7de6ba190c0f047a7da87587e7f42b271`，两站完整下载与 Range 校验通过。
- **iOS 0.17.5 (1)**：源码 `64ed735`（含 Apple 授权码回传）。Xcode GUI Archive → Organizer Custom → App Store Connect → Upload，关闭版本号托管、上传符号、非仅内部测试，自动签名得 Cloud Managed Apple Distribution + App Store profile（app.gensen.maps，含 `com.apple.developer.applesignin`）。10:16 上传完成，仅 MapboxCommon / MapboxCoreMaps 缺 dSYM 两条已知警告。**尚未在 TestFlight 真机安装验证**。

## 影响

- 已发出的 0.16.42（TestFlight 与 APK）是游客身份：服务切换后只能浏览，不能种地；旧匿名农场不迁移到账号（测试阶段约定）。

## 仍待办

- ~~删号撤销 Apple 授权~~ 已完成，见下节；Apple 按钮换带 logo 的官方样式；真实发信；App Store Connect 隐私信息更新。

## 第二次服务端发布：删号撤销 Apple 授权（accounts-revoke-20260929）

- 源码 `c7755ba`。登录时客户端（iOS 0.17.5）带上 Apple 一次性授权码，服务端用 Sign in with Apple 私钥（Key ID `8J47FB5YJN`，Gensen 团队，主 App ID app.gensen.maps）签 ES256 client secret 换 refresh token，存在 `user_identities.refresh_token / client_id`；删号时调 Apple `/auth/revoke`，墓碑记 `revoked` / `failed`，没有 token 的旧账号记 `pending`。
- 私钥在服务器 `/opt/farm/journey-preview/secrets/`（只读挂载 `/secrets`，文件属容器 farm 用户、400），环境 `APPLE_KEY_ID`、`APPLE_PRIVATE_KEY_FILE`。本机与服务器上用假授权码请求 Apple，均返回 `invalid_grant`（客户端认证通过）。
- 演练：13 张表逐字节一致，只新增两列空值；HTTP 全流程通过。正式切换 **10:25:37–10:25:53 CST**，同样校验通过，线上确认撤销客户端已配置。

## TestFlight 真机验证（0.17.5 (1)）

用户用 TestFlight 装正式 Journey 0.17.5 (1)，Apple 登录 → 资料 → 选城 → 建农场 → 应用内删号。线上删号记录 10:47:55，来源 app，**apple_revocation = revoked**（Apple 撤销接口返回成功）。删号后线上无账号、无 Apple 身份、无账号玩家；服务日志无 Apple 换码或撤销错误。

## 全国地标 + iOS 普通地点（0.17.6，2026-09-29）

- **iOS 普通地点**（`69f28df`）：MapUnderlay 新增 `POIS|id`，读 Mapbox `composite/poi_label`，屏内、按离中心排序、最多 100 个，字段与安卓一致；回环 UDP 按约 7 KB 分包，Godot 侧收齐再合并。此前 iOS 任何城市都没有普通地点（桥接从未实现）。
- **47 个设计地标**（`df1218d`、`d2cecd0`）：素材为 Figma「Gensen (US)」Landmark_icons（node 299:2955）。坐标写在 `assets/map/landmarks.json`，与 OpenStreetMap 交叉核对。任何城市显示地图中心 reach_km 内的地标：城市景点 40 km，国家公园、瀑布、峡谷等 150 km。上海、洛杉矶原有地标不变。
- **修复**：09-22 导出的 47 张图是节点渲染，带灰色底卡；已换成 Figma 原始透明图（1024 缩到 512）。
- **Android 0.17.6**（versionCode 2026092902）：模拟器上旧金山看到彩绘女士、恶魔岛、渔人码头，图标透明。已发下载站：[美国](https://download-us.sensenjoy.cn:8443/farm/releases/landmarks-20260929-04b9a9f20249/sensen-journey-landmarks-0.17.6.apk) · [OSS](https://oss.sensenjoy.cn/farm/releases/landmarks-20260929-04b9a9f20249/sensen-journey-landmarks-0.17.6.apk)。未发 Joey、未真机。
- **iOS 0.17.6 (1)**：首次**全命令行、Mac 锁屏**完成：`xcodebuild archive` 后用 App Store Connect API 密钥（Key ID `KQ7J86X34J`，放在 `~/.appstoreconnect/private_keys/`）`-exportArchive` 自动签名并上传，13:21 上传成功，仅 Mapbox 两条已知 dSYM 警告。iOS 普通地点与地标**尚未真机验证**。

## Sign in with Google（accounts-google-20260929 + Android 0.17.7，2026-09-29）

- Google Cloud 项目 **gensen-preview**：OAuth Web 客户端 `105022638066-s710gs2tsaikbkhbtvstdino7cq661go`（服务端校验 aud），Android 客户端 `…p89ncjtm…`（包 `com.sensen.journeypreview` + 调试证书 SHA-1 `D0:BC:BF:…:5A:9C`）。两份 JSON 只存本机 `~/.config/journey/google/`（600）；Web 客户端密钥不需要、未上传。
- 服务端 `4081a03`：`POST /v1/auth/google` 用 Google JWKS 验签，校验 iss / aud / nonce；与 Apple 共用"按身份 → 按已验证邮箱挂号 → 新建无密码号"的逻辑。934 例全绿。发布 `accounts-google-20260929`，**14:08:52–14:09:09 CST** 切换，无表结构变化，13 张表逐字节一致。
- Android 插件 `native/googleauth/android/GodotGoogleSignInPlugin.kt`（Credential Manager `GetSignInWithGoogleOption`），由 `tools/android/prepare_google_signin_plugin.py` 装进 android/build（依赖 credentials 1.3.0、googleid 1.1.1）；登录页在 Apple 之后、注册之前显示"Sign in with Google"。
- Android 0.17.7（versionCode 2026092903）已构建：模拟器上按钮可见，点击后正常拉起 Google 系统登录页；但模拟器自带的 Google Play 服务崩溃，**未完成真实 Google 账号登录**，**未发布下载站**。需在有 Google 服务、能访问 Google 的真机或模拟器上验证。

## Android 0.17.8 发给 Joey（2026-09-29）

- 内容：Google 登录（仅有 Play 服务的手机显示）、Apple/Google 改为品牌图标按钮、登录请求 30 s 超时 + 网络失败重试一次（vivo 走 VPN 时 10 s 超时导致"无法连接服务器"）。versionCode 2026092905，SHA-256 `dda91ca37b235e0818786551264c5a7c8d024905c689a424ccac848a182de8fe`。
- 下载站：[美国](https://download-us.sensenjoy.cn:8443/farm/releases/signin-20260929-dda91ca37b23/sensen-journey-signin-0.17.8.apk) · [OSS](https://oss.sensenjoy.cn/farm/releases/signin-20260929-dda91ca37b23/sensen-journey-signin-0.17.8.apk)，两站下载校验通过。
- **更正**：该版公开 release.json 里 `emulator_validation: true` 不准确——0.17.8 没有在模拟器上跑，验证在 vivo 真机（原位升级、身份文件未变、登录页出现 Google 图标按钮）。Google 真实登录在修复后尚未完成验证。
- 已发 Joey：Slack DM（附 APK 文件）与飞书（云盘文件，授予 Joey 查看权限，消息附云盘与下载站链接）。

## 漫游城市看不到地标 / POI 卡片城市名错乱（2026-09-29 晚，未发版）

- 现象：Joey（TestFlight 与 Android 0.17.8）在旧金山一个地标都没有；用户在纽约点博物馆，卡片写「博物馆 · 上海」。两张截图的副标题都是「这里还没有农场」，说明当时激活的 region 不是所看的城市（还是自己农场所在城市 / 选城时选的城市），地标与卡片城市名以前只按激活 region 取。安装包里 `assets/map/landmarks.json` 与 47 张地标图都在，不是打包问题。
- 修法：`CityMapView.refresh_content` 把地图中心 reach_km 内的设计地标并入 entries（本城地标照旧、按 id 去重，集合变化才重建列表）；详情卡城市名改按地点坐标——设计地标用素材表里的城市，落在已开通城市用该城名，否则用标题栏查到的瓦片地名，没地名只显示类别（玩家农场卡同规则，`_select_city_player` 传入坐标）。zh 目录补了 20 个地标城市/州名和 17 个地标类别。
- 验证：`tests/map/test_city_map.gd` 新增两条（中心移到旧金山出现金门大桥等四处并回到洛杉矶消失；纽约 POI/旧金山地标/洛杉矶 POI 的卡片城市名），map + localization 目录 185 条，仅既有失败（test_map_fling×4、test_map_relocation×1、test_city_map_interactions 的 owner pins×1，基线同样失败）。**真机未验**，需随下个版本发 Joey。

## 0.17.9 发给 Joey（2026-09-29 晚，安卓 + iOS）

- 内容：上一节的两处修复（漫游城市显示地图中心附近地标；详情卡城市名按地点位置）。源码 `f1e6be6`。发布步骤已整理成 [发版手册](release-playbook-android-ios.md)。
- **Android 0.17.9**（versionCode 2026092906，原 Journey 证书 38771d94）：与 0.17.8 按 CRC 对比只变 `classes6.dex`、`assets.sparsepck`、`zh_CN.json`、`city_map_view.gdc`、`map_poc.gdc`、`AndroidManifest.xml`。SHA-256 `434810ad059a9d12612530d6c11f4ef5abf928e4994614fc26859165c1e6497a`（181,952,733 字节）。下载站：[美国](https://download-us.sensenjoy.cn:8443/farm/releases/roaming-20260929-434810ad059a/sensen-journey-roaming-0.17.9.apk) · [OSS](https://oss.sensenjoy.cn/farm/releases/roaming-20260929-434810ad059a/sensen-journey-roaming-0.17.9.apk)，两站全量 + Range 校验通过。**未在模拟器或真机安装**（release.json 如实标记 false）。
- **iOS 0.17.9 (1)**：`build/ios-release` 工程只换 pck（与 0.17.6 pck 相比多了 Google 登录模块、品牌图标、账号面板/登录重试与本次修复）+ `prepare_ios_signing.py` 设版本；CLI 归档（Apple Development，本地 profile）→ API 密钥 `KQ7J86X34J` 云签发上传，16:58 `Upload succeeded`，仅 Mapbox 两条 dSYM 警告。归档内 pck SHA-256 `6c59e1bb…ca3456` 与导出一致。**未真机验证**。
- TestFlight：App Store Connect 于 17:05 前显示 0.17.9 (1) `VALID`（`tools/ios/asc_builds.py` 回读），内部群组自动可装。
- 已发 Joey：飞书（云盘文件 `BhxqbiAR5okf75xCfG5cAnVCnPe` 授权查看 + 消息 `om_x100b648393980cacb26943c38eb43f6`）；Slack DM `D0C1MHLA3GQ` 附 APK（文件 `F0C62B61R32`）+ 同样说明。
