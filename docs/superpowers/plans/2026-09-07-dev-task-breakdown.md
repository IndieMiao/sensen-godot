# 森森海外版（Godot 宿主）：开发任务拆解 —— IM / feed / 主页 / 地图 / 语音房主线

- 日期：2026-09-07 ｜ 分支：`feat/next-feature`（基线 a7426ef）
- 依据：`docs/superpowers/specs/2026-08-30-overseas-refactor-research.md`（§1 范围、§3 目标架构、§4 选型、§6.1 工作流、§6.3 里程碑、§6.4 MoSCoW）
- **不依据**：`docs/product/map-farm-life-sim-direction.md` v0.4 与 09-03 农场实施方案——种田玩法在并行分支 `feat/farm-ui-playability` 推进，其任务在 Plane SGODOT 模块「F 街角四季 MVP」，本分支不承接
- 任务系统：Plane **Sensen Godot（SGODOT）**，模块 A–E 与本文 §3 一致；跨分支模块 R 发布链 / X 工程债 / Z Won't；非开发事务在 Plane **SSLAUNCH**（`../../../sensen-overseas-ops/`）
- 进度快照：`2026-09-08-remaining-tasks.md`（剩余任务与卡点标注，随 Plane 评论同步）
- 性质：工程侧 WBS，估算沿用 08-30 文档的人周口径；每条开工时再按仓库 plan 格式写任务单

---

## 0. 范围与定位

| 维度 | 决定（08-30 §1） |
|---|---|
| 保留功能 | IM（私聊 + 群聊）、UGC feed（图文动态）、地图（好友位置 + 3D 角色）、我的主页（资料 / 个人空间）、avatar 换装 |
| 语音房 | 保留框架能力（上下麦 / 静音 / 音量），玩法不迁移；Should 档，是否进 Demo 一期 = SSLAUNCH F2 |
| 不保留 | 全部旧小游戏；旧原生壳与 Unity 均不保留 |
| 引擎 / 架构 | Godot 4.7 全屏宿主，原生层零 UI 页面只以插件形态存在（§3.1） |
| 后端 | 08-30 按复用 Java Spring Boot 微服务裁剪合并估算；农场分支已另建 Node/Fastify 服务——**栈选择是本分支第一个待决策（D0）** |
| 目标 | 1–2 个月达到北美 Apple + Play「可提审规格」（暂不提审），作融资 Demo |

**页面骨架（§3.1）**：登录 → 地图主页（Mapbox 垫底）/ feed / IM / 我的主页 / 语音房 / 设置。地图页常驻底层，进出时显隐原生 MapView；其余页面纯 Godot 全屏。

---

## 1. 现状可复用盘点（仓库 a7426ef）

| 能力 | 现状 | 用法 |
|---|---|---|
| avatar 一期 | `modules/avatar`：装配 / 换装 / 存档 / toon shader，15 部件，155 用例 | 主页头像、地图 3D 角色、换装房直接复用；部件池扩充（B7） |
| 地图 PoC + 09-04 Demo | `scenes/map_poc` + Android Kotlin 插件 + iOS Swift/UDP 桥；G1 Android 合成、G2 相机同步、G3 iOS 透明真机通过；换装回写地图 / GPS / Marker 气泡 / 手势惯性已 Done（SGODOT-9/16/17/18） | 地图主页的基线（B5）；农场分支的受限地图模式不合入 |
| 路由 / UI | `AppRouter` 场景栈 + Android 返回键；`design_tokens.gd` + `app_theme.tres` + `SafeAreaMargin`；Noto Sans SC 全局字体 | 架构骨架（A1）扩成路由表 + Tab 壳 |
| 网络层 | `modules/net/api_client.gd`（可注入 transport、协程化、幂等重试）、`net_service.gd` | 改接 Firebase token 与海外后端；WebSocketPeer 封装新增 |
| 测试 / 工具 | gdUnit4 + `tools/run_tests.sh`（orphans 计失败）；Android / iOS 构建脚本 | 新模块同结构；Godot CI 缺（R 模块 B1） |
| 服务端参考 | `server/` Node/Fastify/PostgreSQL（农场）；Java 微服务群在备份盘（24 仓，无 k8s manifests，Nacos 配置未入备份） | D0 决策后二选一；Nacos 抢救归 SSLAUNCH G1 |
| 缺 | 登录 / 账号、IM、feed、主页、语音房、推送、Photo Picker、SiwA / Google 插件、LiveKit 桥、审核管线、i18n、删号、年龄门、Sentry / PostHog | 本文 §3 全部 |

---

## 2. 里程碑（08-30 §6.3；W0 = 2026-08-31 当周，本文写于 W1）

| 里程碑 | 截止 | 出口 |
|---|---|---|
| **M1** W2 末 | 2026-09-20 | 客户端架构定型（A1）；后端骨架在海外云跑通 登录 → 拿到用户资料（D1 + D2 + B1）；IM 自建 vs Tinode 定案（SSLAUNCH F4）；D0 后端栈定案；iOS 生命周期通知验证（A6）；第 0 周流程项（SSLAUNCH）全部在途 |
| **M2** W4 末 | 2026-10-04 | 登录 + 主页 + feed 只读端到端（B1 / B4 / B3 / D4）；IM 服务端 alpha 1v1 文本（D3）；LiveKit 桥接 spike 通（C4）；R2 / 审核管线接通（D4 / D6） |
| **M3** W6 末 | 2026-10-18 | IM 端到端：群聊 + 图片 + 离线推送 + 举报拉黑（B2 / D3 / C2 / D7 / E1）；feed 发布：Photo Picker → R2 → 审核 → 分发（B3 / C3）；语音房 demo 建房 / 上下麦 / 静音（B6 / C4 / D5）；i18n 切换可用（A2） |
| **M4** W8 末 | 2026-11-01 | 合规硬化完成：删号双入口 / EULA / 年龄门 / 隐私四处申报 / 分级问卷 / CSAE / 双端包 target36 + 16KB（E 模块 + R 模块）；融资 demo 剧本全程联调 = 可提审 checklist 全绿（E7） |

**关键路径**（§6.2）：客户端架构 + 后端骨架（W1–2）→ **IM 服务端（最长单项，W2–6）** → 合规硬化 + 联调（W7–8）。IM 选 Tinode 可缩短 2–3 周。

---

## 3. 任务清单（模块 = 08-30 §6.1 工作流）

估算沿用 08-30 人周；「依赖」中 `SSL-*` 指 SSLAUNCH 任务。**Plane 编号见 §8。**

### A 客户端基建（3.5 人周）

| # | 任务 | 估算 | 截止 | 依赖 | 出口 |
|---|---|---|---|---|---|
| A1 | 架构骨架：路由表 + Tab 壳；API client（Firebase token 注入 / 刷新、错误码、幂等重试）；会话状态机；`WebSocketPeer` 封装（前台连、`PAUSED` 断、回前台按 seq 补拉）；地图页常驻底层 | 1.5 人周 | 09-20 | — | M1 客户端架构定型 |
| A2 | i18n 基建：gettext PO 提取、全部字串 `tr()` 化、en-US 主 / zh-CN 次、Noto fallback、语言切换；PO 交 SSL-E10 | 1 人周 | 09-27 | SSL-F3 | M3 切换可用 |
| A3 | 打包合规：iOS Privacy Manifest 核查 + purpose strings + 加密标记（R4）；Android 权限审计 + target 36 显式 + Android 16 回归（R5）；16 KB 对齐（SGODOT-35） | 1 人周 | 10-11 | SSL-B8 | 双端包验证入 E7 |
| A5 | 文本输入与键盘专项：IME 光标同步 #68338、键盘避让 `virtual_keyboard_get_height()`、聊天 / 发布器 / 资料编辑三处 | 2 人天 + 每里程碑 0.5 | 10-18 | — | 每里程碑真机输入回归 |
| A6 | iOS 生命周期通知验证 #115936；不可靠则插件层桥 `UIApplication` | 0.5 人天 | 09-13 | — | IM 长连接前后台可靠 |
| A7 | GameUi / DesignTokens 单一来源（SGODOT-19） | 1 人天 | 10-25 | — | 改两个文件换全局风格 |

### B 客户端功能（10.5 人周）

| # | 任务 | 估算 | 截止 | 依赖 | 出口 |
|---|---|---|---|---|---|
| B1 | 登录页 + Firebase Auth REST（邮箱验证码 / SiwA / Google `signInWithIdp`）+ 会话持久化；GodotFirebase 封装评估；自有 user id 为主键 | 1 人周 | 09-20 | C1、D2、SSL-D1 | M1 登录 → 资料 |
| B2 | IM UI：会话列表 / 单聊 / 群聊 / 图片消息 / 已读 / 离线补拉 / 长按举报 / 拉黑 | 2.5 人周 | 10-18 | A1、D3、C2、C3 | M3 IM 端到端 |
| B3 | feed：时间线 / 多图发布器 / 点赞 / 一级评论（Should）/ 举报；无推荐算法 | 2 人周 | 10-04 只读 → 10-18 发布 | D4、C3、D6 | M2 只读，M3 发布 |
| B4 | 我的主页 + 设置：资料页 / 编辑 / avatar 入口 / Space 3D（Could）/ 设置四入口 / 首启合规流（年龄门 R2 → 同意 R3 → 登录）；删号入口（R1） | 1.5 人周 | 10-04 | B1、D2 | M2 主页端到端 |
| B5 | 地图主页整合：Mapbox 垫底 + Godot 透明层；好友位置（非好友降精度）+ 3D 角色（好友 avatar）+ HUD；进出显隐；位置只 When-In-Use | 2.5 人周 | 10-04 | A1、B7、D4 | 地图页在路由壳内可用 |
| B6 | 语音房 UI：房间列表 / 建房 / 麦位 / 上下麦 / 静音 / 音量 / 说话人 / 举报（Should） | 1 人周 | 10-18 | C4、D5、SSL-F2 | M3 语音房 demo |
| B7 | avatar 换装房接入主页 + 装扮上服务端 + 部件池扩充（剔除水晶族） | 2 人天 | 10-04 | D4 | 地图 / 资料显示好友装扮 |

### C 原生插件（4–5 人周，全部薄桥接）

| # | 任务 | 估算 | 截止 | 依赖 | 出口 |
|---|---|---|---|---|---|
| C1 | Sign in with Apple / Google Credential Manager → id_token | 1 人周 | 09-27 | SSL-A9 | B1 双通 |
| C2 | FCM / APNs token 上报 + 通知回调 + 前台处理（双端） | 1 人周 | 10-11 | SSL-A9 | IM 离线推送到达 |
| C3 | Photo Picker（Android Photo Picker API / iOS PHPicker，免权限弹窗）多图 | 0.5–1 人周 | 10-04 | — | feed / IM 选图 |
| C4 | LiveKit 音频薄桥接双端（10–15 方法）+ 桌面 godot-livekit；麦克风 / 前台服务合规配套 | 1.5–2 人周 | 10-04 spike → 10-18 | SSL-F2、SSL-D2 | M2 spike 通 |
| C5 | iOS 地图桥生产化决策（UDP 回环加固 vs GDExtension，SGODOT-71 / 6）；Android 插件 AAR 化（SGODOT-10） | 1 人天决策 + 加固 | 10-25 | — | TestFlight 包不因桥崩 |

### D 后端（13.5–18.5 人周；D0 决策后重估）

| # | 任务 | 估算 | 截止 | 依赖 | 出口 |
|---|---|---|---|---|---|
| **D0** | **【已决策 2026-09-07】后端统一 Node**：在现有 `server/`（Fastify + TypeScript + PostgreSQL）上扩展，不复用 Java 微服务。后果：feed / 关注 / 资料 / 审核 / 推送全部新写，08-30 的 WS-D 人周按"重写"口径重估；Java 仓库与 Nacos 配置只作业务规则参考（SSL-G1 仍要抢救，用来核对限流阈值与业务参数） | — | 已定 | — | D1–D7 按 Node 口径开工 |
| D1 | 部署基建（Node 口径）：现有 `server/deploy` compose（app + PostgreSQL + Caddy）已在香港 ECS 跑通，本项变成"迁到海外区域 + 加 Redis（会话 / 限流 / WebSocket 广播）+ 环境分离"；不再有 Nacos / RocketMQ / SchedulerX 迁移 | 1 人周 | 09-20 | SSL-D5 | M1 骨架跑通 |
| D2 | 账号服务：Google JWKS 校验 Firebase ID token → 自有 user id 映射；删号级联（资料 / IM / feed / 位置 / 关注 / token / 举报）+ Apple revocation + Web 删号接口 + 数据导出 | 1.5–2 人周 | 09-27 | D1、SSL-D1 | M1 登录 → 资料 |
| **D3** | **IM 服务端**：自建极简（Mongo 消息表 + seq 同步 + WS 网关 + 1v1 / 群 文本图片 + 推送 + 已读 + 举报拉黑 + 审核挂钩）**4–6 人周**，或 Tinode 自托管 1–1.5 周 | 4–6 人周 | 10-04 alpha → 10-18 | SSL-F4（W2 末） | M2 alpha，M3 端到端 |
| D4 | feed / 关注 / 资料 API（Node 新写：Note 时间线、点赞、一级评论、关注、资料、avatar 装扮）+ R2 预签名直传 + CDN；业务规则对照 Java gensen_api 代码 | 3 人周 | 10-04 | D1、SSL-D4 | M2 feed 只读 + R2 |
| D5 | 语音房 token + 信令：Agora → LiveKit JWT（canPublish 上下麦）；room-socket-server 保留或并入 IM | 1.5–2 人周 | 10-11 | SSL-F2、SSL-D2 | M3 语音房 demo |
| D6 | 审核管线 + 工单后台：omni-moderation + Rekognition 前置过滤 → 人工复审 → 24h 处置；reports / blocks；gensen_admin 最小工单页；PhotoDNA 接入位 | 1.5–2 人周 | 10-04 | SSL-D5、SSL-D6 | M2 管线接通 |
| D7 | 推送服务：Firebase Admin SDK 统一发 FCM + APNs；token 表；IM 离线 / 点赞评论通知 | 0.5 人周 | 10-11 | SSL-D1 | M3 离线推送 |
| D8 | 环境分离 prod / qa / dev + 演示账号脚本 | 0.5 人天 | 10-11 | D1 | — |
| D9 | 备份策略：Mongo 备份保留期 + R2 异地副本 + 恢复演练 | 0.5 人天 | 10-11 | SSL-D4 | — |
| D10 | 云迁移预案（条件项，SGODOT-77）；Mapbox token 独立化（SGODOT-14） | 1 + 0.5 人天 | 待定 | SSL-D5 / D3 | — |

### E 合规与联调（2 人周 + 合规硬化）

| # | 任务 | 估算 | 截止 | 依赖 | 出口 |
|---|---|---|---|---|---|
| E1 | UGC 四件套落地：feed / 资料页 / IM / 语音房 举报 + 拉黑双向不可见 + 前置过滤 + 公开联系方式 + EULA 零容忍强制同意 | 2 人天客户端 | 10-18 | D6、SSL-C6、SSL-B3 | Apple 1.2 / Play UGC |
| E2 | 位置与聊天数据卫生：日志 / Sentry / PostHog scrub；非好友位置降精度；截图无位置元数据 | 0.5 人天 | 10-11 | E4、E5 | SSL-F6 控制措施落地 |
| E3 | 数据流说明 `docs/compliance/data-flow.md`（Firebase / Mapbox / LiveKit / Sentry / PostHog 代采）→ SSL-E1 | 0.5 人天 | 10-04 | E4、E5 | 四处申报唯一事实源 |
| E4 | 崩溃上报：sentry-godot + 服务端 Sentry；PII / 位置过滤 | 0.5 人天 | 10-11 | SSL-D7 | — |
| E5 | 埋点：PostHog；注册转化 / DAU / IM 发送 / feed 发布 / 语音房进房 / 举报 / 删号；不采位置；不弹 ATT | 1 人天 | 10-11 | SSL-D8 | 融资 DAU / 留存曲线 |
| E6 | 应用身份定版：包名 / Bundle ID / 显示名 / 图标 / 启动图 / 版本策略（现为 avatarphase1 / mapg3 / 图标空） | 1 人天 | 10-04 | SSL-B1 | R 模块发布包前提 |
| E7 | M4 联调：demo 剧本全程联调 + 可提审 checklist 全绿（双端包 target36 / 16KB / 权限 / manifest / 删号 / EULA / 年龄门）；审核备注所需测试账号 | 2 人周 | 10-30 | 全部 | **M4** |
| R1–R3 | 删号客户端入口 / COPPA 年龄门 / 条款同意（归 B4 首启合规流，卡在 B 模块） | 2.5 人天 | 10-11 | SSL-B2/B3/B4/F9 | — |

### R 双端构建与分发链（跨分支）

B1 Godot CI（09-20）· B2 Android 签名 + AAB + Play 内测上传（10-25）· SGODOT-35 16 KB（10-25）· B4 iOS 导出链正规化 + TestFlight 首包（10-25，合并 SGODOT-11；先用现有账号跑通，SSL-A6 到手换签名）· B7 发布流程与版本管理（10-25）· B8 演示构建：投资人内测包 + 预置好友 / 动态 / 群 / 语音房 + 社交主线剧本彩排 + `demo-*` tag（10-30）。

### Z Won't（Demo 期，08-30 §6.4）

支付 / IAP、任何小游戏、AIGC、热更、后台定位、多端完整漫游、语音消息；中国大陆发行地图供应商；Apple Declared Age Range / Play Age Signals 二期。

---

## 4. 估算与人力（这是排期成立的前提）

| 工作流 | 人周（08-30 §6.1） |
|---|---|
| A 客户端基建 | 3.5 |
| B 客户端功能 | 10.5 |
| C 原生插件 | 4–5 |
| D 后端 | 13.5–18.5 |
| E 合规与联调 | 2 |
| **合计** | **33.5–39.5 人周 ≈ 170–200 人天** |

| 场景（§6.2） | 配置 | 8 周结果 |
|---|---|---|
| A（推荐） | 5 人：2 Godot + 1 原生插件 + 2 后端 | 全量范围（含语音房）达标 |
| B | 4 人：2 Godot（兼原生插件）+ 2 后端 | 达标，但砍：评论、Space 3D、语音房只留最小上下麦 |
| C | 2–3 人 | 8 周只能到 M2 + IM（Tinode 路线）；全量需 12–16 周 |

**单人做不到 8 周**：单人 8 周 ≈ 40 人天，只够 A 全部 + B1 / B4 / B5 + D0–D2 + Tinode 路线 IM 的一半。人力决策 = SSLAUNCH F1，**立即**。本文的截止日期按场景 A/B 写；场景 C 下按 §5 裁剪并把 M3 / M4 各顺延 4 周。

---

## 5. 裁剪顺序（08-30 §6.4 MoSCoW）

- **Must**：登录三件套、IM（1v1 + 群，文本 + 图片）、feed（图文 + 点赞）、地图（好友位置 + 3D 角色）、我的主页 + 设置 + 删号、举报 / 拉黑 / 审核管线、en-US、推送。
- **Should**：语音房（LiveKit 基础能力）、feed 一级评论、zh-CN。
- **Could**：Space 3D 个人空间、系统分享、深链、应用内评分。
- **Won't**：见 Z。

先裁 Could → Should（评论 → zh-CN → 语音房只留最小上下麦）→ IM 切 Tinode（省 2–3 周）。Must 与合规硬化不动。

---

## 6. 与 SSLAUNCH 的接口

开发消费：SSL-F1 人力（决定场景）· F2 语音房（B6 / C4 / D5 开工前提）· F3 语言范围（A2）· F4 IM 路线（D3，W2 末）· F5 Space 3D（B4）· B1 品牌（E6）· B2 / B3 条款 URL（R3 / E1）· B4 删号页（D2）· B8 权限文案（A3）· C6 举报类型（E1）· F9 COPPA 需求稿（R2）· D1 Firebase（B1 / D2 / D7）· D2 LiveKit（C4 / D5）· D3 Mapbox 新 token · D4 Cloudflare R2（D4 / D9）· D5 AWS / 云决策（D1 / D6）· D6 OpenAI（D6）· D7 Sentry（E4）· D8 PostHog（E5）· A6 / A7 / A9 商店账号与密钥（R 模块）· G1 Nacos 抢救（D1 硬前置）· E10 翻译 PO（A2）。

开发交付：E3 数据流说明 → SSL-E1；A3 权限清单 / manifest 核查 → SSL-E2 / E3；A2 导出 PO → SSL-E10；R 模块可装机包 + 截图 → SSL-A8 / E8；B8 演示构建 → SSL-E11 / E12；E7 测试账号与审核机制说明 → SSL-E9。

---

## 7. 风险（08-30 §8 + 本轮）

| 风险 | 影响 | 对策 |
|---|---|---|
| 人力未定 | 33–39 人周没有可信排期 | SSL-F1 立即拍板；场景 C 下按 §5 裁并顺延 |
| D0 后端栈悬而未决 | D1–D7 无法开工，M1 落空 | 09-13 前定；Java 维护人力不可得就统一 Node 并重估 WS-D |
| Nacos 配置流失 | 限流阈值 / 密钥 / 业务参数失传，Java 复用路线崩 | SSL-G1 本周导出 |
| IM 服务端 4–6 人周 | 关键路径最长 | W2 末 F4 定案；后端 <2 FTE 切 Tinode |
| Godot 文本输入体验 | 聊天页手感直接影响融资观感 | A5 专项，每里程碑真机回归 |
| iOS 生命周期通知回归 | IM 前后台断连 | A6 第 1 周验证，插件层兜底 |
| target API 36 窗口 | 2026-10 / 11 上架按新 App 口径 | A3 第 1 周核实 targetSdk 并真机回归 |
| 品牌 / 账号迟定 | E6 卡住 → TestFlight 首包临时 ID 白跑 | 占位 `com.sensenjoy.*`，接受一次重传 |
| 语音成本 | 按 MAU 年 20–30 万美元（Plane 项目方向讨论记录） | SSL-F2 先算账；Should 档可裁到最小上下麦 |
| 两分支合并 | 农场分支改了地图为受限模式、路由、HUD | 本分支地图保持自由漫游；合并时以本分支路由壳为宿主，农场作为一个实例页面接入 |

---

## 8. Plane 映射（SGODOT）

模块：A 客户端基建 · B 客户端功能 · C 原生插件 · D 后端 · E 合规与联调 · R 双端构建与分发链 · X 工程债 · Z Won't · **F 街角四季 MVP（并行分支，本分支不做）**。父卡 SGODOT-48（合规硬化总览）、SGODOT-49（发布链总览）。

| 本文 | Plane | 本文 | Plane | 本文 | Plane |
|---|---|---|---|---|---|
| A1 架构骨架 | SGODOT-88 | B1 登录 + Firebase | SGODOT-67 | C1 SiwA / Google 插件 | SGODOT-96 |
| A2 i18n | SGODOT-78 | B2 IM UI | SGODOT-91 | C2 FCM / APNs 插件 | SGODOT-81 |
| A3 打包合规 | SGODOT-59 / 60 / 35 | B3 feed | SGODOT-92 | C3 Photo Picker | SGODOT-97 |
| A5 输入与键盘 | SGODOT-89 | B4 主页 + 设置 | SGODOT-93 | C4 LiveKit 桥 | SGODOT-98 |
| A6 iOS 生命周期 | SGODOT-90 | B5 地图整合 | SGODOT-94 | C5 iOS 桥 / AAR | SGODOT-71 / 6 / 10 |
| A7 tokens | SGODOT-19 | B6 语音房 UI | SGODOT-80 | D0 后端栈决策 | SGODOT-99 |
| R1 删号入口 | SGODOT-56 | B7 avatar 接入 | SGODOT-95 | D1 部署 + 去 Nacos | SGODOT-100 |
| R2 年龄门 | SGODOT-57 | E1 UGC 四件套 | SGODOT-61 | D2 账号服务 | SGODOT-76 |
| R3 条款同意 | SGODOT-58 | E2 数据卫生 | SGODOT-62 | D3 IM 服务端 | SGODOT-82 |
| 发布链 B1 CI | SGODOT-68 | E3 数据流说明 | SGODOT-63 | D4 feed API + R2 | SGODOT-101 |
| 发布链 B2 AAB | SGODOT-69 | E4 Sentry | SGODOT-64 | D5 语音 token + 信令 | SGODOT-102 |
| 发布链 B4 TestFlight | SGODOT-70（含 11） | E5 PostHog | SGODOT-65 | D6 审核管线 + 工单 | SGODOT-103 |
| 发布链 B7 发布流程 | SGODOT-72 | E6 应用身份 | SGODOT-66 | D7 推送服务 | SGODOT-104 |
| 发布链 B8 演示构建 | SGODOT-73 | E7 M4 联调 | SGODOT-105 | D8 / D9 环境 / 备份 | SGODOT-74 / 75 |
| | | | | D10 云迁移 / Mapbox token | SGODOT-77 / 14 |

已有卡归属：**B** ← 地图 PoC 与 09-04 Demo 基线 3 5 7 8 9 16 17 18 20；**X** ← 1 2 12 13 79；**Z** ← 85 86 87 15 22；**F**（农场，本分支不做）← 21 23 24 25 26 27 28 29 30 31 32 33 34 36 37 38 39 40–47 4 50–55 83 84。

标签：`阻塞提审` · `依赖SSLAUNCH` · `交付SSLAUNCH` · `待决策`（D0 SGODOT-99、D3 SGODOT-82、B6 SGODOT-80）· `条件项` · `工程债`。
