# SGODOT-113 人物属性与装备验证

日期：2026-09-14。分支：`farm-dev`。领域版本 `17`，存档结构版本 `1`。
本文记录至模拟器农场版本 `28`，区分已实现规则、自动检查与开发者操作。
满包模拟器流程、重启恢复及最终截图已完成；未发布，未修改 Plane 状态，未完成自然玩家观察。
规则见[人物属性与装备](https://github.com/IndieMiao/sensen-godot/blob/25b7a8a6e0574f9b0c4c97f480238e98d5d9985c/docs/product/character-equipment-2026-09-14.md)。

## 已实现范围

- 人物页展示农具范围、采集加成、开采石料加成、制作节料，并区分基础、装备和料理来源。
- 工具位与配件位可选择、比较、装备和卸下；铜镐、采集手套、工匠围裙在工作台以真实材料制作，
  每种最多一件，不自动换装，不可丢弃。已有基础农具与整畦农具继续使用原库存实例。
- 沙拉、岩盐蔬菜汤、洋甘菊茶分别作用于随后三次有效采集、采矿、工作台制作。
  装备与料理相加，同类效果未结束时不能重复食用；茶只有实际额外节省材料时才扣次数。
- 采集加成进入实际材料收益；矿坑只增加石料，额外矿物抽签不变；制作节省只作用于基础材料，
  每项至少保留一份，铜矿石与岩盐不打折。失败、满包与历史请求重放不重复扣料或扣效果次数。
- 旧背包仍是库存权威；迁移补空人物状态和配件位，不补发新装备。成功命令的事件记录实际节省，
  历史重放保留原结果，普通读取不重复发送事件。

## 自动验证

| 范围 | 结果 | 证据与限制 |
| --- | --- | --- |
| 服务端全量，含 PostgreSQL | 40 文件、614 项通过 | `node server/tools/test_character_isolated.mjs`，最终运行 183.07 秒；类型检查与差异空白检查通过 |
| Godot 广泛回归 | 548 项，0 错误、1 失败、29 个孤立节点提示 | [client-tests.log](../../output/character-emulator-2026-09-14/client-tests.log)，不能记为全量全绿 |
| 修复后客户端专项 | 89 项通过，0 错误/失败/跳过/孤立节点 | [focused-tests.log](../../output/character-emulator-2026-09-14/focused-tests.log) |
| 原生中英文布局 | 72 组，`passed=true`，错误列表为空 | 360x640、390x844、960x720；合成装备与料理状态 |
| 模拟器冷启动恢复 | 通过，版本保持 `18` | `bag`、`character`、`mine` 深比较一致，启动标识已变化 |
| 满包边界与恢复 | 服务端、夹具及模拟器触控通过 | 失败保留效果 3 次，准确丢弃 99 铜矿后，同一矿石得 3 石料并仅扣一次效果 |
| 模拟器结果核对 | 15 项状态断言均通过 | [playtest.json](../../output/character-emulator-2026-09-14/playtest.json)，依逐步保存的前后快照核算 |

服务端覆盖装备唯一性、槽位交换、跨堆扣料、满包原子回滚、料理叠加与耗尽、无效动作不扣次数、
HTTP 重放、内存与 PostgreSQL 一致性，以及领域 `16` 的背包、暂存、实例、矿坑和历史结果迁移。
固定测试库为 `sensen_farm_journey_character_test_20260914`，与试玩库分离。

广泛 Godot 回归中的失败为 `test_new_trail_has_distinct_materials_and_physical_targets`：
无加成时不应改变原 JSON 数值类型；实现修复后该测试与关联专项通过。
29 个孤立节点提示位于原有农场场景测试，2026-09-13 的
`output/localization-qa-20260913-investor/native-tests.log` 同一套件也报告 29 个；本轮未定位其来源，
不将它们记为本轮新增问题，也不宣称已消除。

原生报告为 [report.json](../../output/localization-qa-character-20260914/project/output/character-visual/report.json)，
其中 `natural_player_verified=false`、`physical_device_verified=false`。
冷启动证据为 [cold-start.json](../../output/character-emulator-2026-09-14/cold-start.json)，
对应 `before-restart.json` 与 `after-restart.json`。

## 模拟器操作

设备 `emulator-5560`，720x1560；独立包 `com.sensen.journeycharacterqa`。
服务端口 `3151`，记录时 PID `63636`；数据库
`sensen_farm_journey_character_emulator_20260914`。APK 位于
`output/character-emulator-2026-09-14/sensen-character-local-qa-2026-09-14.apk`。
以下除 `v0` 外，均是人工材料夹具基础上的实际客户端操作。

| 版本 | 实际操作与状态核对 |
| --- | --- |
| 普通新档 `v0` | 正常建场并打开人物页，四项基础值依次为 `1 / 0 / 0 / 0`，基础农具已装备 |
| `materials` 夹具 `v1` | 显式补充原料、三种料理及工作台/厨房解锁；新增三件装备尚未拥有 |
| `v2-v4` | 在工作台依次制作铜镐、手套、围裙，分别扣木料 3/铜矿 4/石料 2，木料 2/芦苇 4，铜矿 2/芦苇 4；仍装备基础农具 |
| `v5-v6` | 喝茶获得 3 次效果，再装备围裙 |
| `v7` | 制作花箱实际扣木料 1、芦苇 1；花箱库存 `1 -> 2`，茶剩 2 次 |
| `v8` | 制作铜箍木箱扣木料 1、铜矿 3、石料 1；只有围裙贡献节省，茶仍为 2 次 |
| `v9-v10` | 换采集手套，食用沙拉获得 3 次效果；已有茶效果保留 |
| `v11-v12` | 育苗地西、东两处分别获得木料 3；沙拉依次剩 2、1 次 |
| `v13-v14` | 小馆西侧获得木料 3、芦苇 1，沙拉耗尽；随后东侧仅手套生效，获得木料 2、芦苇 1 |
| `v15-v17` | 装备铜镐，喝汤获得 3 次效果，进入矿坑第一层 |
| `v18` | 点击 `rock_1` 得石料 3、铜矿石 1；汤剩 2 次；随后冷启动，版本与背包、人物、矿坑状态均保持 |
| `v19-v20` | `rock_2`、`rock_3` 各得石料 3，额外分别为岩盐 1、铜矿石 1；汤依次剩 1 次、耗尽 |
| `v21` | `rock_4` 仅铜镐生效，获得石料 2；茶仍剩 2 次，证明采矿不会消耗制作效果 |
| `full` 夹具 `v22-v23` | 24 格满包、铜镐与 3 次汤效果；入矿后开采被拒绝，版本仍为 23，矿石、库存与汤次数均保持 |
| `v24-v25` | 用数量输入选择 99 铜矿并确认丢弃，空出一格；重试同一矿石获得石料 3、岩盐 1，汤剩 2 次，矿石只完成一次 |
| 结束准备 `v26` | 恢复满包检查前的材料与已制作装备，背包序号和 ID 分配器保持单调，已退出矿坑；人物页和配件替换比较截图已检查，最终停在人物页 |
| `v27-v28` | 从人物页卸下手套，采集加成 `1 -> 0`、背包 `21 -> 22` 格；重新装备后 `0 -> 1`、占用恢复 21 格，原实例与料理次数不变，最终停在人物页 |

夹具工具为 `server/tools/prepare_character_qa.ts`，固定只访问上述独立模拟器库并要求明确 `FARM_ID`。
`fixtures/*-before.json` 保存修改前完整农场行，`*-after.json` 标注 `artificial_qa=true`、新版本与状态。
`materials` 原始备份为
`output/character-emulator-2026-09-14/fixtures/2026-09-14T11-36-51.037Z-materials-5544558d-8bda-4023-9829-982fb98bda33-before.json`。
人工补入的材料、料理和解锁不能计为自然获得，不能用于推断成长节奏或玩家自主配装意愿。

操作证据位于 `output/character-emulator-2026-09-14/actions/`，每次动作保存同名前缀的
`*-before.json`、`*-action.json`、`*-after.json` 与 `*.png`。关键截点：

- [铜镐制作，v2](../../output/character-emulator-2026-09-14/actions/2026-09-14T11-38-02-176Z-tap.png)。
- [花箱节省并扣一次茶，v7](../../output/character-emulator-2026-09-14/actions/2026-09-14T11-41-04-090Z-tap.png)。
- [木箱仅装备节省，v8](../../output/character-emulator-2026-09-14/actions/2026-09-14T11-41-55-973Z-tap.png)。
- [沙拉耗尽后的采集，v14](../../output/character-emulator-2026-09-14/actions/2026-09-14T11-43-46-816Z-tap.png)。
- [铜镐与汤叠加开采，v18](../../output/character-emulator-2026-09-14/actions/2026-09-14T11-45-38-367Z-tap.png)。
- [汤耗尽后仅铜镐生效，v21](../../output/character-emulator-2026-09-14/actions/2026-09-14T11-46-37-459Z-tap.png)。

最终截图：[人物属性](../../output/character-emulator-2026-09-14/screenshots/character.png)、
[装备替换比较](../../output/character-emulator-2026-09-14/screenshots/equipment-comparison.png)、
[实际制作优惠](../../output/character-emulator-2026-09-14/screenshots/crafting-effect.png)。
满包后恢复试玩状态的前后快照为 `resume-before.json` 与 `resume-after.json`，
同样标记为人工测试状态。`app-logcat.txt` 的本轮应用采样无 GDScript 错误或崩溃。
APK SHA-256：`dd24384589a40159c02415efaacd539b745fb35ffe09ac47bfedd8e7481a550d`。

本机 Godot 启动入口为 `tools/dev/open_character.command`；模拟器服务保持在
`http://127.0.0.1:3151/v1`，使用 `10.0.2.2:3151` 供模拟器访问。
Android 16 的该模拟器仍使用原有 16 KB 兼容模式，本轮没有修改原生库对齐。

## 验收边界

初轮 113 在 Godot 与模拟器开发验证；用户随后明确要求真机安装并测试，结果见下节。
之前安装的 112 真机应用及存档保留，`3150` USB 转发维持其既有试玩连接。
本报告不宣布发布、不自动修改 Plane 卡片状态。玩家是否能自主读懂属性、为下一次采集/制作/探索
选择装备和料理，并形成重复选择，仍需自然玩家观察。

## 真机测试补充

2026-09-14 已按用户要求在 vivo V2509A（`10AFAF162200319`）安装独立应用
“街角四季·人物测试”，包名 `com.sensen.journeycharacterqa`，版本
`0.6.0-character-local.20260914.r1`。112 与原矿坑应用及存档保留。
服务为 `127.0.0.1:3152`，PID `83698`，固定独立库
`sensen_farm_journey_character_device_20260914`；通过 `adb reverse tcp:3152 tcp:3152` 连接。

真机从普通新档 `v0` 查看基础属性，再使用独立人工材料存档完成与上表 `v1-v28`
同样的核心流程：三件装备实际制作、围裙替换、食用花茶、有效叠加节料、无额外节省保留次数、
手套加沙拉采集及耗尽、铜镐加汤采矿及耗尽、途中冷启动、满包拒绝和丢弃后原矿石重试、
配件卸下再装备。随机额外矿物按该真机农场独立生成，不要求与模拟器掉落相同。

[真机状态核对](../../output/character-device-2026-09-14/playtest.json)的 15 项断言全部通过；
[冷启动核对](../../output/character-device-2026-09-14/cold-start.json)确认背包、人物效果、矿坑、
农场版本保持不变。应用日志采样未发现 GDScript 错误或崩溃。
测试后恢复满包检查前的材料与已制作装备，最终 `v28` 停在人物页，供继续试玩。

材料和满包夹具使用 `prepare_character_qa.ts ... --device`，只允许上述固定真机测试库，
每次修改先备份完整农场行。备份、操作前后快照与截图位于
`output/character-device-2026-09-14/`；这些人工材料与解锁不计为自然玩家进度或体验证明。

- [真机人物页截图](../../output/character-device-2026-09-14/screenshots/character.png)。
- APK：`output/character-device-2026-09-14/sensen-character-local-qa-2026-09-14.apk`。
- SHA-256：`9b2d0b55107bd4e4b1048f8891a6c53761da0bf8a6c8c7cf40945293ef63d127`。
- 本地试玩需保持 USB 与服务运行，重新插线后可能需要恢复端口转发。
