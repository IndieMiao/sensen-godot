# 数据流说明（E3）—— 供 SSLAUNCH E1 数据清单 / App Store 隐私标签 / Play 数据安全表

状态：2026-09-07，按当前代码（feat/next-feature）写；后续接入的第三方在「计划中」列里，接入时改成「已接」并补字段。
**唯一事实源**：这里改了，隐私政策、App Store「App 隐私」、Play「数据安全」三处都要跟着改。

## 1. 我们自己的服务端（`server/`，Fastify + PostgreSQL）

| 数据 | 来源 | 存哪 | 用途 | 保留 / 删除 |
|---|---|---|---|---|
| 账号映射：Firebase uid → 自有 user id、邮箱（可空）、创建时间 | Firebase ID token 校验后 | `users` | 登录、所有业务的主键 | 删号级联全删（`AccountModule`：social / feed / moderation / im） |
| 资料：昵称、handle、简介、头像装扮（JSON ≤4 KB）、关注列表可见开关 | 用户填写 | `profiles` | 主页、feed 作者卡 | 随删号删 |
| 关注关系 | 用户操作 | `follows` | 时间线可见范围、陌生人打招呼规则 | 随删号删（两个方向） |
| 动态（文字 ≤2000、图片 key ≤9 张）、点赞、一级评论 | 用户发布 | `posts` / `post_likes` / `comments` | feed | 随删号删；审核下架为 `hidden` |
| 私信 / 群聊消息（文字 ≤4000 / 图片 key）、会话成员、已读进度 | 用户发送 | `conversations` / `conversation_members` / `messages` / `user_events` | IM | 撤回软删；删号：本人消息内容清空、会话成员移除 |
| 举报（举报人、目标、原因、说明 ≤500）、拉黑、封禁 | 用户操作 / 管理员 | `reports` / `blocks` / `bans` | UGC 合规（Apple 1.2 / Play UGC） | 举报记录随举报人删号删；封禁记录保留（防再注册滥用，只有 user id） |
| 图片文件 | 用户上传 | R2（生产）/ 本地目录（dev） | feed / IM 图片 | key 带 user 前缀；删号时按前缀清理（待做，见 §4） |
| 农场存档（另一分支功能） | 玩法 | `farms` 等 | 街角四季 | 随删号删 |

不采集：精确位置（B5 地图接入后只存好友可见的**降精度**位置，非好友不给）、通讯录、设备标识、广告标识（不弹 ATT）。
服务端日志不写消息正文与位置（E2）。

## 2. 第三方（代采 / 数据接收方）

| 服务 | 状态 | 我们发过去什么 | 它给回什么 | 目的 | 备注 |
|---|---|---|---|---|---|
| Firebase Authentication（Google） | 已接 | 邮箱 + 密码 / Apple / Google 身份令牌；设备 IP 由 Firebase 自行记录 | uid、ID token、刷新 token | 登录 | 客户端直连 identitytoolkit；服务端只校验 token（Google JWKS），不调 Admin SDK。删号时调 `accounts:delete` |
| Cloudflare R2 | 待真桶（SSLAUNCH D4） | 图片字节（客户端直传预签名 URL） | 公网读地址 | 图片存储 / 分发 | 服务端不经手图片流量；key `u/<user_id>/<日期>/<随机>` |
| OpenAI omni-moderation | 已接（未配 key 时全部进人工队列） | 用户发布的**文本**（动态 / 评论 / 消息） | 是否命中 + 分类 | 前置审核 | 不发用户身份；OpenAI API 数据不用于训练（企业条款） |
| AWS Rekognition | 计划中 | 图片 | 分类 | 图片前置审核 | 接入时补 |
| Mapbox | 计划中（B5） | 地图瓦片请求（含设备 IP、粗略位置） | 瓦片 | 地图底图 | token 独立化 SGODOT-14 |
| LiveKit | 计划中（C4 / D5） | 语音流、房间 token | — | 语音房 | 麦克风权限 purpose string |
| FCM / APNs | 计划中（C2 / D7） | 推送 token、通知内容（只有标题类，不含消息正文） | — | 离线消息通知 | |
| Sentry | 计划中（E4） | 崩溃栈、设备型号 / OS 版本；**剔除**位置与消息内容 | — | 崩溃诊断 | E2 scrub |
| PostHog | 计划中（E5） | 匿名事件（注册转化 / DAU / 发送 / 发布 / 进房 / 举报 / 删号）；不采位置 | — | 产品指标 | 不弹 ATT，不做跨 App 跟踪 |

## 3. 客户端本地（设备上）

| 数据 | 位置 | 说明 |
|---|---|---|
| 会话（Firebase ID / 刷新 token、自有 user id、provider、邮箱） | `user://auth_session.json` | 登出 / 删号即清 |
| 首启裁决（年龄门结果、同意的条款版本） | `user://first_run.json` | COPPA 年龄门 <13 拒绝并持久化 |
| IM 同步游标 | `user://im_sync.json` | 只有一个整数 |
| 选图临时文件 | 系统临时目录 `sensen_picks/` | 上传后可清 |
| 语言 / UI 偏好 | `user://` | |

相册：用系统选图器（iOS PHPicker / Android Photo Picker），**不申请相册权限**，只拿到用户选中的那几张。

## 4. 待补

- R2 上按 user 前缀的删号清理（`AccountModule` 加 uploads 模块）；
- 上表「计划中」各项接入时改状态并补 purpose strings（R4）；
- 与隐私政策（SSLAUNCH B2）和两个商店的申报表逐条对照一次（SSLAUNCH E1）。
