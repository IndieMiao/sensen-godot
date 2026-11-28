# 动态农场隐私政策：产品分析一节（Mixpanel）

SEN-C-204。草稿：玩家可见文本由 PM 按 SEN-C-45 定稿，再交所有者本人确认后才能合入；合入不等于发布，网页发布另走所有者批准。

## 现有隐私政策在哪

- 线上只有两份，托管在 gensen.app，源文件不在本仓库：
  - 安卓：https://gensen.app/privacy-android（`modules/p0/p0_legal.gd` 的 `PRIVACY_ANDROID`，生效日期 2026-11-13）
  - iOS：https://gensen.app/privacy（`PRIVACY_IOS`）
- 这两份写的是 Gensen App（P0 演示服）：不用注册、手机生成随机玩家 ID，并写明“no third-party analytics”。Gensen App 连的不是动态农场正式服，不会给 Mixpanel 上报，所以这两份不用改。
- 动态农场 App（`com.gensen.mapfarm`，连 `https://farm.sensenjoy.cn/dynamicfarm/v1`）还没有自己的隐私政策：要邮箱或 Google 账号，设置里只有 Licenses，没有 Privacy Policy 入口（`scenes/dynamic_farm/parcel_profile.gd`）。
- Mixpanel 只会在动态农场正式服打开（`server/deploy/dynamicfarm/README.md`“产品分析（Mixpanel）”），所以下面这一节放进动态农场的隐私政策。本卡只写这一节，不写整份政策。

## 依据

- 事件和属性：`server/src/analytics/events.ts`、`server/src/accounts/routes.ts`、`server/src/parcels/routes.ts`，清单见 `docs/plans/C-203.md`；重设密码记 `login`（`method=password_reset`）见 `docs/plans/C-205.md`。
- 每条事件只带 `distinct_id`（`users.id`）、`time`、`$insert_id`（随机去重键）、`ip: 0`；由服务端发出，玩家手机不连 Mixpanel。
- 数据存放地区：美国。依据是所有者在 SEN-H-128 的回答“美国”（SEN-C-203#29）。
- 删号：应用内和网页两个删号入口删库成功后，服务端向 Mixpanel 提交删除请求，Mixpanel 最长 30 天删完（`docs/plans/C-205.md`）。没配删除令牌或请求失败时由人到 Mixpanel 后台补删；政策只写“会请求删除”，不写实现。

## 英文

### Product analytics

We use Mixpanel, a US company, to see how the game is used so we can improve it. Our server sends Mixpanel a record when you:

- create an account or sign in, and how you signed in
- claim a farm plot or enter your farm
- do something on your farm, such as tilling or selling, and whether it worked
- sell items or claim a blueprint

Each record has your account's internal ID, the time, the map area your farm is in, and game details such as the item, amount and coins earned. It does not include your email, nickname, profile, IP address, location coordinates or which plot is yours. Records are sent from our server, not your phone, so Mixpanel does not receive your IP address or device details.

Mixpanel stores this data in the United States. We use it only to improve the game, not for ads.

When you delete your account, we ask Mixpanel to delete this data. Mixpanel completes deletion within 30 days.

## 中文

### 产品分析

我们使用美国公司 Mixpanel 了解游戏的使用情况，用来改进游戏。你做下面这些事时，我们的服务器会发一条记录给 Mixpanel：

- 注册或登录账号，以及用什么方式登录
- 认领地块或进入自己的农场
- 在农场里操作（例如翻地、出售），以及是否成功
- 出售物品或领取蓝图

每条记录包含你账号的内部编号、时间、农场所在的地图区域，以及物品、数量、所得金币这类游戏信息；不包含你的邮箱、昵称、个人资料、IP 地址、位置坐标，也不包含你是哪块地。记录由我们的服务器发出，不经过你的手机，所以 Mixpanel 拿不到你的 IP 地址和设备信息。

Mixpanel 把这些数据存放在美国。我们只用它改进游戏，不用于广告。

你删除账号后，我们会请求 Mixpanel 删除这些数据，Mixpanel 在 30 天内删完。

## 文本和实际上报的对应

| 政策里的说法 | 事件 | 属性 |
|---|---|---|
| 注册或登录，以及登录方式 | `account_created`、`login` | `method`：`email`、`google`、`apple`、`password_reset`（补发脚本另有 `invite` 和 `backfill`）。正式服 Apple 登录关闭 |
| 认领地块或进入农场 | `parcel_claimed`、`parcel_enter` | `community_id`、`dataset_version`、`starter_zone`；`welcome_gift`、`rebased` |
| 农场操作及是否成功 | `farm_command` | `community_id`、`command`、`count`、`outcome`、`reject_code` |
| 出售物品或领取蓝图 | `market_sell`、`blueprint_claimed` | `community_id`、`item`、`count`、`coins`；`blueprint`、`item` |
| 账号的内部编号、时间 | 全部 | `distinct_id`（`users.id`）、`time`；`$insert_id` 是随机去重键，不对应任何个人信息 |
| 农场所在的地图区域 | 地块类事件 | `community_id`：社区编号，现在只有 `sf` |
| 不含 IP，Mixpanel 拿不到 IP | 全部 | `ip: 0`，请求从服务端发出 |

不上报：邮箱、昵称、性别、生日、地块编号、地块中心经纬度、玩家 IP、设备型号、广告标识。没有账号的请求不上报。

## 放进整份政策时要一起写的地方

动态农场的整份政策还没写，写的时候和这一节对齐：

- “我们使用的服务”表加一行：Mixpanel（美国公司）｜产品分析｜上面列的游戏记录和账号内部编号，不含邮箱、IP 和位置坐标。
- “存放在哪里”写上：分析数据由 Mixpanel 存在美国。
- “保留多久”写上：分析数据保留到删除账号；删号后请求 Mixpanel 删除，30 天内删完。
- “删除数据”写上：删除账号也会请求删除 Mixpanel 里的分析数据。
- 简要说明里不能写“没有第三方统计服务”（Gensen App 政策里有这句，不能照搬）。
