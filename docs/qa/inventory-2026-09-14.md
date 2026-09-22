# SGODOT-112 背包与物品验证

日期：2026-09-14。分支：`farm-dev`。领域版本 `16`，存档结构版本 `1`。
本报告区分已实现行为、自动验证与模拟器操作证据；记录截至模拟器农场版本 `22`。
满包拒绝、丢弃后恢复开采与最终包覆盖安装冷启动均已验证；自然玩家体验仍未验证。
初轮按用户要求仅使用 Godot 和模拟器；用户随后明确要求安装真机，安装检查见文末补充。未发布线上版本或修改 Plane 状态。

## 已实现范围

- 共享物品定义统一名称、分类、描述、用途与实际玩法属性；原有物品 ID 保持稳定。
- 24 格背包，材料、矿物、种子、作物每堆 99，料理与摆件每堆 20，工具为独立实例。
  赠送与购买种子分堆；品质、来源、属性不同的堆叠不能混合。
- 物品详情、搜索、分类筛选、拆分、合并、整理、暂存领取、丢弃确认与工具装备/卸下。
  已装备工具不占背包格，永久工具和已预留建造数量不能丢弃。
- 农场、矿坑、街区与地点可打开背包，物品用途连接播种、矿坑、厨房、工作台、出售交付与庭院。
  从矿坑选择其他用途时先完成离矿结算；背包操作保存期间阻止关闭和重复操作。
- 采矿、采集、收获、购买、制作和料理统一对账；普通产出满包时原子拒绝。
  首次花箱进入库存，庭院新摆放扣除、取回返还，位置调整不重复扣除。
- 旧档超额物品与自动奖励进入暂存。已有 `bag` 后以其为库存权威，不重复导入旧汇总；
  旧免费庭院道具只转换一次，已摆放道具及独立工作台存量保留。
- `BAG_CHANGED` 自动读取权威状态；刷新失败时保留恢复入口并阻止继续用旧序号管理背包。

## 自动验证

| 范围 | 已记录结果 | 证据或限制 |
| --- | --- | --- |
| 初版服务端全量，含 PostgreSQL | 578 项通过 | 后续庭院统一后另跑下列最终回归，不能将此次数当作最终全量 |
| 最终服务端内存回归 | 514 项通过 | 覆盖领域、HTTP 内存实现和相关契约 |
| 最终 PostgreSQL/HTTP/迁移 | 63 项通过 | 独立测试库；包含保存、重放、旧档迁移与庭院库存流转 |
| Godot 广泛回归 | 476 项，1 处失败，29 个孤立节点提示 | `client-tests.log`；数量显示 `x1.0` 已修复，不能记为本次全量全绿 |
| 最终背包与庭院专项 | 33 项通过，0 错误/失败/跳过/孤立节点 | 14 项背包、19 项庭院；`final-focused-tests.log` |
| 原生中英文布局 | 90 张截图，错误列表为空 | 360x640、390x844、960x720；合成库存状态 |
| 新物品缩略图 | 13 张 256px 透明 PNG，均非空且保存成功 | `item-render.log`；逐张检查主体完整、居中，无裁切 |
| 模拟器最终包覆盖安装、冷启动 | 通过；版本保持 18，背包与矿坑深比较相等 | `upgrade-cold-start.json` |
| 模拟器满包恢复 | 通过；拒绝无状态变化，准确丢弃后同一矿石可开采 | `full-bag-recovery.json` |

服务端边界覆盖堆叠上限、跨堆消耗、变体保留、满包回滚、工具唯一性、旧档暂存、
自动奖励不重复、原始幂等请求重放，以及迁移前后历史结果保留。
客户端专项覆盖搜索焦点、选定数量与序号、离线恢复、同农场版本下背包序号更新、
装备、物品用途及庭院占用和取回。
另做过 2,500 次确定性内存操作，逐次核对变体总量、唯一 ID、容量、堆叠上限和拒绝原子性，
948 次成功、1,552 次拒绝均满足约束；此补充检查发生在庭院统一前，不替代最终回归。

服务端测试入口：`server/tools/test_inventory_isolated.mjs`，固定使用
`sensen_farm_journey_inventory_test_20260914`，与试玩数据库分离。
复跑前需工作区依赖与 `server/.env` 中可连接的测试数据库配置：

```sh
pnpm --dir server typecheck
node server/tools/test_inventory_isolated.mjs
tools/run_tests.sh res://tests/inventory
```

Godot 日志位于 `output/inventory-emulator-2026-09-14/`。
原生布局报告为
[`report.json`](../../output/localization-qa-inventory-20260914/project/output/inventory-visual/report.json)，
其中 `passed=true`、`natural_player_verified=false`、`physical_device_verified=false`。
原生探针为 `tools/dev/inventory_visual_probe.gd`；缩略图复现入口为
`tools/art/render_inventory_items.tscn`，复用游戏内模型与建模助手。

## Android 模拟器操作

使用 `emulator-5560`，720x1560；独立包 `com.sensen.journeyinventoryqa`，
本机服务 `3149`，记录时 PID `41572`，数据库
`sensen_farm_journey_inventory_emulator_20260914`。
APK 位于 `output/inventory-emulator-2026-09-14/sensen-inventory-local-qa-2026-09-14.apk`。
最终覆盖安装包包含庭院物品选择器的中文修正和统一的“铜箍木箱”名称。
模拟器既有的 16 KB 原生库兼容弹窗仍存在，确认后在兼容模式进行功能验证；
本轮没有验证或修复原生库的 16 KB 对齐。

| 状态来源与版本 | 实际操作与结果 |
| --- | --- |
| 普通新档 `v0-v5` | 正常选城、建场；种子拆分再合并，数量保持；进入矿坑点击一块矿石，石料进入背包；返回农场，已挖记录保留 |
| `materials` 人工夹具 `v6` | 显式补入材料、料理、工具及相关解锁，19/24 格；保存修改前后快照 |
| 夹具后 `v7-v11` | 入矿并采一块；从铜矿用途离矿到工作台，制作使木箱 `1 -> 2`；从岩盐用途到厨房，料理使蔬菜汤 `1 -> 2` |
| 夹具后 `v12-v14` | 装备整畦农具、卸下、再装备；工具实例保留，卸下占格、装备释放格子 |
| 夹具后 `v15-v16` | 木箱进入庭院并保存，库存 `2 -> 1`；取回保存后 `1 -> 2`，庭院放置列表清空 |
| `full` 人工夹具 `v17-v18` | 24/24 格，石料堆已满；入矿后开采返回 `BAG_FULL`，版本保持 `18`、`mine.broken` 保持空，未消耗矿石或增加材料 |
| 最终包覆盖安装、冷启动 `v18` | 启动标识改变，农场版本不变，`bag` 与 `mine` 同重启前深比较完全一致 |
| 满包恢复 `v18-v20` | 满包拒绝前后整个状态相等；选择 99 份铜矿石并确认丢弃，`v19` 变为 23 格、铜矿石剩 95；重试同一 `rock_1`，`v20` 石料增加 1、已挖记录仅该矿石 |
| 结束准备 `v21` | 显式恢复 `materials` 人工夹具，19/24 格，供后续截图与本地继续测试；不计入自然获得 |
| 最终界面 `v22` | 分类筛选收获物并恢复全部物品，按分类整理；铜矿、木箱等中文名称与数量正常，最终截图已检查 |

`materials` 与 `full` 均由 `server/tools/prepare_inventory_qa.ts` 显式建立，
只允许独立模拟器库内的普通测试农场。`fixtures/*-before.json` 保存原始行，
`*-after.json` 标注 `artificial_qa=true`、版本与最终状态。夹具补入的材料和解锁
不能计为自然获得，也不能把上述制作/料理流程作为自然成长节奏的验证。

操作证据位于 `output/inventory-emulator-2026-09-14/actions/`，完成的动作成套保存
`*-before.json`、`*-action.json`、`*-after.json` 与 `*.png`。
只读观察器提供当前控件与模型投影；操作工具校验前台应用和观测新鲜度后发出模拟器触摸。
关键截图与对应同名前缀状态记录：

- `2026-09-14T10-21-35-872Z-tap.png`：普通新档首次矿石入包，`v4`。
- `2026-09-14T10-26-10-946Z-tap.png`：夹具后木箱制作完成，`v10`。
- `2026-09-14T10-26-56-568Z-tap.png`：夹具后岩盐蔬菜汤完成，`v11`。
- `2026-09-14T10-28-33-080Z-tap.png` 与 `2026-09-14T10-28-39-248Z-tap.png`：庭院放置和取回，`v15-v16`。
- `2026-09-14T10-29-51-905Z-tap.png`：满包拒绝开采，仍为 `v18`。
- [背包](../../output/inventory-emulator-2026-09-14/screenshots/backpack.png)与[铜矿详情](../../output/inventory-emulator-2026-09-14/screenshots/copper-details.png)：最终包中文截图，`v22`。

最终检查为
[`upgrade-cold-start.json`](../../output/inventory-emulator-2026-09-14/upgrade-cold-start.json)
与 [`full-bag-recovery.json`](../../output/inventory-emulator-2026-09-14/full-bag-recovery.json)，
两者均为 `passed=true`。操作期截图中的早期物品名称不代表最终安装包仍使用旧名称。
最终 APK SHA-256：`fbee6551c7ecd7047171f66d8009888bf1db9f76bb92336eb72e3cc1e2ac8971`。
`logcat.txt` 本轮采样未发现 GDScript 错误或应用崩溃。

## 结论边界

- 广泛 Godot 回归的 29 个孤立节点提示与旧基线一致：`output/localization-qa-20260913-investor/native-tests.log` 和本轮日志均在 `test_crops_render_outside_props` 后报告同样数量。该测试未创建背包；本轮没有新增证据，具体节点仍可另行定位。
- 初轮没有真机验证或自然玩家观察。合成布局和人工材料夹具证明指定界面与事务可操作，
  不证明玩家会自然理解背包、主动规划材料用途或形成目的明确的第二次矿坑出行。
  SGODOT-111 的自然玩家闭环与 SGODOT-112 的完整验收状态均不由本报告自动宣告完成。

## 真机安装补充

2026-09-14 用户重新连接手机并明确要求安装当前背包版本。已在 vivo V2509A
（设备 `10AFAF162200319`，内存页 4096 字节）安装独立应用“街角四季·背包测试”，
包名 `com.sensen.journeyinventoryqa`，版本 `0.5.0-inventory-local.20260914.r1`。
原 `com.sensen.journeyminingqa` 应用及其存档保留。

真机包连接 `http://127.0.0.1:3150/v1`，通过
`adb -s 10AFAF162200319 reverse tcp:3150 tcp:3150` 转发到本机服务，PID `53777`。
独立数据库为 `sensen_farm_journey_inventory_device_20260914`，未使用模拟器人工夹具。
本地试玩需要保持 USB 连接与服务运行；重新插线后可能需要恢复上述转发。

已验证安装成功、正常启动、匿名联网、新建上海农场和背包入口。新档为版本 `0`，
背包 `2/24` 格，萝卜种子 6、生菜种子 3，基础农具已装备；中文文字和图像正常。
已停在背包界面，应用日志采样无 GDScript 错误或崩溃。此次是安装与启动检查，
不代替完整真机功能回归或自然玩家观察。

- [真机背包截图](../../output/inventory-device-2026-09-14/backpack.png)。
- APK：`output/inventory-device-2026-09-14/sensen-inventory-local-qa-2026-09-14.apk`。
- SHA-256：`ed043052088665c466ea2060698fea97133987bd7f2d531be3db62a23fb1ab0e`。
- 安装工程、导出日志、应用日志与触控证据：`output/inventory-device-2026-09-14/`。
