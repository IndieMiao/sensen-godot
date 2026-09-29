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

- 删号撤销 Apple 授权：客户端 0.17.5 已回传授权码，服务端代码 `64ed735` 已写好并测试，**等 .p8（Key ID 8J47FB5YJN）配到服务器后再发一次服务端**；Apple 按钮换带 logo 的官方样式；真实发信；App Store Connect 隐私信息更新。
