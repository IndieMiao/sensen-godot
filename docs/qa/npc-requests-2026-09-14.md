# SGODOT-114 NPC 与邻里委托验证

日期：2026-09-14。分支：`farm-dev`。领域版本 `18`，存档结构版本 `1`。
服务端与客户端专项、原生布局及模拟器操作检查已完成；记录至模拟器农场版本 `32`。
未发布，未修改 Plane 状态，未完成自然玩家观察。规则见[NPC 与邻里委托](../product/npc-requests-2026-09-14.md)。

## 已实现范围

- 复用三名既有居民，补充身份与性格简介、需求原因和交付回应；统一委托页可比较三份当前需求、
  持有量、金币和已有街边成果，详情页提供与状态匹配的主操作。
- 每槽独立保存接取状态，地图只追踪一份。切换或取消追踪不放弃；放弃保留当前需求，
  换单轮换下一份，两者都清除本次接取与追踪并推进序号，不扣物、不发奖。
- 交付必须已接取且材料足够，通过现有 NPC 或餐桌场景完成；背包委托页只导航，不直接交付。
  成本规范化为物品 ID，支持跨堆及暂存消费，保留工程预留、场景陈列物和永久装备。
- 原六份委托顺序与奖励保留，追加蔬菜汤 1 份/24 金币、铜矿石 3 份/18 金币、
  铜箍木箱 1 件/26 金币。新需求复用已有街边成果，不增加重复友情奖励，不消耗人物料理效果次数。
- 缺盐、缺铜接续矿坑；原料齐全后接厨房或工作台，已有成品或可收回手作品不重复要求制作。
  `timber_only:true` 仅用于修缮师，可从混合、铜矿或木箱需求直接回到纯木料工作；已是纯木料时拒绝无效换单。
- `last_completed` 保存每槽最近完成的稳定委托 ID、居民、准确序号、实际扣除、金币和成果阶段。
  读取可恢复记录，重放不重复发奖或播放完成反馈；蔬菜汤具有对应实体表现。
- 旧 17 版有效追踪投影为已接取，背包、装备、人物效果、矿坑及历史命令结果保持；
  不从旧序号推导完成次数、关系点或额外奖励。所有小馆委托操作统一要求首次共餐。

## 已完成验证

| 范围 | 已记录结果 | 证据或限制 |
| --- | --- | --- |
| 服务端全量，含 PostgreSQL | 41 文件、659 项通过，174.86 秒 | `node server/tools/test_requests_isolated.mjs`；类型检查与差异空白检查通过 |
| Godot 广泛回归 | 562 项；1 运行错误、6 断言失败，分布在两处旧测试；29 个孤立节点提示 | [client-tests.log](../../output/requests-emulator-2026-09-14/client-tests.log)，不记为全量全绿 |
| 合同更新后相关回归 | 238 项；0 断言失败，仍有 1 旧测试运行错误 | [focused-tests.log](../../output/requests-emulator-2026-09-14/focused-tests.log) |
| 最终四套专项 | 41 项通过；0 错误/失败/跳过/孤立节点 | [final-focused-tests.log](../../output/requests-emulator-2026-09-14/final-focused-tests.log) |
| 最终原生中英文布局 | 84 组通过，错误列表为空 | 360x640、390x844、960x720，已包含详情主按钮与过期状态修正 |
| Android 模拟器实际操作 | 17 项检查通过 | [playtest.json](../../output/requests-emulator-2026-09-14/playtest.json)，包含接取、切换、放弃、实际交付、矿坑补料和恢复 |
| 接取状态冷启动 | 通过，版本保持 `9` | 请求、追踪、背包与人物状态深比较一致，启动标识改变 |
| 交付记录冷启动 | 通过，版本保持 `32` | 请求记录、钱包、背包深比较一致，查看历史不重复领奖 |

服务端验证包括接取后切换追踪、取消与放弃的区别、跨堆与暂存交付、缺料不改变接取状态、
制作后重试先前拒绝请求仍返回原拒绝、重复交付只结算一次、纯木料恢复，以及 17 版迁移和存储重启。
使用独立测试库 `sensen_farm_journey_requests_test_20260914`，与运行中的试玩服务分离。

广泛客户端回归的两处旧测试仍假设“物品足够即可交付”，已按独立接取合同修正。
238 项回归剩余问题来自旧测试假设过期请求不会发出恢复 GET，最终专项已更新并通过。
最终检查覆盖过期确认刷新后退出旧确认、详情页主操作，以及非木料委托不再误称“交付木料”。
29 个孤立节点提示与 `output/localization-qa-20260913-investor/native-tests.log` 的原农场套件基线一致；
本轮未定位或消除该旧提示，不把后续专项通过写成已重跑全部 562 项通过。

原生报告为 [report.json](../../output/localization-qa-requests-20260914/project/output/requests-visual/report.json)，
`passed=true`，`natural_player_verified=false`，`physical_device_verified=false`。
图像使用合成委托和库存状态，证明指定界面可渲染和操作，不代表自然获得材料或玩家理解需求。

## 模拟器操作

已在 `emulator-5560` 安装独立应用 `com.sensen.journeyrequestsqa` 并完成实际操作。
本地服务 `3153`，记录时 PID `4018`；数据库
`sensen_farm_journey_requests_emulator_20260914`。
APK 路径：`output/requests-emulator-2026-09-14/sensen-requests-local-qa-2026-09-14.apk`。
最终 APK SHA-256：`4824273371dd9532d522afea7d5ffb91c85115fc1c6f25f81d9159b62efed740`。

| 版本 | 实际操作与核对结果 |
| --- | --- |
| 普通新档 `v0-v1` | 正常建场；在委托页接取苗圃需求，页面保持打开，接取并追踪成功 |
| `materials` 夹具 `v2` | 人工提供材料与解锁，三份当前需求分别为生菜、蔬菜汤、铜矿；未将这些补给计为自然获得 |
| `v3-v6` | 先后接苗圃与小馆；停止小馆追踪后仍已接取，再改追苗圃，两份接取独立保存 |
| `v7-v9` | 放弃小馆使其序号加一，变体、物品和金币保持；重新接取小馆，再接修缮师，三份同时已接；冷启动保持 `v9` |
| `v10-v12` | 街区与修缮师交谈后交铜矿 3 份，实得 18 金币；到餐桌交汤 1 份，实得 24 金币，出现汤模型及主理人回应 |
| `shortage` 夹具 `v13` | 汤缺盐、木箱缺铜矿与成品，其他食材和基础材料足够；完整修改前后快照保留 |
| `v14-v16` | 接取汤与木箱委托；按缺料目标进入矿坑 |
| `v17-v22` | 实际点击六块矿石，获得本轮所需铜矿石 3、岩盐 1 |
| `v23-v26` | 离矿跟随目标到工作台；制作木箱实际扣木料 2、石料 1、铜矿石 3；与修缮师交谈并交木箱 1 件，实得 26 金币 |
| `v27-v28` | 用本轮采得岩盐烹调蔬菜汤，再交汤 1 份，实得 24 金币 |
| `v29-v32` | 修缮师正常换单到铜矿并接取；详情页确认“纯木料工作”后直接切回木料，背包和钱包不变 |
| 最终冷启动 `v32` | 启动标识改变，请求记录、钱包、背包保持；打开小馆最近交付，显示正确历史且没有重复奖励 |

两次恢复报告为 [cold-start.json](../../output/requests-emulator-2026-09-14/cold-start.json)
与 [history-cold-start.json](../../output/requests-emulator-2026-09-14/history-cold-start.json)，均为 `passed=true`。
动作证据位于 `output/requests-emulator-2026-09-14/actions/`，按同名前缀保留操作前后状态、
动作元数据与截图；汇总 [playtest.json](../../output/requests-emulator-2026-09-14/playtest.json)
明确标注 `materials v2`、`shortage v13` 和 `physical_device_tested=false`。

关键截图：[委托比较](../../output/requests-emulator-2026-09-14/screenshots/requests.png)、
[最近交付](../../output/requests-emulator-2026-09-14/screenshots/delivery-history.png)、
[蔬菜汤交付](../../output/requests-emulator-2026-09-14/screenshots/soup-delivery.png)。

夹具入口为 `server/tools/prepare_requests_qa.ts materials|shortage`，要求明确 `FARM_ID`，
固定只访问上述独立模拟器库，先保存完整农场行备份再递增版本。
`materials` 提供可比较和交付的人工库存；`shortage` 的汤作物与木箱基础材料足够，仅缺盐和铜，
用于验证真实导航、开采及制作接续。夹具不得写成自然玩家获得或成长成果。

## 验收边界

用户要求继续 114 前后的 113 真机安装与 15 项实测已另行完成；真机当前 113 应用、存档和
`3152` 服务保留。初轮 114 使用 Godot 与模拟器；随后按用户要求单独安装 114 R2 真机包，见下节。未发布线上版本。
自然玩家是否能理解至少两份不同需求并自主决定先帮助谁、如何分配矿物和料理，仍需单独观察；
自动检查和开发者按流程操作不能替代这项验收，也不自动将 Plane 卡片标为完成。

## R2 真机安装与矿坑模型入口

2026-09-14 用户要求安装 114，并移除农场矿坑入口的悬浮图标。已删除入口按钮，
点击范围根据矿口拱门和轨道模型实际包围盒投影生成，保留最小 44px 触区与界面区域裁切。
点击后沿用走近、入矿的既有流程；访客、弹窗、离线与忙碌守卫保持。此为客户端交互修改，
不改变领域版本、矿石抽签或存档格式。

- Godot 农场与矿坑 75 项检查无错误或失败；新增两项覆盖不同缩放的模型命中、无图标、
  走近行为和访客/弹窗/隐藏守卫。原农场套件仍有既有 29 个孤立节点提示，进程退出码 101。
- 模拟器先覆盖安装 R2，确认入口模型可见且不存在 `MineEntranceButton`；实际点模型，
  存档从 `v32` 进入第一层至 `v33`，返回农场至 `v34`。
- vivo V2509A（`10AFAF162200319`）安装“街角四季·委托测试”，包名
  `com.sensen.journeyrequestsqa`，版本 `0.7.0-requests-local.20260914.r2` / `2026091409`。
- 真机使用独立正常新档，`v0` 建场后实际点模型进入矿坑 `v1`，返回农场 `v2`，
  接取苗圃委托 `v3`，停止追踪 `v4`；已接取状态保留。当前停在委托页。
- 真机启动、联网、模型入口和委托基本操作检查通过，应用日志采样无 GDScript 错误或崩溃。
  这次安装检查不代替上文完整委托交付链的真机回归。

独立服务为 `http://127.0.0.1:3154/v1`，PID `46905`，数据库
`sensen_farm_journey_requests_device_20260914`；试玩需要 USB 与本机服务运行，重新连接时使用
`adb -s 10AFAF162200319 reverse tcp:3154 tcp:3154`。未复制或覆盖 113 的身份与进度。

APK：`output/requests-device-2026-09-14/sensen-requests-local-qa-2026-09-14-r2.apk`。
SHA-256：`872ce9604615a4d31ad5d3ff69bb19a07631170af25187a3133a1a9a2c5dc8e2`。
验证与动作证据在 `output/requests-device-2026-09-14/`，包括 `entrance-tests.log`、
`emulator-entry.json`、`model-entry.json`、`install-check.json`、`app-logcat.txt`。
截图：[农场无图标入口](../../output/requests-device-2026-09-14/screenshots/farm-model-entrance.png)、
[真机委托页](../../output/requests-device-2026-09-14/screenshots/requests.png)。
