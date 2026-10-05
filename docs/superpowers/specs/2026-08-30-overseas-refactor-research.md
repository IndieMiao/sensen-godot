# 森森海外版重构：调研方案与实施步骤

> **资料范围（2026-10-05 清理）**：保留原日期的技术选型、Avatar/地图参考或交接事实。旧玩法、UI、上架目标、版本与排期不是当前任务；当前规则与分期以 [玩法方案 v2](../../product/gameplay-plan-v2-2026-10-02.md) 为准。

**日期**：2026-08-30 ｜ **目标**：1–2 个月内完成功能重构，达到北美 Apple App Store + Google Play 上架规格（暂不实际提审），作为融资 Demo
**范围**：保留 IM、UGC/feed、地图、我的主页；旧小游戏全部不保留；客户端 Godot 替代 Unity；基础服务（注册/IM/语音）换海外版；后端重构；前端多语言化
**调研方法**：11 个并行调研代理（4 路本地备份盘点 + 6 路 Web 选型/合规调研）+ 1 轮对抗性缺口审查（14 条缺口已吸收修正）

---

## 0. 执行摘要

**结论：可行，但对"1–2 个月"必须诚实。** 全量范围约需 **30–38 人周**，8 周内交付需要 **4–5 名全职开发**（2 Godot + 1 原生插件 + 2 后端）并接受范围裁剪；2–3 人团队做全量需 12–16 周，或按第 6.4 节裁剪表收缩到核心四模块。

**改变认知的三个盘点事实**：

1. **线上 App 是「原生双端壳嵌 Unity」，不是 Unity App。** 登录、IM 界面、feed、我的主页全部在原生层（iOS ObjC + Android Kotlin），IM 用网易云信 NIMSDK，语音用声网 Agora，Unity 只承载 3D 地图和 avatar。所以"Godot 替代 Unity"实际是**用 Godot 重写整个 App**——好消息是 Godot 侧已完成的 avatar + 3D 地图恰好就是原 Unity 的全部职责，剩下的是把原生壳页面在 Godot 里重做。
2. **后端可整体复用，但有一项资产正在流失。** Java 17 + Spring Boot 3.2 微服务群（MongoDB + Redis + RocketMQ + gRPC）代码备份齐全，但**全部运行时配置在阿里云 Nacos 上、未入备份**——趁环境还在，本周必须导出，否则限流阈值/密钥/业务参数全部失传。
3. **中国依赖高度集中、边界清晰。** 客户端 Godot 侧几乎零中国 SDK 残留；替换面全部在服务层：网易云信（IM+推送+审核）、声网（RTC）、阿里云（OSS/短信/一键登录/内容安全/CDN/邮件）、微信/支付宝（支付+登录）。

**选型一句话版**：登录 Firebase Auth（免费 50k MAU，Godot 走 REST）；IM 自建极简版（商业 IM 全部把实时通道锁死在官方 SDK 里，Godot 接不进去）；语音 LiveKit（美国公司、开源、可自托管，融资叙事最优）；地图沿用已验证的 Mapbox v11 方案；存储 Cloudflare R2；推送 FCM+APNs 直连（$0）；审核 OpenAI omni-moderation（免费）+ Rekognition；崩溃 Sentry（有官方 Godot SDK）；统计 PostHog；Demo 不做支付。**全栈月成本约 $120–400。**

**三大风险**（详见第 8 节）：① iOS 端地图合成（G3）尚未验证，是唯一可能推翻地图方案的技术风险，必须第 1–2 周做掉；② 人力与工期错配——不定人力就没有可信排期；③ 合规里的"日历时间"项（D-U-N-S 组织账号 2–4 周、PhotoDNA 申请周期）不并行启动就会卡在最后。

---

## 1. 目标与范围

| 维度 | 决定 |
|---|---|
| 保留功能 | IM（私聊+群聊）、UGC feed（图文动态）、地图（好友位置+3D 角色）、我的主页（资料/个人空间）、avatar 换装 |
| 不保留 | 全部旧小游戏（_MicBattle/_SecretBomb/_SenLair/_StarCard/卧底/海龟汤玩法等）——合伙人确认"肯定不保留之前的游戏，逻辑会变" |
| 语音房 | 保留框架能力（上下麦/静音/音量），玩法不迁移；是否进 Demo 一期见待决策项 |
| 目标市场 | 北美；Apple App Store + Google Play 双store |
| 交付口径 | "达到可提审规格"（合规四件套齐备、双端包可出、demo 剧本可跑），暂不实际提审 |
| 用途 | 融资 Demo——技术叙事（自研栈、美国供应商）本身是卖点 |
| 引擎 | Godot 4.7（已投入：avatar 一期 + 3D 地图 PoC 已合 main，110+ 测试） |

---

## 2. 现状盘点

### 2.1 客户端真实架构（关键发现）

```
线上 App（中国版）
├─ iOS 原生壳（ObjC，sensen-ios）────┐  登录/IM 会话/feed/我的/设置 = 原生 UI
├─ Android 原生壳（Kotlin，android_donut）┘  网易云信 NIMSDK 10.9、百度地图、Agora 特供版、
│                                        阿里 OSS/一键登录、国内厂商推送、SolarEngine 归因
├─ 内嵌 Unity（Tuanjie 分支）：仅 3D 地图 + avatar/个人空间 + 小游戏
│   └─ 私有包 com.sensen.modules（Framework 115cs / Game 239cs / ChatRoom 45cs）
│      热更 HybridCLR + Obfuz 混淆（海外版全部弃用）
└─ 嵌壳 H5（gensen-client-web，Vue3）：活动页
```

- Unity 内**唯一**实质中国依赖 = 阿里云 API 网关签名（`SignedHttpClient.cs`，APP_KEY 硬编码）；换普通 HTTPS 即消除。
- 保留模块在 Unity 侧规模都不大：地图（NewMapHome 11 + MapHomePage 17 + MapTrace 7 cs）、feed 时间线（PostsTimeline 6 + Like 5 cs）、主页（NewUserHomePage 3 + Space 11 cs）——功能基线清晰，Godot 重写参照成本低。
- `flutterproject_sensen` 是 2023–2024 的旧版 Flutter 壳（已弃用），但自带 l10n 骨架（zh 185 词条 / en 65 词条），可作术语参考。

### 2.2 后端

- **技术栈**：Java 17、Spring Boot 3.2.2、Spring Cloud 2023 + Spring Cloud Alibaba；Nacos 注册/配置中心；gRPC 1.60 + protobuf 3.25（各服务带 `*-agent` stub）；**MongoDB**（无 MySQL）+ Redis(Redisson) + RocketMQ 5；xxl-job + 阿里 SchedulerX 定时任务。
- **核心服务**：`gensen_api`(gensen-major)=用户/关注/feed(Note)/地图/avatar/空间/榜单/支付入口；`gensen-basis`=公共库（im/agora/oss/sms/push）；`gensen-audio`=语音房；`gensen-pay`=支付；`gensen_job`=定时任务；`gensen_admin`=运营后台；`gensen-room-socket-server`=**自研 Node socket.io 信令服务（仅语音房进出房/麦位广播，不是聊天 IM）**。
- **IM 真身**：网易云信托管（服务端 NetEaseIMService + `/im/neteaseMsgCallback` 抄送回调），离线推送也走云信通道——海外版 IM 与推送需**整体新建**，没有"自研 IM 可升级"这回事（缺口审查修正）。
- **语音真身**：声网 Agora RTC（token 签发 + 回调验签在 basis-core/agora）。
- **部署物料**：24 仓有 Dockerfile；无 k8s manifests；**Nacos 运行时配置未入备份（高危，见 6.0 立即行动）**。

### 2.3 Godot 迁移进度（main@d8d9897）

| 已完成 | 未开始 |
|---|---|
| avatar 换装一期（装配/目录/持久化/shader，Android 真机 120Hz 验证） | IM 界面、feed、我的主页、登录/账号 |
| 3D 地图 PoC：G1 Android 合成真机通过、G2 相机同步已实现、多角色地理锚定+剔除 | 推送、多语言、设置/删号 |
| 移动端 UI 缩放 + 统一主题（白浮层+薄荷绿）+ 触摸滚动修复；23 个测试文件 | **iOS 端地图合成（G3）——最大技术风险** |

### 2.4 可复用资产

- **Gensen_US/**（2026-08 产出）：约 30 篇英文功能 PRD（派对房架构、关注、语音房管理、新手引导、MBTI2.0 等）+ 2026 年 2–7 月版本 release 英文记录 + 已定英文术语表——**海外版 PRD 与商店文案可直接取材**（注意：小游戏类文档弃用；飞书图床需重新导图）。
- 后端全部业务代码 + proto 定义（客户端可用 godobuf 直接生成 GDScript 侧）。
- Godot 侧 avatar 资产转换管线、Mapbox token、Android 原生桥接先例（语音/登录插件同构复用）。

### 2.5 中国区依赖替换总表

| 现状（中国版） | 用途 | 海外替代 | 迁移动作 |
|---|---|---|---|
| 网易云信 NIMSDK | IM+离线推送+在线状态 | 自建极简 IM（备选 Tinode） | 服务端新建，客户端 Godot WebSocket 直连 |
| 网易易盾/云信审核 | 文本/图片/音频审核 | OpenAI omni-moderation + AWS Rekognition | 审核管线重建（合规硬门槛） |
| 声网 Agora RTC | 语音房 | LiveKit Cloud（可自托管） | token 签发改 LiveKit JWT；客户端原生桥接 |
| 阿里云 OSS+CDN | 图片/资源存储 | Cloudflare R2（S3 兼容，零出流量费） | Java AWS SDK 换 endpoint |
| 阿里云短信/一键登录 | 注册登录 | Firebase Auth（邮箱验证码 + Apple/Google 登录） | 短信整体砍掉，省钱省 10DLC 审批 |
| 微信/支付宝/Ping++ | 支付 | Demo 不做支付（IAP 后置） | 虚拟商品按"免费解锁"处理 |
| 微信/QQ 登录 | 第三方登录 | Sign in with Apple + Google | 上 Google 登录则 Apple 登录为 4.8 强制 |
| 国内厂商推送 | 离线触达 | FCM + APNs 直连（$0） | Firebase Admin SDK for Java 统一发 |
| 百度地图（原生壳） | 2D 地图/定位 | Mapbox v11（Godot 方案已验证 Android） | 已在 3D 地图 PoC 内 |
| 阿里云邮件/SchedulerX/百炼 | 邮件/定时/AI | SES/Resend、Spring @Scheduled、后置 | 低优先级 |
| Nacos | 注册/配置中心 | **去除**：compose DNS + 环境变量 | Demo 量级下 Nacos 是纯负资产 |
| HybridCLR + Obfuz | 热更+混淆 | 弃用 | Apple 对热更本就敏感 |

---

## 3. 海外版目标架构

### 3.1 客户端：Godot 为唯一宿主（缺口审查补齐项）

**决策：Godot 全屏宿主 App，原生层零 UI 页面**，只以插件形态存在。旧原生壳与 Unity 均不保留。

```
Godot 4.7 App（唯一宿主：导航栈/路由/主题/全部页面 UI）
├─ 页面：登录 → 地图主页(Mapbox垫底) / feed / IM / 我的主页 / 语音房 / 设置
├─ 网络：HTTPRequest(REST+JSON) + WebSocketPeer(IM) + godobuf(如沿用 proto)
├─ i18n：gettext PO 工作流 + Noto Sans 字体 fallback 链
└─ 原生插件层（全部薄桥接，复用 Mapbox 桥接先例）
    ├─ Mapbox 底图 view（Android 已验证；iOS = G3 待验证）
    ├─ Sign in with Apple / Google Credential Manager（取 id_token）
    ├─ FCM / APNs token 上报 + 通知回调
    ├─ Photo Picker（Android Photo Picker API + iOS PHPicker，均免权限弹窗）
    └─ LiveKit 音频（connect/mute/音量回调约 10–15 个方法，音频流不进 Godot）
```

要点：
- **导航**：单 Godot 场景栈（已有场景切换 spec）；Mapbox 原生 view 只在地图页作为垫底层，进出地图页时显隐，其余页面纯 Godot 全屏——避免"谁是宿主"的并行开发返工。
- **IM 长连接**：前台 WebSocket；`NOTIFICATION_APPLICATION_PAUSED` 断开、回前台按最后 seq 增量补拉；离线消息走推送（微信/WhatsApp 同款架构，也是 Apple 审核友好做法）。注意 Godot 4.7 生命周期通知在 iOS 有回归 issue（#115936），第 1 周真机验证，不可靠就在插件层桥 UIApplication 通知。
- **WebView 不做**：隐私政策/条款用 `OS.shell_open` 跳外部浏览器（iOS WebView 插件生态空白，Demo 阶段绕过）。
- **文本输入**是 Godot 做社交 App 的最大体验坑：Android IME 光标不同步（#68338）、键盘遮挡无自动避让（自己监听 focus + `virtual_keyboard_get_height()` 平移，iOS 键盘升起动画期高度不准需延迟取值）。聊天页键盘体验预留专门打磨时间。

#### 3.1.1 为什么不是原生壳 / Flutter 壳（架构对比，2026-08-30 定案）

| 路线 | 可行性 | 8 周 Demo 判断 |
|---|---|---|
| **纯 Godot 宿主** ✅ | 已验证（G1 Android 合成、avatar 真机、UI 主题、23 测试全在此架构上） | **选定**。单栈单团队；已投入资产全复用；代价=IME/键盘体验短板（已知 workaround） |
| Flutter 壳嵌 Godot | ❌ 生态不成熟：flutter_godot 插件**目前仅支持 Android**；libgodot FFI 包实验性；学术研究点名双向通信延迟/渲染管线冲突/视图错位问题；iOS 桥基本空白 | 排除。8 周内自建 Flutter-Godot iOS 桥不可控，且三层合成（Mapbox 垫底 + Godot 透明层 + Flutter PlatformView）把 G3 风险乘倍 |
| 原生双端壳嵌 Godot | ⚠️ 技术上可行：Android 官方支持 .aar 库嵌入（GodotFragment）；iOS 走 SwiftGodotKit/libgodot（基于 Godot 4.4，与本项目 4.7 有版本错配；不支持模拟器；+30MB） | 融资后的正路备选。双端两套 UI = 人力约翻倍，且需要 iOS/Android 工程师；Demo 期不选 |

关键认识：**换宿主消不掉地图叠层的 iOS 透明风险**（Mapbox 垫底+Godot 透明层在任何宿主下都存在），反而作废已验证的 Android G1。**留后路设计**：地图/avatar 模块保持清晰场景边界 + 消息桥接口，使其未来可"降级"为原生/Flutter 壳内的 3D 视图库（SwiftGodotKit 生态在快速成熟，GodotCon 2025 主推方向）。触发重评条件：融资到位扩团队、目标转为正式消费级产品、或手上有现成移动端工程师且 IM/feed 手感被判定为演示决定性因素。

### 3.2 后端：裁剪合并 + 单区域轻部署

- **保留改造**：gensen_api（裁掉游戏/支付/活动路由）、gensen-basis（换 OSS→R2、砍云信/短信）、gensen-audio（Agora→LiveKit token）、gensen_admin（审核工单最小化）。**新建**：IM 服务（消息模型+同步+推送+审核挂钩）。**弃用**：gensen-game/gamematch/gensen-card/gensen-pay（Demo）/room-socket-server（职责并入 IM 服务或保留做语音房信令，二选一）。
- **部署**：单区域 AWS us-west（1×t3.large 跑 docker-compose 合并 2–4 个 Java 进程 + Mongo 容器或 Atlas M10 + Redis 容器）；更省选 Hetzner US CPX41（$32/月）。**不上 K8s**。
- **去 Nacos**：服务发现=compose DNS；配置=环境变量+.env；RocketMQ→Redis Stream 或直接同步调用；SchedulerX/xxl-job→Spring `@Scheduled`（Demo 量级）。
- **数据库沿用 MongoDB**（缺口审查修正：不要按 MySQL 迁移，那是全部 Repository 层重写的巨量隐藏工作）。

---

## 4. 基础服务选型结论

> Godot 4.7 没有任何厂商官方 SDK——所有选型的第一筛选条件是"**有无平台无关的 REST/WebSocket 协议**"或"**原生 SDK 桥接面是否够小**"。

### 4.1 注册登录：Firebase Authentication ✅

- **免费 50k MAU**；Godot 走 Identity Toolkit REST（`signInWithPassword`/`sendOobCode`/`signInWithIdp`），有维护中的纯 GDScript 封装 GodotNuts/GodotFirebase；原生插件拿到 Apple/Google id_token 后**一次 POST 直换会话**。
- 登录方式：**邮箱验证码 + Sign in with Apple + Google**，不做短信（省 Twilio 10DLC 审批周期与费用，符合北美习惯）。上了 Google 登录，Apple 登录即为 Guideline 4.8 强制项。
- 删号：客户端可直调 `accounts:delete` + 后端调 Apple token revocation（5.1.1(v) 强制）。
- 现有 Java 账号服务退化为资料/业务层，用 Google JWKS 验 Firebase ID token 建映射；未来可迁自研或 Supabase（备选，`grant_type=id_token` 同样一步换）。
- 排除：Auth0 / Cognito（都要系统浏览器 + deep link 回跳插件，1–2 个月工期内是纯风险）；自研（省下的 8–12 人日该花在 IM 上）。工作量：约 3–5 人日 + 原生登录插件 2–4 人日。

### 4.2 IM：自建极简 IM ✅（备选 Tinode 自托管）

- **商业四强（Sendbird/Stream/Agora Chat/CometChat）全部出局**：实时通道锁死在官方客户端 SDK（REST 仅限服务端持全局 token 调用），Godot 只能做原生 SDK 数据层桥接——每家约 3–4 人周还买不来资产。
- **自建范围（Demo 版）**：消息表（Mongo）+ seq 增量同步 + 1v1/群文本图片 + FCM/APNs 离线推送 + 已读回执 + 举报/拉黑端点 + 审核挂钩。**诚实工期：服务端 4–6 人周（从零，不是"升级"——room-socket-server 只是语音房信令，没有 IM 可复用）**；客户端 WebSocketPeer 直连自有协议零桥接。
- **决策点（第 2 周末前定）**：若后端人力 < 2 FTE，切换 Tinode 自托管（文档化 JSON-over-WebSocket 协议，1v1/群/送达回执/FCM 内建，Godot 直连；1–1.5 周部署+封装），代价是举报/审核仍需自补、社区单维护者风险。
- Matrix/Synapse 为标准化备选（内建举报 API 最强，但 /sync 协议学习曲线陡）。

### 4.3 实时语音：LiveKit ✅（Cloud 起步，保留自托管退路）

- **选型理由**：美国公司（a16z 系）、Apache 2.0 开源、OpenAI 语音生态采用——北美融资叙事显著优于 Agora/ZEGO（Clubhouse-Agora 数据审查先例是尽调观感风险）；免费 5k 分钟/月，Ship 档 $50/月；量大后自托管客户端零改动。
- **集成路径**：移动端=原生 SDK 薄桥接（Swift/Kotlin 各一，桥接面 10–15 个方法：connect/disconnect/set_mic/说话人事件/音量——音频采集、3A、编码全在原生层，不进 Godot）；桌面端=社区 godot-livekit GDExtension（编辑器内联调房间逻辑，独有工程效率红利）。上下麦用 canPublish 权限 + token 刷新实现。
- 排除：自研 WebRTC（Godot webrtc-native 只有 DataChannel 可用，移动端回声消除 1–2 个月不可能补齐）；100ms（已转型医疗 AI，实质弃线）；Daily（单价 4 倍于 Agora）；Chime（无免费层、封装最少）。
- 合规配套：iOS `NSMicrophoneUsageDescription` + UIBackgroundModes audio；Android 14+ `FOREGROUND_SERVICE_MICROPHONE` 前台服务 + Play Console 声明；Data Safety 申报"音频实时传输不留存"。
- **语音房审核（缺口审查补齐）**：Demo 最小 SOP=举报即静音被举报者 + 人工进房复核 + 24h 处置记录；二期接 LiveKit egress→ASR→文本审核留证。SOP 必须成文（Apple 会问审核机制）。

### 4.4 地图：Mapbox v11 沿用 ✅

- 方案 A（原生 Mapbox v11 垫底 + Godot 4.7 透明层角色）G1/G2 已验证；**G3 iOS 合成是本方案的关键剩余风险**（Godot iOS 不支持窗口透明，spike 路线：runtime `layer.opaque=NO` → 引擎 patch → SwiftGodotKit fork 备选），第 1–2 周必须出结论并预设降级方案（Godot 内自绘瓦片地图）。
- 计费：Mobile SDK 按 MAU，**25k MAU/月免费**，Demo 量级 $0。需列入 Privacy Manifest / Data Safety 申报（Mapbox 遥测）；验证 Android SDK .so 16KB 对齐与 iOS SDK 自带 privacy manifest。

### 4.5–4.10 其余服务速览

| 领域 | 选型 | 成本（Demo 量级） | 要点 |
|---|---|---|---|
| 推送 | FCM + APNs，服务端 Firebase Admin SDK for Java 统一发 | $0 | 客户端插件自研（token 上报+回调，2–3 人日/端） |
| 存储+CDN | Cloudflare R2（S3 兼容） | $0–5/月 | 出流量免费；Java AWS SDK v2 换 endpoint 即迁 |
| 内容审核 | OpenAI omni-moderation（文本+图片，免费）打底 + Rekognition 图片二道（$0.001/张） | $0–30/月 | 免费端点无 SLA，Demo 可接受；正式运营前再评估 Hive |
| CSAM | PhotoDNA/Safer（申请制）+ NCMEC 上报 SOP | ~$0 | **申请周期长，第 1 周启动**；过渡期用 Rekognition 露骨内容标签 + 人工 |
| 崩溃 | Sentry（2025-07 起有官方 Godot SDK） | $0（5k errors/月） | Crashlytics 无 Godot 支持，不选；Java 后端同 org 接 sentry-java |
| 统计 | PostHog（HTTP capture API，Godot 十几行接入） | $0（1M 事件/月） | 融资 Demo 的 DAU/留存曲线由此出 |
| 邮件 | Amazon SES（$0.10–0.16/千封） | <$2/月 | SendGrid 免费层已死（2025-05）；备选 Resend |
| 支付 | **Demo 不做** | $0 | 虚拟商品按免费解锁；避开 IAP 集成+收款协议+税表数周流程；美国外链支付新规仍在流动，不做进架构 |

---

## 5. 北美双店上架合规清单

### 5.1 Apple 硬门槛

| # | 规则 | 对本 App 的动作 |
|---|---|---|
| 1 | **1.2 UGC 四件套** | feed/资料页/IM/语音房全部加举报+拉黑；发布链路前置自动过滤；App 内公开联系方式；2025 版明确随机/匿名聊天同受约束 |
| 2 | **1.2 实操加码** | 注册/首次发 UGC 前强制同意含"零容忍"条款的 EULA；举报 **24 小时内**下架+封禁（App Review 拒审模板明文） |
| 3 | **4.8 登录服务** | 提供 Google 登录 ⇒ 必须同时提供 Sign in with Apple |
| 4 | **5.1.1(v) 删号** | App 内可发起完整删号（非停用）；接了 SiwA 须调 token revocation；数据级联删除（IM/UGC/位置） |
| 5 | **Privacy Manifest** | Godot 4.3+ 导出内建 PrivacyInfo.xcprivacy（引擎命中 FileTimestamp/BootTime/DiskSpace/UserDefaults 四类）；第三方 SDK（Mapbox/LiveKit/Firebase）须带各自 manifest |
| 6 | **隐私营养标签** | 申报位置/用户内容/标识符等；与 Manifest、Data Safety、隐私政策**四处同源一致**（2025–26 两店交叉核验） |
| 7 | **ATT** | Demo 不接广告归因 SDK ⇒ 不弹 ATT，标签标"不追踪"；排查第三方 SDK 勿偷读 IDFA |
| 8 | **位置权限** | 只申请 When-In-Use，**绝不申请 Always**；purpose string 具体化（"在地图上向好友展示你的位置"） |
| 9 | **2025 新年龄分级** | 4+/9+/13+/16+/18+ 新体系，UGC+陌生人聊天+位置分享 ⇒ 预期 **16+ 或 18+**；按 16+ 预设产品线 |
| 10 | **加密出口申报** | `ITSAppUsesNonExemptEncryption` 正确设置（标准 HTTPS 可豁免）；记录 BIS 年度自分类义务 |

### 5.2 Google Play 硬门槛

| # | 规则 | 对本 App 的动作 |
|---|---|---|
| 1 | **target API 36** | **2026-08-31 起新 App 强制**（可延至 11-01）——正卡上架窗口；Godot 导出 targetSdk 直接设 36，Android 16 真机回归（前台服务/通知权限/edge-to-edge） |
| 2 | **16KB page size** | 2025-11 起新 App 强制；Godot 4.7 官方模板已对齐（NDK r28）；**所有第三方 .so（Mapbox/LiveKit/自研 GDExtension）逐个用 `check_elf_alignment` 验证** |
| 3 | **UGC 政策** | 与 Apple 1.2 一套实现复用；差异点：**发 UGC 前必须先同意条款** |
| 4 | **Child Safety Standards（CSAE）** | 社交类强制：公开儿童安全标准文档（URL）+ App 内举报 + NCMEC 上报流程 + 指定儿童安全联系人——**不填无法发布** |
| 5 | **账号删除双入口** | App 内删号 + **站外 Web 删号页**（URL 填入 Data Safety，展示在商店页） |
| 6 | **Data Safety 表单** | 含 SDK 代采数据全量申报；与 Apple 侧同源生成 |
| 7 | **位置权限** | 前台 FINE_LOCATION 无需单独审批；manifest 确保**没有** `ACCESS_BACKGROUND_LOCATION`（Godot 导出权限逐项检查，历史上有默认多带权限的坑） |
| 8 | **IARC 分级问卷** | 如实勾选聊天/UGC/位置分享 ⇒ Teen 或 Mature 17+，与 Apple 侧口径一致 |

### 5.3 美国法域

- **COPPA**：一般受众定位 + **中立年龄门**（注册第一步收生日、<13 拒绝并持久化、覆盖 SSO 路径）；2025 修订版把"采集任何 PI 前先过年龄门"升级为设计要求（合规截止 2026-04-22）。
- **CCPA/州法**：Demo 量级大概率不触发门槛，但隐私政策直接按 CCPA 模板写（约 20 州综合隐私法取最严公约数）；地理位置属敏感信息单独披露。
- **CSAM 法定义务**：18 U.S.C. §2258A——获知即须向 NCMEC CyberTipline 报告，这是法律不是商店政策。
- **DMCA**（缺口审查补齐）：美国版权局注册指定代理（$6 在线）；ToS 加版权投诉条款；举报类型加"侵权"。
- **州级年龄核验法**（信息项）：德州 App Store Accountability Act 已生效；Apple Declared Age Range API / Play Age Signals API 接入写进二期方案，收到未成年信号时降级体验（关陌生人私信/位置共享）。

### 5.4 主体策略：现有主体发 Demo → 新主体发正式版（风险评估，2026-08-30）

**结论：可行，但"公开上架"与"内测分发"风险天差地别。推荐双轨：Demo 期现有主体只走 TestFlight / Play 内测轨道（不公开上架），公开版直接用新主体发新 App。**

| 风险 | 内容 | 缓解 |
|---|---|---|
| **DOJ 批量敏感数据规则**（28 CFR 202，2025-04 生效）| 中国（含港澳）是 country of concern；**精确地理位置 >1,000 美国人即达 bulk 阈值**；中国境内团队可访问生产库=受限交易（员工/供应商协议口径）。本 App 核心功能就是位置，中国主体公开运营正中靶心；政府相关位置（军事基地等清单区域）**无阈值** | 内测分发天然控制用户数在阈值下；生产数据访问与中国侧隔离；位置对非好友降精度；正式版换美国主体根治 |
| **Sign in with Apple 迁移陷阱** | user ID 与 private relay 邮箱均为 **team-scoped**：换主体只有两条路——App Transfer + TN3159 transfer_sub 迁移流程（60 天窗口，需提前把 DB 关联到 transfer ID），或发新 App（**隐藏邮箱用户永久无法重新关联**） | 账号主键用自有 user id，登录以邮箱为主、SiwA 为辅；demo 不积累公开用户则直接新 App 重来，零迁移 |
| 融资叙事反噬 | TikTok 阴影下，"中国主体运营的美国社交+位置 App"是尽调最敏感画像——demo 本为融资服务，公开以中国 seller 上架可能反噬目的 | TestFlight 分发无公开 seller 足迹，投资人装机=测试邀请 |
| 隐私申报诚实性 | 公开上架则隐私政策/Data Safety 必须如实写数据控制者=中国公司+跨境访问，形成公开可查记录 | 内测规避；正式版以新主体重新申报 |
| 中国侧资产转让 | 正式版=中国主体→新主体的跨境 IP/资产转让：个性化推荐算法在中国技术出口管制目录内（TikTok 案同源；demo 时间线 feed 无推荐则低风险）、关联交易税务 | 新代码 IP 归属从现在就保持干净（贡献者协议）；feed 推荐算法留在正式版再评估 |
| 账号违规历史 | demo 期 UGC 审核不到位吃 1.2 警告记录在现有账号；Apple 有 repeat-offender 关联机制 | 审核四件套 demo 期就做全（本就是"可提审规格"的一部分） |
| 商标/品牌 | demo 期以中国主体注册 US 商标则后续需转让 | 商标直接以新主体（或待成立主体）注册 |
| 数据迁移 | demo 用户数据换控制者需通知/同意（CCPA 通知即可） | 用户少则放弃迁移、重新注册最干净 |

**推荐路径（四步）**：
1. **第 0 周**：新主体 + D-U-N-S 流程即刻启动（2–4 周、不占人力）——不是"融资后才办"，是现在就并行走。
2. **Demo 期**：现有主体只走 TestFlight（iOS 外测上限 1 万人，无公开商店页）+ Play internal/closed track。投资人装机=测试邀请；用户数天然低于 DOJ 阈值；无公开 seller 足迹。
3. **公开发行**：新主体发新 App。Demo 未积累公开用户 ⇒ App Transfer 与 SiwA 迁移复杂度整体跳过。
4. **若坚持公开发行 Demo**（不推荐）：位置对非好友降精度、生产数据访问与中国侧隔离、监控美国用户数逼近 1,000 阈值、过滤政府相关位置区域；账号体系按"可 App Transfer"设计（自有主键 + TN3159 transfer ID 预案），并接受尽调解释成本。

### 5.5 审核运营基线（可辩护最小配置）

发布前自动过滤（文本+图片）→ 人工复审队列（Demo 期运营兼任，但**流程与工单系统必须真实存在**）→ 举报 24h SLA → CSAM hash 匹配 + NCMEC SOP。后台用 gensen_admin 裁剪出最小审核工单页。

---

## 6. 实施步骤（8 周计划）

### 6.0 第 0 周立即行动（本周，均为"日历时间"项，不占开发人力）

1. **抢救 Nacos 配置**：趁阿里云环境可访问，导出全部 namespace 配置存档（若已失联：从 `@Value`/`@ConfigurationProperties` 反推配置清单，排第 1 周）。⚠️ 最高优先级
2. **双店开发者账号**：确定上架法律实体。**新北美主体 = Apple 全新组织账号，全流程重走**（账号绑定法律实体，不能沿用中国主体资质）。周期（假设公司已注册、有官网+同域名邮箱）：D-U-N-S 新号 ~5 个工作日（免费，买加急不缩短 Apple 侧等待）+ 同步到 Apple 系统 ~2 个工作日 + Apple 组织核验 3–6 个工作日（可能电话核验法人授权人）→ **常见合计 2–4 周，边缘案例 3 周+**；若公司尚未注册再加注册+EIN+官网 1–3 周。Play 组织账号 $25，同样要 D-U-N-S + 身份验证（数天–2 周），组织账号豁免新个人账号的 12 人/14 天封闭测试要求。税表 W-8/W-9。**降险路径**：Demo 期 TestFlight 内测可先用现有账号跑，正式提审用新主体账号发新 app（尚未上架，无迁移成本）——两条线并行，账号流程不阻塞开发。
3. **CSAM 检测申请**：提交 PhotoDNA / Thorn Safer 申请（审批周期长）。
4. **域名与合规页**：注册域名；隐私政策（CCPA 模板）+ ToS（含 UGC 零容忍 + 版权条款）+ Web 删号页 + 儿童安全标准页，托管 Cloudflare Pages（$0）。
5. **DMCA 代理注册**（$6）。
6. **语言范围定版**：建议 en-US（提审语言）+ zh-CN（华人用户），商店元数据只做 en-US。

### 6.1 工作流分解与工期

| WS | 内容 | 人周 |
|---|---|---|
| **A 客户端基建** | 架构骨架（导航/路由/API client/token 管理）1.5；i18n 基建+翻译 1；打包合规（manifest/target36/16KB/权限清理/InfoPlist.strings）1 | 3.5 |
| **B 客户端功能** | 登录页+Firebase REST 1；IM UI（会话/聊天/群/举报拉黑）2.5；feed（时间线/发布器/点赞）2；主页+设置+删号 1.5；地图整合（G3-G5+HUD）2.5；语音房 UI 1 | 10.5 |
| **C 原生插件** | Apple/Google 登录 1；FCM/APNs 1；Photo Picker 0.5–1；LiveKit 桥接双端 1.5–2 | 4–5 |
| **D 后端** | 部署基建+配置重建+去 Nacos 2–3；账号服务（Firebase 映射/删号级联/Web 删号）1.5–2；**IM 服务端 4–6**；feed/主页 API 裁剪+R2 迁移 2–3；语音房 token+信令 1.5–2；审核管线+工单后台 1.5–2；推送服务 0.5 | 13.5–18.5 |
| **E 合规与联调** | 数据清单→四处申报同源生成、分级问卷、CSAE 声明、demo 剧本联调、双端包验证 | 2 |
| **合计** | | **33.5–39.5** |

### 6.2 人力场景（关键决策输入）

| 场景 | 配置 | 8 周结果 |
|---|---|---|
| A（推荐） | 5 人：2 Godot + 1 原生插件 + 2 后端 | 全量范围（含语音房）达标 |
| B | 4 人：2 Godot（兼原生插件）+ 2 后端 | 达标，但砍：评论、Space 3D、语音房只留最小上下麦 |
| C | 2–3 人 | 8 周只能到 M2+IM（走 Tinode 路线）；全量需 12–16 周 |

**关键路径**：客户端架构+iOS G3（W1–2）→ IM 服务端（最长单项，W2–6）→ 合规硬化+联调（W7–8）。IM 选 Tinode 可把关键路径缩短约 2–3 周。

### 6.3 里程碑

- **M1（W2 末）**：客户端架构定型；**iOS 地图 G3 go/no-go**；后端骨架在海外云跑通（登录→拿到用户资料）；IM 自建 vs Tinode 定案；第 0 周流程项全部在途。
- **M2（W4 末）**：登录+主页+feed 只读端到端；IM 服务端 alpha（1v1 文本收发）；LiveKit 桥接 spike 通；R2/审核管线接通。
- **M3（W6 末）**：IM 端到端（群聊+图片+离线推送+举报拉黑）；feed 发布（Photo Picker→R2→审核→分发）；语音房 demo（建房/上下麦/静音）；i18n 切换可用。
- **M4（W8 末）**：合规硬化完成（删号双入口/EULA/年龄门/隐私四处申报/分级问卷/CSAE 声明/双端包 target36+16KB 验证）；融资 demo 剧本全程联调通过 = **"可提审规格" checklist 全绿**。

### 6.4 范围裁剪（MoSCoW）

- **Must**：登录三件套、IM（1v1+群，文本+图片）、feed（图文+点赞）、地图（好友位置+3D 角色）、我的主页+设置+删号、举报/拉黑/审核管线、en-US、推送。
- **Should**：语音房（LiveKit 基础能力）、feed 一级评论、zh-CN。
- **Could**：Space 3D 个人空间（复用换装房场景低成本保留）、系统分享、深链、应用内评分。
- **Won't（Demo 期）**：支付/IAP、任何小游戏、AIGC、热更、后台定位、多端完整漫游、语音消息。

---

### 6.5 北美双店上架前置流程预留周期总表（日历时间，与开发完全并行）

以 W8 末（≈2026-10 底）达到"可提审规格"为锚点倒排。这些项**不占开发人力，只吃日历**——晚启动就会成为 W8 的唯一卡点。

| 前置项 | 预留周期 | 最晚启动 | 说明 |
|---|---|---|---|
| 公司注册（若新主体未成立） | 1–2 周 | 第 0 周 | Delaware/目标州，可加急到数天；注册代理人必备 |
| EIN（税号） | 即时–4 周 | 第 0 周 | 有 SSN 线上即时；外籍股东走 SS-4 传真/电话 1–4 周 |
| 官网 + 同域名邮箱 | 1–2 天 | 第 0 周 | Apple 组织核验要求实体信息可查、域名匹配 |
| **D-U-N-S 新号** | ~5 个工作日 + 2 个工作日同步进 Apple | 第 0–1 周 | 免费；买 D&B 加急**不缩短** Apple 侧等待 |
| **Apple 组织账号核验** | 3–6 个工作日常见，**总计 2–4 周**（边缘案例 3 周+） | D-U-N-S 到手即提 | 可能电话核验法人授权人；$99/年 |
| **Play 组织账号 + 身份验证** | 数天–2 周 | 第 0–1 周 | $25 一次性；组织账号也要 D-U-N-S；豁免个人账号 12 人/14 天封闭测试要求 |
| PhotoDNA / Thorn Safer 申请 | 数周（申请制，**不可控**） | 第 0 周 | 过渡期用 Rekognition 露骨内容标签 + 人工兜底 |
| 域名 + 隐私政策/ToS/Web 删号页/儿童安全标准页 | 2–3 天 | 第 1 周 | 提审表单必填 URL；Cloudflare Pages $0 |
| DMCA 代理注册 | 当天，$6 | 第 1 周 | copyright.gov 在线 |
| 税表 W-8/W-9 与收款协议 | 数天 | 仅付费 App 需要 | Demo 免费 App 可跳过银行/税务设置 |
| TestFlight 内测（内部 100 人） | 即时，无审核 | — | Demo 分发主通道 |
| TestFlight 外测（Beta App Review） | 首个构建 ~1–2 天 | 演示前 1 周 | 后续构建通常秒过 |
| Play internal/closed track | 数小时–数天 | 演示前 1 周 | 新账号首包审核可能 3–7 天，预留一周 |
| **首次公开提审（若走到这步）** | **预留 2–4 周** | 目标发布日前 4 周 | Apple 90% 提审 24–48h 出结果，但社交/UGC 类首次提审吃 1–3 轮拒审是常态（1.2 审核机制说明、权限文案、年龄分级都是高频拒点）；审核备注里必须附测试账号 |
| IARC 分级问卷 / CSAE 声明 / Data Safety / 隐私标签 | 各半天（填表） | W7–8 | 内容依赖"数据清单"唯一事实源（见 5.1#6） |

**汇总**：新主体全链条（公司→EIN→官网→D-U-N-S→双店账号）保守 **4–8 周**，与 8 周开发计划等长——这就是"第 0 周启动、全程并行"的原因。若公司已成立、只办账号：**2–4 周**。Demo 内测分发本身无硬前置（现有主体 TestFlight 即时可用）。

## 7. 成本汇总

**月度（DAU<5k）**：约 **$120–400/月**
云主机+DB $35–150（Hetzner 自托管 Mongo 取低值 / AWS+Atlas M10 取高值）｜ R2 $0–5 ｜ 推送 $0 ｜ SES <$2 ｜ 审核 $0–30 ｜ Sentry/PostHog $0 ｜ LiveKit $0–50 ｜ Mapbox $0（25k MAU 内）｜ Firebase Auth $0（50k MAU 内）

**一次性/年度**：Apple $99/年 + Play $25 + 域名 ~$12/年 + DMCA $6 + UI 翻译（约 1000–1500 词条 MT+人工校对 $100–300）

**说明**：Demo 量级下真正花钱的只有云主机和数据库；SaaS 全部躲在免费额度内。放量后最先出现的账单：Mapbox MAU、LiveKit 分钟、审核 API。

---

## 8. 风险与待决策项

### 风险（按杀伤力排序）

1. **iOS 地图合成未验证（G3）**——唯一可能推翻地图方案的技术风险。W1–2 强制出结论；降级预案：Godot 内自绘矢量瓦片地图（功能缩水但可控）。
2. **人力-工期错配**——33–39 人周的量，不定人力就没有可信承诺。用 6.2 场景表先做人力决策。
3. **Nacos 配置流失**——阿里云环境一旦到期，业务参数全部失传。第 0 周动作，成本半天。
4. **target API 36 时间线**——上架窗口（2026-10/11）按新 App 口径必须 target 36，Godot 4.7 默认 targetSdk 需第 1 周核实并用自定义 gradle build 提级+真机回归。
5. **Godot 文本输入体验**——IME/键盘遮挡是引擎已知短板，聊天页体验直接影响融资 demo 观感；每个里程碑都在真机过输入回归。
6. **流程性日历时间**——D-U-N-S 2–4 周、PhotoDNA 申请、Play 身份验证；不在第 0 周启动就会在 W8 卡住"可提审"口径。

### 待决策项（需要你/合伙人拍板）

| # | 决策 | 建议 | 期限 |
|---|---|---|---|
| 1 | 可投入人力（几人×几周） | ≥4 人全职（场景 B） | 立即 |
| 2 | 语音房是否进 Demo 一期 | 进（Should 档，融资演示价值高） | W1 |
| 3 | IM 自建 vs Tinode | 后端 ≥2 FTE 则自建，否则 Tinode | W2 末 |
| 4 | 语言范围 | en-US + zh-CN | W1 |
| 5 | Space 3D 个人空间去留 | 复用换装房低成本保留 | W2 |
| 6 | 上架法律实体（决定双店账号与 D-U-N-S） | 双轨：demo 用现有主体**仅内测轨道**，公开版新主体发新 App（见 5.4） | 第 0 周 |
| 7 | 品牌/商店名与域名（Gensen?） | —（业务决策） | 第 0 周 |

---

## 9. 关键参考来源

**Apple**：[Review Guidelines](https://developer.apple.com/app-store/review/guidelines/)（1.2/4.8/5.1.x）· [删号要求](https://developer.apple.com/news/?id=12m75xbj) · [Privacy Manifest](https://developer.apple.com/news/?id=pvszzano) · [2025 年龄分级](https://developer.apple.com/news/?id=ks775ehf) · [隐私标签](https://developer.apple.com/app-store/app-privacy-details/)
**Google Play**：[target API](https://support.google.com/googleplay/android-developer/answer/11926878) · [16KB pages](https://developer.android.com/guide/practices/page-sizes) · [删号政策](https://support.google.com/googleplay/android-developer/answer/13327111) · [UGC 政策](https://support.google.com/googleplay/android-developer/answer/9876937) · [Child Safety Standards](https://support.google.com/googleplay/android-developer/answer/14747720) · [Data Safety](https://support.google.com/googleplay/android-developer/answer/10787469)
**美国法域**：[COPPA FAQ](https://www.ftc.gov/business-guidance/resources/complying-coppa-frequently-asked-questions) · [COPPA 2025 修订](https://www.federalregister.gov/documents/2025/04/22/2025-05904/childrens-online-privacy-protection-rule) · [18 U.S.C. §2258A](https://www.law.cornell.edu/uscode/text/18/2258A) · [CCPA](https://oag.ca.gov/privacy/ccpa)
**选型**：[Firebase Auth REST](https://firebase.google.com/docs/reference/rest/auth) · [GodotFirebase](https://github.com/GodotNuts/GodotFirebase) · [Tinode API](https://github.com/tinode/chat/blob/master/docs/API.md) · [LiveKit 定价](https://livekit.io/pricing) · [godot-livekit](https://github.com/NodotProject/godot-livekit) · [R2](https://www.cloudflare.com/products/r2/) · [OpenAI Moderation](https://developers.openai.com/api/docs/guides/moderation) · [sentry-godot](https://github.com/getsentry/sentry-godot) · [godot-sdk-integrations](https://github.com/godot-sdk-integrations)
**Godot 工程**：[gettext i18n](https://docs.godotengine.org/en/4.5/tutorials/i18n/localization_using_gettext.html) · [16KB 对齐 PR#106358](https://github.com/godotengine/godot/pull/106358) · [Privacy Manifest issue#90323](https://github.com/godotengine/godot/issues/90323) · [Android IME #68338](https://github.com/godotengine/godot/issues/68338) · [iOS 生命周期回归 #115936](https://github.com/godotengine/godot/issues/115936) · [godobuf](https://github.com/oniksan/godobuf)

---

*本文档由 2026-08-30 的 11 路并行调研（4 路本地备份盘点 + 6 路 Web 调研）+ 1 轮缺口审查汇总而成；盘点证据均标注了备份盘内的具体文件路径，详见调研工作流 journal。*
