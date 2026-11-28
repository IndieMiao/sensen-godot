# 动态农场隐私政策（整份，中英）

SEN-C-242。适用动态农场 App（`com.gensen.mapfarm`，连 `https://farm.sensenjoy.cn/dynamicfarm/v1`）。玩家可见文本待 PM 按 SEN-C-45 定稿，再交所有者本人确认；合入不等于发布，页面上线另交所有者批准发布。

“产品分析”一节是 SEN-C-204 已定稿、所有者确认（Q-356）的原文，逐字并入，不改（`docs/legal/dynamic-farm-privacy-analytics.md`）。

## 页面托管方案

- 地址：`https://gensen.app/privacy-dynamic-farm`。和 Gensen App 的两份政策（`/privacy`、`/privacy-android`）放在同一个站点，同一个开发者名下；Play Console 的“隐私权政策网址”也填这个地址。
- 不放正式服域名（`farm.sensenjoy.cn`）：正式服合并后自动部署，放在服务端路由里等于合并即上线，越过“上线另行批准”。
- 本文件是网页的源文本。发布时由有 gensen.app 权限的人把下面的英文（和中文，如要放）做成页面；“Last updated”写成实际上线日期。
- App 入口：设置 › Legal 第一行 `Privacy Policy ›`，在系统浏览器里打开上面的地址（`scenes/dynamic_farm/parcel_profile.gd` 的 `PRIVACY_URL`）。页面上线前 `PRIVACY_LIVE` 为 `false`，这一行不显示，免得玩家点开 404；随页面上线一起改成 `true`（和 Gensen App 的 `P0Legal.PRIVACY_LIVE` 同一做法）。

## 英文

# Dynamic Farm Privacy Policy

Last updated: [date of publication]

This policy covers the Dynamic Farm app and its game service. "We" means Gensen, the maker of Dynamic Farm.

## What we collect

**Your account**

- Your email address and password, if you sign up with email. We store your password only in a form that can't be turned back into it.
- If you sign in with Google: your Google account ID, your email address, and your first name as your starting nickname.
- Your nickname, and your gender and birthday if you add them. We don't save a birthday if you're under 13.

**Your farm**

- The plot you claim on the map and where it is.
- What's on your farm, such as crops, animals, buildings, items and coins.
- When you created your account, claimed your plot and last played.

**Sign-in and security**

- Your sign-ins on each phone and the codes we email you.
- When you sign in, we use your IP address to stop repeated attempts. We keep only a coded form of the networks you've signed in from, not your IP address.

Your character's look is saved only on your phone. The game doesn't use your phone's location.

## What other players see

Other players see your nickname on the plot you claimed.

## How we use it

- To run your account and your farm
- To email you verification and password reset codes
- To protect accounts from misuse
- For product analytics, described below

We don't sell your data or use it for ads.

## Services we use

- Mixpanel: product analytics, described below.
- Mapbox: the map. Your phone loads the map from Mapbox, so Mapbox receives your IP address and device details. With Share anonymous map usage on (Settings › Licenses › Mapbox), Mapbox also collects anonymous usage data. You can turn it off there.
- Google: Google sign-in, if you use it.
- An email service that delivers our emails.

Our servers are in the United States.

### Product analytics

We use Mixpanel, a US company, to see how the game is used so we can improve it. Our server sends Mixpanel a record when you:

- create an account or sign in, and how you signed in
- claim a farm plot or enter your farm
- do something on your farm, such as tilling or selling, and whether it worked
- sell items or claim a blueprint

Each record has your account's internal ID, the time, the map area your farm is in, and game details such as the item, amount and coins earned. It does not include your email, nickname, profile, IP address, location coordinates or which plot is yours.

Mixpanel stores this data in the United States. We use it only to improve the game, not for ads.

When you delete your account, we ask Mixpanel to delete this data. Mixpanel completes deletion within 30 days.

## How long we keep it

We keep your account and farm until you delete your account. Email codes stop working after 10 minutes.

Our encrypted backups can keep deleted data until those backups are deleted. After you delete your account, we keep a record that it was deleted: the account's internal ID, a coded form of your email address and the time.

## Delete your account

Delete your account at https://farm.sensenjoy.cn/dynamicfarm/v1/account/delete. This deletes your account, profile and farm.

## Children

Dynamic Farm isn't meant for children under 13. We don't knowingly collect personal information from children under 13.

## Contact us

For questions or requests about your data, email shaojie@gensen.app.

## Changes

When we change this policy, we update it here and change the date above.

## 中文

# 动态农场隐私政策

更新日期：[上线日期]

本政策适用于动态农场 App 及其游戏服务。“我们”指动态农场的开发者 Gensen。

## 我们收集什么

**你的账号**

- 用邮箱注册时：你的邮箱地址和密码。密码只以无法还原的形式保存。
- 用 Google 登录时：你的 Google 账号编号、邮箱地址，以及作为初始昵称的名字。
- 你的昵称，以及你选填的性别和生日。未满 13 岁的生日不保存。

**你的农场**

- 你在地图上认领的地块及其位置。
- 农场里的东西，例如作物、动物、建筑、物品和金币。
- 你注册、认领地块和最近一次玩的时间。

**登录和安全**

- 你在各台手机上的登录，以及我们发给你的邮件验证码。
- 你登录时，我们用 IP 地址限制反复尝试。我们只保存你登录过的网络的编码形式，不保存 IP 地址。

你的角色外观只存在你的手机上。游戏不使用你手机的位置。

## 其他玩家能看到什么

其他玩家能在你认领的地块上看到你的昵称。

## 我们怎么用

- 运行你的账号和农场
- 给你发验证码和重设密码的验证码
- 防止账号被滥用
- 产品分析，见下文

我们不出售你的数据，也不用于广告。

## 我们使用的服务

- Mixpanel：产品分析，见下文。
- Mapbox：地图。你的手机从 Mapbox 加载地图，所以 Mapbox 会收到你的 IP 地址和设备信息。打开“Share anonymous map usage”（设置 › Licenses › Mapbox）时，Mapbox 还会收集匿名使用数据，你可以在那里关掉。
- Google：Google 登录，如果你使用。
- 替我们发送邮件的邮件服务。

我们的服务器在美国。

### 产品分析

我们使用美国公司 Mixpanel 了解游戏的使用情况，用来改进游戏。你做下面这些事时，我们的服务器会发一条记录给 Mixpanel：

- 注册或登录账号，以及用什么方式登录
- 认领地块或进入自己的农场
- 在农场里操作（例如翻地、出售），以及是否成功
- 出售物品或领取蓝图

每条记录包含你账号的内部编号、时间、农场所在的地图区域，以及物品、数量、所得金币这类游戏信息；不包含你的邮箱、昵称、个人资料、IP 地址、位置坐标，也不包含你是哪块地。

Mixpanel 把这些数据存放在美国。我们只用它改进游戏，不用于广告。

你删除账号后，我们会请求 Mixpanel 删除这些数据，Mixpanel 在 30 天内删完。

## 保留多久

你的账号和农场保留到你删除账号为止。邮件验证码 10 分钟后失效。

加密备份里可能留有已删除的数据，直到这些备份被删除。你删除账号后，我们保留一条删除记录：账号内部编号、邮箱地址的编码形式和删除时间。

## 删除账号

在 https://farm.sensenjoy.cn/dynamicfarm/v1/account/delete 删除账号。删除后你的账号、资料和农场都会删掉。

## 儿童

动态农场不面向 13 岁以下的儿童。我们不会有意收集 13 岁以下儿童的个人信息。

## 联系我们

关于你的数据的问题或请求，请发邮件到 shaojie@gensen.app。

## 变更

政策有变化时，我们会在这里更新，并改上面的日期。

## 每节对应的代码和表

| 政策里的说法 | 代码或表 |
|---|---|
| 邮箱、密码只存无法还原的形式 | `users.email`、`users.email_verified`、`users.password_hash`（scrypt，`server/src/accounts/password.ts`）；`server/src/db/schema.sql` |
| Google 账号编号、邮箱、名字作初始昵称 | `user_identities`（`provider='google'`、`provider_uid`=Google `sub`）；只在 Google 标明已验证时存邮箱；没有昵称时用 `given_name` 作 `users.display_name`（`server/src/accounts/routes.ts` 的 `resolveIdentityUser`、`google_token.ts`）。正式服 Apple 登录关闭（`server/deploy/dynamicfarm/README.md`），所以政策不写 Apple |
| 昵称、选填的性别和生日；未满 13 岁的生日不保存 | `users.display_name`（必填）、`gender`、`gender_custom`、`birth_date`；不足 13 岁整条拒绝（`server/src/accounts/profile.ts` 的 `MIN_AGE`）；客户端 `scenes/account/account_panel.gd` 的 Your profile |
| 认领的地块及其位置；农场里的东西 | `parcel_claims`：`community_id`、`parcel_id`、`dataset_version`、`center_lat`/`center_lng`（地块中心，不是手机位置）、`farm_state`（作物、动物、建筑、物品、金币）、`claimed_at`、`updated_at`（`server/src/parcels/pg_store.ts`） |
| 注册、最近一次玩的时间 | `users.created_at`、`users.last_seen_at`、`players.created_at`、`players.last_seen_at` |
| 各台手机上的登录 | `tokens`（只存 `token_hash`，`created_at`、`last_used_at`），每个账号对应一行 `players`（`players.user_id`，`install_key_hmac`） |
| 邮件验证码，10 分钟失效 | `email_codes`（邮箱、用途、`code_hash`、`expires_at`、`attempts`）；`CODE_TTL_MS = 10 分钟`（`server/src/accounts/email.ts`）；删号时一并删除（`pg_store.ts` 的 `deleteUser`） |
| 用 IP 限制反复尝试；只存网络的编码形式 | 限流按 `req.ip` 在进程内存里计数（`server/src/accounts/routes.ts`、`server/src/http/app.ts`，网络键见 `http/network.ts` 的 `networkKey`）；`login_networks.network_hash` 是网络键的 HMAC，不存 IP（`routes.ts` 的 `trustNetwork`）。请求日志默认关闭（`HTTP_LOG` 不设，`server/src/http/app.ts`） |
| 角色外观只在手机上 | `modules/avatar/persistence/outfit_store.gd` 写 `user://`；动态农场不进联机空间，不上传外观（`scenes/dynamic_farm` 不用 `OnlineSpace`） |
| 游戏不使用手机位置 | 动态农场地图不调用 `start_location`（`scenes/dynamic_farm/dynamic_farm_map.gd`）；地图插件清单去掉了定位权限（`tools/android/overlay/AndroidManifest.xml`）。“定位”键只回到自己的地块 |
| 其他玩家看到地块上的昵称 | `GET /v1/parcels` 返回每块已认领地块的 `nickname`（`users.display_name`），不返回对方账号编号（`server/src/parcels/routes.ts`） |
| 发验证码 | `server/src/accounts/mailer.ts`，正式服经 `.env` 的 `SMTP_URL`、`MAIL_FROM` 发信 |
| Mixpanel 产品分析 | 见 `docs/legal/dynamic-farm-privacy-analytics.md`（SEN-C-204） |
| Mapbox 地图和匿名使用数据开关 | 手机直接从 Mapbox 加载地图；`Share anonymous map usage` 是 Mapbox SDK 自己的遥测开关，默认开（`scenes/map_poc/map_usage.gd`，设置 › Licenses › Mapbox › Map data） |
| Google 登录 | Android Credential Manager 在手机上取 Google ID token，服务端校验（`server/src/accounts/google_token.ts`） |
| 服务器在美国 | 正式服在美西（`tools/android/dynamic_farm_export.py` 的 `RELEASE_TARGET`，`server/deploy/dynamicfarm/README.md`） |
| 保留到删除账号 | 账号和农场没有按时间自动删除；闲置回收只针对游客（`PARCEL_IDLE_RECLAIM_DAYS`），正式服没有游客（`GUEST_ACCOUNTS=closed`） |
| 加密备份 | `ops.sh backup`：每天一次，`age` 加密；定时备份本机留最近 14 份（`DF_BACKUP_KEEP`），部署前等带标签的备份不轮换、要手工删，异地副本归主机备份方案（`server/deploy/dynamicfarm/README.md`“备份与恢复”） |
| 删除记录 | `account_deletions`：`user_id`、`provider_uid`（邮箱账号是邮箱的 HMAC `email:<emailKey>`）、`requested_at`、`source`、`apple_revocation`；不带外键、不存邮箱原文 |
| 删除账号 | 网页 `GET/POST /v1/account/delete`（邮箱验证码确认）；删除 `users` 行，级联删除 `user_identities`、`login_networks`、`players`→`tokens`、`parcel_claims`、`parcel_reclaims`、联机行，再删 `email_codes`，最后请求 Mixpanel 删除（`routes.ts` 的 `deleteUserEverywhere`、`pg_store.ts` 的 `deleteUser`） |
| 13 岁以下 | 生日不足 13 岁拒绝保存（`profile.ts`）；生日选填，不做年龄验证 |
| 联系邮箱 | `P0Legal.SUPPORT_EMAIL`（所有者 11-12 指定的地址） |

## 核对时发现的问题（不在本卡改）

- **动态农场 App 里没有删号入口**。SEN-C-204 表单写的“应用内 My account › Delete account”在动态农场到不了：地图右上角的账号键登录后只给“Sign out”（`dynamic_farm_map.gd` 的 `_account_action`），账号面板只在未登录时以 sign_in 打开，设置里也去掉了 Delete account（`tests/dynamic_farm/test_parcel_profile.gd`）。所以政策只写网页删号。Google Play 要求应用内和应用外都能删号，上架前要补应用内入口，并改 `docs/legal/dynamic-farm-play-data-safety.md` 第 3 节。
- 备份没有固定的保留期限：带标签的备份和异地副本不轮换，所以政策写“直到这些备份被删除”，不写天数。要写天数，先定备份保留规则。
- 法律主体只写了“Gensen”，仓库里没有公司全称；发信服务商（SMTP）由所有者提供（SEN-H-70），仓库里看不到是哪家，政策写“替我们发送邮件的邮件服务”。
- 正式包最终合并的安卓权限没有核（要看实际 APK 的清单）；政策只写“游戏不使用手机位置”，不写权限清单。
- `/v1/users/me/export`（导出账号和 Journey 农场）在动态农场 App 里没有入口，也不导出地块；政策不写导出，数据请求走联系邮箱。
