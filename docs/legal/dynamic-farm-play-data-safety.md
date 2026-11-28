# 动态农场 Google Play 数据安全表单：Mixpanel 相关答案

SEN-C-204。适用动态农场 App（`com.gensen.mapfarm`），在正式服打开 Mixpanel 上报（SEN-C-203、SEN-C-205）之前填好。草稿：所有者本人确认后合入；填表和提交由所有者在 Play Console 操作，不在本卡。

## 现有答案

- 本仓库里没有动态农场的数据安全表单答案。
- 已有的答案是 Gensen App（`app.gensen.maps`）的，在仓库外（`docs/governance/release-process.md` 第 7 步指向 `pm/legal/store-2026-11/store-forms-1113.md`），本卡未核（SEN-C-204#12）。
- 动态农场的表单如果已经填过（例如账号、邮箱），按下面逐项补；没填过就以下面为准，其它数据类型另行补齐。

## 逐项答案

### 1. 数据收集和安全

| 问题 | 答案 | 依据 |
|---|---|---|
| 应用是否收集或分享所需的用户数据类型 | 是 | 账号要邮箱；Mixpanel 上报游戏行为 |
| 所有用户数据在传输时是否都加密 | 是 | App 连 `https://farm.sensenjoy.cn/dynamicfarm/v1`；服务端连 Mixpanel 走 HTTPS（`https://api.mixpanel.com`） |
| 是否提供让用户请求删除数据的方式 | 是 | 见第 3 节 |

### 2. 数据类型（只列 Mixpanel 涉及的）

Mixpanel 是替我们做分析的服务商，按 Play 的定义，转给代为处理的服务商不算“分享”，所以下面“分享”都选否。

| 类别 › 数据类型 | 收集 | 分享 | 临时处理 | 必需还是可选 | 用途 | 对应的上报 |
|---|---|---|---|---|---|---|
| 应用活动 › 应用互动 | 是 | 否 | 否 | 必需（玩家不能关） | 分析 | `account_created`、`login`（含 `method`）、`parcel_enter`（`welcome_gift`、`rebased`） |
| 应用活动 › 其他操作 | 是 | 否 | 否 | 必需 | 分析 | 游戏操作：`parcel_claimed`（`dataset_version`、`starter_zone`）、`farm_command`（`command`、`count`、`outcome`、`reject_code`）、`market_sell`（`item`、`count`、`coins`）、`blueprint_claimed`（`blueprint`、`item`） |
| 个人信息 › 用户 ID | 是 | 否 | 否 | 必需 | 分析；已填的应用功能、账号管理保留 | 每条事件的 `distinct_id` = `users.id`（账号内部编号） |

以下选否，或保持已有答案、不因 Mixpanel 增加：

| 类别 › 数据类型 | 答案 | 理由 |
|---|---|---|
| 应用活动 › 应用内搜索记录、已安装的应用、其他用户生成的内容 | 否 | 不上报 |
| 个人信息 › 邮箱、姓名及其它 | 不因 Mixpanel 增加 | 邮箱、昵称、性别、生日不上报 Mixpanel；账号本身收集邮箱，按账号那部分的答案填 |
| 位置 › 大致位置、精确位置 | 不因 Mixpanel 增加 | 只报 `community_id`（地块所在社区编号，现在只有 `sf`），是玩家在地图上选的游戏区域，不是手机的位置；不报经纬度；每条带 `ip: 0`，请求从服务端发出，Mixpanel 拿不到玩家 IP |
| 设备或其他 ID | 否 | 不上报设备号、广告标识或安装编号 |
| 财务信息 › 购买记录 | 否 | `coins` 是游戏内金币，不是真钱 |
| 应用信息和性能 › 崩溃日志、诊断信息 | 不因 Mixpanel 增加 | 不上报 |

### 3. 数据删除

| 问题 | 答案 |
|---|---|
| 删除账号的方式 | 应用内：My account › Delete account。网页：`https://farm.sensenjoy.cn/dynamicfarm/v1/account/delete`（邮箱加密码或验证码，已上线，返回 200） |
| 删除账号时删除哪些数据 | 账号、个人资料和农场从我们的数据库删除；同时请求 Mixpanel 删除这个账号的全部分析数据，Mixpanel 最长 30 天删完 |
| 是否可以不删账号只删部分数据 | 否：没有单独删除分析数据的入口 |

删除 Mixpanel 数据要服务端配好 `MIXPANEL_GDPR_TOKEN`（`docs/plans/C-205.md`）。上线前会配好；没配或请求失败时，服务端日志记下账号编号，由人到 Mixpanel 后台补删。

### 4. 和隐私政策对齐

- 隐私政策网址填动态农场自己的政策（SEN-C-242 写，分析一节见 `docs/legal/dynamic-farm-privacy-analytics.md`）。不能填 Gensen App 的 https://gensen.app/privacy-android，那份写的是不用注册、没有第三方统计服务。
- 政策里的“产品分析”一节和本表单的应用活动、用户 ID、删除三项对应。
