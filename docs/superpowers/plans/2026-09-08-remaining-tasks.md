# 海外社交主线：后续任务清单与卡点标注（2026-09-08 快照）

- 基线：分支 `feat/next-feature` @ `c33f6ec`，已推 origin；自 `a7426ef` 起 48 个提交
- 上游：`2026-09-07-dev-task-breakdown.md`（WBS 与 Plane 映射）；本文只回答「还剩什么、卡在哪、能先做什么」
- 状态口径：Plane SGODOT 卡片状态 + 各任务单「未做 / 后续」节，逐条核对于 2026-09-08
- 图例：✅ 已完成 ｜ 🟢 不卡，可直接开工 ｜ 🟡 部分可做，剩余等外部输入 ｜ 🔴 硬卡，外部输入未到 ｜ ⚪ 待决策 / 条件项
- 2026-09-08 晚更新：无卡点的八项已全部开工，完成态见 §0 各行

---

## 0. 一页总览

| 状态 | 任务 | Plane | 卡点（括号内为 SSLAUNCH 卡片当前状态） |
|---|---|---|---|
| ✅ | B4 收尾：关注者 / 关注中列表页、用户主页头像、avatar 入口 | SGODOT-93 | 09-08 完成（Done） |
| ✅ | B2 收尾：会话列表头像、群聊实时「N 人已读」 | SGODOT-91 | 09-08 完成（Done） |
| 🟡 | B7 avatar 装扮上服务端 + 主页 / 资料页接入 | SGODOT-95 | 接入与同步 09-08 完成；剩部件池扩充（要资产管线） |
| 🟡 | **B5 地图主页整合**（Mapbox 垫底 + 透明层 + 好友位置 + 3D 角色 + HUD） | SGODOT-94 | 第一刀 09-08 完成（`2026-09-08-b5-map-home.md`）：服务端位置接口、地图 Tab、好友角色、iOS 定位桥；剩 HUD 好友列表、Android 验证、C5 决策；新 token 等 SSLAUNCH D3 |
| 🟡 | 发布链 B1 Godot CI（headless gdUnit4 + server vitest + APK 产物） | SGODOT-68 | 工作流已上（`.github/workflows/godot.yml`）；headless 跳过 8 个渲染用例；等最新一轮绿与 APK 任务首跑 |
| ✅ | 发布链 B7 发布流程与版本管理（tag / changelog / 回滚） | SGODOT-72 | 09-08 完成：`docs/release-process.md` + `tools/release/manifest.sh` |
| 🟡 | A7 GameUi / DesignTokens 单一来源 | SGODOT-19 | 09-08：GameUi 色板 / 字号 / 触控尺寸全部指向 `DesignTokens.UI_*` 并有测试锁；剩散落的 `add_theme_*_override` 字面值收口 |
| ✅ | Q6 测试退出 ObjectDB 警告 | SGODOT-79 | 09-08：全量 --verbose 不复现；CI 加守卫（Done） |
| 🟡 | 语音房线 C4 LiveKit 桥 → D5 token 签发 → B6 UI | SGODOT-98 / 102 / 80 | 技术不卡（自托管 LiveKit 即可开发）；**是否进 Demo 一期 = SSLAUNCH F2（Backlog）未拍板**，云 key 等 D2（Backlog） |
| 🟡 | D8 环境分离 prod / qa / dev | SGODOT-74 | dev / qa 本机可做；prod 一套等 D1 部署 |
| 🟡 | E2 位置与聊天数据卫生 | SGODOT-62 | 日志 scrub 可做；非好友降精度等 B5 位置 API；Sentry / PostHog scrub 等 E4 / E5 |
| 🟡 | R4 iOS Privacy Manifest + purpose strings + 加密申报 | SGODOT-59 | 自有 SDK 申报可写；purpose strings 文案等 SSLAUNCH B8（Backlog）；加密申报口径等 E6（Backlog） |
| 🟡 | R5 Android 权限审计 + targetSdk 36 + 16 KB | SGODOT-60 / 35 | 清单审计可做；**回归缺 Android 设备** |
| 🟡 | C3 收尾：Android 真机验证、template_release iOS 静态库 | SGODOT-97 | 缺 Android 设备；release 库随 SGODOT-70 |
| 🟡 | C1 Sign in with Apple / Google 原生插件 | SGODOT-96 | 正式 client ID / Services ID 等 SSLAUNCH A9（Backlog）；开发期可用 dev Firebase 项目自建 OAuth client + 现有 Apple 账号 + 占位 Bundle ID 先打通，接受一次重配 |
| 🟡 | C2 FCM / APNs 推送插件 | SGODOT-81 | **APNs .p8 与正式 Bundle ID 等 A9（Backlog）**；Android FCM 侧用 dev 项目可先做 |
| 🟡 | D7 推送服务（Firebase Admin 发 FCM + APNs） | SGODOT-104 | SSLAUNCH D1 项目已 Done，缺 Admin 服务账号 JSON 的交付与存放（D9 密钥台账 Backlog）；dev 项目可自取先跑通 |
| 🟡 | D1 部署基建（海外区域 + Redis + 环境分离） | SGODOT-100 | **云决策 = SSLAUNCH D5（Backlog）**；compose 加 Redis / 健康检查可在香港 ECS 先演练 |
| 🟡 | D4 收尾：R2 真桶 | SGODOT-101 | 代码已通（SigV4 预签名 + 本地存储替代），只差 Cloudflare 账号 = SSLAUNCH D4（Backlog），换四个 env |
| 🟡 | D6 收尾：图片审核 Rekognition、PhotoDNA / Safer、OpenAI key | SGODOT-103 | Rekognition 等 D5（Backlog）；PhotoDNA 等 SSLAUNCH C1（Todo）；OpenAI key 等 D6（Backlog），代码已在，env 即通 |
| 🟡 | D2 收尾：Apple revocation、Web 删号页对接 | SGODOT-76 | revocation 等 A6（Todo）；Web 删号页由 SSLAUNCH B4（Backlog）出，服务端接口已在 |
| 🟡 | R1 删号双入口收尾（Web 入口） | SGODOT-56 | 同上 SSLAUNCH B4 |
| 🟡 | E1 UGC 四件套收尾 | SGODOT-61 | EULA 零容忍强制同意等 B3（Backlog）；公开联系方式邮箱等 C6（Backlog，按钮已在、等 `LegalLinks.SUPPORT_EMAIL`）；语音房入口等 B6 |
| 🟡 | E4 Sentry 崩溃上报 | SGODOT-64 | 接入代码可先写，DSN 走 env；org = SSLAUNCH D7（Backlog） |
| 🟡 | E5 PostHog 埋点 | SGODOT-65 | 事件口径与接入可先写；项目 = SSLAUNCH D8（Backlog） |
| 🔴 | E6 / R11 应用身份定版（包名 / Bundle ID / 图标 / 启动图） | SGODOT-66 | **品牌决策 = SSLAUNCH B1（Todo）**；卡整条 R 发布链 |
| 🔴 | 发布链 B2 Android 签名 + AAB + Play 内测 | SGODOT-69 | Play 账号 A7（Backlog）+ 品牌 B1（Todo） |
| 🔴 | 发布链 B4 iOS 导出链正规化 + TestFlight 首包 | SGODOT-70 | Apple 账号资格 A6（Todo）+ 品牌 B1；导出链正规化本身可先做（见 §3） |
| 🔴 | 发布链 B8 演示构建 | SGODOT-73 | 剧本 E11（Backlog）+ D1 部署 + 预置账号 |
| 🔴 | E7 M4 联调 / 可提审 checklist | SGODOT-105 | 依赖全部 |
| 🔴 | D9 备份策略（R2 异地副本） | SGODOT-75 | SSLAUNCH D4 |
| ⚪ | C5 iOS 地图桥：UDP 回环加固 vs 迁 GDExtension | SGODOT-71 / 6 / 10 | 内部技术决策，B5 开工时定；C3 已用 GDExtension 打通 iOS 链，有先例 |
| ⚪ | D10 云迁移预案；Mapbox token 独立化 | SGODOT-77 / 14 | 条件项；等 D5 / D3 |

---

## 1. 本轮已完成（供对照，不再列入后续）

| 模块 | 已完成 | Plane |
|---|---|---|
| A | A1 架构骨架、A2 i18n（170 键 en / zh_CN 全译）、A6 iOS 生命周期真机结论、A5 键盘避让（SHIFT / SHRINK 两模式，真机帧稳） | 88 / 78 / 90 / 89 |
| B | B1 登录页 + Firebase REST；B2 会话列表 / 单聊 / 群聊 / 图片消息 / 已读回执 / 长按举报拉黑撤回；B3 时间线 / 图文发布 / 点赞 / 一级评论 / 举报；B4 资料页 / 编辑 / 设置 / 首启合规流 / 删号 / 用户主页 / 动态详情 / 「公开我关注的人」 | 67 / 91 / 92 / 93 |
| C | C3 Photo Picker：统一入口 + iOS PHPicker GDExtension（真机 `picker: native`）+ Android 插件 AAR + 桌面文件框 | 97 |
| D | D0 后端统一 Node；D2 账号服务；D3 IM 核心 + WS 网关 + 成员 / 对方已读 / 消息举报（真机 1v1 双向通）；D4 资料 / 关注 / feed / 图片直传（R2 SigV4 + 本地存储）；D6 前置过滤 / 举报 / 拉黑 / 封禁 / 管理队列 / ≥3 举报自动撤回；D8 QA 账号种子脚本与说明 | 99 / 76 / 82 / 101 / 103 / 74 |
| E / R | R2 年龄门、R3 条款同意、R8 / E3 数据流说明；E1 feed / IM / 资料页的举报与拉黑 | 57 / 58 / 63 / 61 |
| QA | 步行器 `qa_flow.gd`（social / login 流、PHOTO / PROFILE / PICK / WATCH 钩子）、iPhone 13 真机链路（代理中继、本地网络权限键）、证据目录 `~/Downloads/sensen-qa-2026-09-07/e2e/` | — |

里程碑对照：M1（09-20）客户端定型 ✅、登录 → 资料 ✅（本机 / 香港，海外云未部署 ⛔ D1）；M2（10-04）登录 + 主页 + feed 只读 ✅、IM alpha ✅、审核管线 ✅、R2 ⛔ 真桶、LiveKit spike ⛔ 未开工；M3（10-18）IM 群聊 / 图片 / 举报拉黑 ✅、离线推送 ⛔ C2 / D7、feed 发布 ✅、语音房 ⛔、i18n ✅。

---

## 2. 不被卡、建议开工顺序

按「先小后大、先铺路再整合」排：

1. **B4 + B2 收尾（1–2 天）**：关注者 / 关注中列表页（服务端 `followers` / `following` 接口已在，只缺页面）、用户主页与会话列表头像（头像图走 `/v1/files/<key>` + `ImageCache`）、资料页 avatar 入口占位。
2. **B7 avatar 装扮上服务端（2 天）**：`users/me/profile` 加 `avatar_config`，主页 / 用户主页渲染 3D 头像；为 B5 的「好友 3D 角色」铺路。
3. **B5 地图主页整合（2.5 人周，最大不卡块）**：把 09-04 Demo 基线（`scenes/map_poc` + Android Kotlin 插件 + iOS UDP 桥）接进 `AppRoutes` 壳，进出页显隐原生 MapView；服务端新写好友位置上报 / 查询（When-In-Use、非好友降精度 → 顺手做 E2 那一半）；HUD；C5 决策在此时一并定。
4. **发布链 B1 Godot CI + B7 发布流程（1–2 天，可与上并行）**：GitHub Actions 跑 `tools/run_tests.sh` 与 `server` vitest / typecheck；tag 规范与 release-manifest 文档。
5. **A7 tokens、R5 清单审计（无设备部分）、Q6（各 ≤1 天）**。
6. **语音房线 C4 → D5 → B6（3–4 人周）**：自托管 LiveKit（docker）即可开发，桌面 godot-livekit spike 先通；**建议 SSLAUNCH F2 拍板后再投**，否则可能白做。
7. **可先写代码、等 env 的项**：E4 Sentry 接入、E5 PostHog 事件口径、D7 服务端发送链（dev 项目服务账号）、C2 Android FCM 侧、C1 开发期打通（占位 Bundle ID）。

---

## 3. 硬卡明细（按 SSLAUNCH 输入归类）

| SSLAUNCH 输入 | 状态 | 卡住的开发项 | 到手后要做的事 |
|---|---|---|---|
| **B1 品牌 / 商店名 / 域名** | Todo | E6 应用身份（SGODOT-66）→ 发布链 69 / 70 / 73 → E7 | 定包名 / Bundle ID / 显示名 / 图标 / 启动图；替换导出预设；`LegalLinks` 域名 |
| **A9 开发者账号配置项** | Backlog | C1（96）正式 client ID；C2（81）APNs .p8 | 填 `config/firebase.json` 的 iOS / Android client；APNs key 进服务端 env |
| A6 Apple 账号资格 | Todo | 发布链 B4 TestFlight（70）；D2 Apple revocation（76） | 换签名与 Team；revocation 队列上线 |
| A7 Play 账号资格 | Backlog | 发布链 B2 AAB（69） | upload keystore、Play 内测轨道 |
| **D5 云托管决策 / AWS** | Backlog | D1 部署（100）；D6 Rekognition（103）；D10（77） | compose 迁海外区域 + Redis；Rekognition 接图片审核位 |
| D4 Cloudflare（R2 / Pages / DNS） | Backlog | D4 真桶（101）；D9 备份（75）；合规页托管 | 换 `R2_*` 四个 env，关掉 `UPLOAD_LOCAL_DIR` |
| D9 密钥台账 | Backlog | D7 服务账号 JSON 交付（104） | 服务端 env 挂 `FIREBASE_SERVICE_ACCOUNT` |
| D2 LiveKit Cloud | Backlog | D5 正式 key（102）、B6 | 自托管 → 云，只换 URL / key |
| D3 Mapbox 新 token | Backlog | B5 正式 token；SGODOT-14 | 换 token，遥测申报 |
| D6 OpenAI / D7 Sentry / D8 PostHog | Backlog | D6 文本过滤开启（103）；E4（64）；E5（65） | 各填一个 env |
| B3 ToS / EULA、B2 隐私政策 | Backlog | E1 EULA 零容忍强制同意（61）；R3 正式 URL | `LegalLinks` 换正式 URL；同意版本号 +1 |
| B4 Web 删号页 | Backlog | R1（56）/ D2（76）Web 入口 | 页面用 Firebase JS 登录后 `POST /v1/account/delete` |
| B8 权限用途文案 | Backlog | R4（59）purpose strings | 填 iOS plist / Android 前台服务声明 |
| C6 举报类型清单 + 公开联系方式 | Backlog | E1（61）联系方式按钮 | 填 `LegalLinks.SUPPORT_EMAIL`；举报类型枚举对齐 |
| SSLAUNCH C1 PhotoDNA / Safer | Todo | D6 CSAM 接入位（103） | 图片上传后异步哈希比对 |
| E11 融资 Demo 剧本 | Backlog | 发布链 B8 演示构建（73） | 预置账号 / 好友 / 动态 / 群 |
| F1 人力 | Todo | 决定场景 A / B / C，决定 M3 / M4 是否顺延 | — |
| F2 语音房进 Demo 一期？ | Backlog | C4 / D5 / B6 是否开工 | — |
| F4 IM 自建 vs Tinode | Backlog | **已由实现事实决定：自建 D3 真机跑通，建议 SSLAUNCH 直接关闭 F4**，SGODOT-82 摘「待决策」 | — |
| F5 Space 3D | Backlog | B4 Could 项 | — |

---

## 4. 非 SSLAUNCH 的卡点（设备 / 人手 / 发布前清单）

- **无 Android 设备**：C3 Android Photo Picker 真机验证、R5 权限回归、16 KB 对齐验证、B5 Android 侧回归。到手前这几项只能停在「编译通过」。
- **需要人手在 iPhone 上操作**：`SENSEN_QA_PICK=1` 流程弹出 PHPicker 后要真人选图才能截 `photos_picked`；iPhone 镜像不显示键盘、手机在用时镜像断开。
- **发布前必须清掉的开发期配置**（记在发布链 SGODOT-70）：导出预设 `additional_plist_content` 里的 `NSAllowsLocalNetworking` 与 `NSLocalNetworkUsageDescription`；`native/photo_picker` 的 `template_release` iOS 静态库尚未构建。
- **本机常驻进程**：本地服务 3101（本地图片存储模式）与代理中继 7891 仍在跑，重启机器后按 `2026-09-07-qa-flow-device.md` §6 重开。

---

## 5. Plane 同步动作（2026-09-08 已做）

- 被外部卡住的卡统一加 `依赖SSLAUNCH`，并在评论里写明「卡点 = SSLAUNCH 编号 + 可先做的部分」，指回本文。
- 语音房线 SGODOT-98 / 102 加 `待决策`（F2）；SGODOT-82 摘 `待决策`（F4 已由实现决定）。
- 未改任何卡的状态：In Progress 卡保持，直到收尾项做完再置 Done。
