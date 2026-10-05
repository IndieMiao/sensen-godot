# P0 进度核查与 Plane 拆卡（2026-10-05）

基线：`farm-dev@25b7a8a`，已合并 `feat/p0-core` 38 个提交。需求以 [玩法方案 v2](../product/gameplay-plan-v2-2026-10-02.md) §17.2 与 10-05 p(6)–p(9) 最新修订为准。
Figma：[Gensen (US) · Prototype](https://www.figma.com/design/OMLTC3yw3u2WDjOZhLnhaR/Gensen--US-?node-id=310-2955)，file key `OMLTC3yw3u2WDjOZhLnhaR`，page `310:2955`。原型地址已补在玩法方案首页，供后续核查直接使用。

## 结论

**核心闭环有实现，P0 可玩纵切尚未完成，也尚未通过出口验收。** 不给没有统一权重的完成百分比。源码完成、设计完成、测试通过和真人验收分别判断。

已有：200 Energy/自然回复与04:00计数、种植/钓鱼/做菜/进食核心链路、三技能轨阈值、摇杆与安全框、真实地图、25格基础背包、无人 Homestead Stall、Bag | Gear 同抽屉。上海已接入6塘，Pond/River都有，数量达标，不另建“补鱼塘数量”任务。

剩余集中在正式厨房与完整图鉴、主行动切换和快捷栏、背包仓储/包裹、农场等级、矿洞材料工作台、家一套/NPC恢复与委托经济、Profile/Today，以及数值与真实玩家验收。

### 优先修复

1. **升级礼满包会丢失**：`server/src/p0/progress.ts:60` 按 room 截断物品后记账，未把剩余放入包裹。见 SGODOT-158。
2. **Lv4 开第三槽却没有三槽菜**：8作物/8鱼/14菜数量虽存在，料理分布实际7/5/2，目标5/6/3，三槽配方为0。见 SGODOT-154。
3. **首会话成长不符**：首竿/首提5/5，目标10/10且缺首城奖励；首做分支提前return遗漏基础品质XP。Good烤鲫应15、Good香草鱼应30，Cooking Lv2汤配方礼缺失。见 SGODOT-131。

## 对照证据

| 模块 | 已有与缺口 | 主要源码/设计 |
|---|---|---|
| 操作 | 摇杆、安全框、主行动键已有；径向不能切换，缺Pin/收起/Mining候选 | `scenes/p0/p0_ui.gd:1266`、`modules/p0/p0_logic.gd:110`；BAR-1/2 |
| 背包 | 25格、Bag/Gear已有；缺七分类/排序、仓库/扩容、被动奖励包裹 | `p0_ui.gd:624`、`server/src/p0/state.ts:37`；BAG-1/2、SOC-4 |
| 烹饪 | 实验/火候/品质已有；2D临时锅、列表式Cookbook，五态与正式厨房未齐 | `scenes/p0/p0_farm.gd:319`、`p0_cooking.gd:33`、`p0_ui.gd:1445`；COOK-2a/2b |
| 成长生产 | 三轨阈值已有；无Homestead等级、矿洞/采集/制造命令，工具升级不完整 | `server/src/p0/state.ts:37`、`reducer.ts:12,147`；HOME-1/2、MINE-1 |
| NPC经济 | 种子/饵/竿与教学单已有；茶/赠餐、室内据点、8委托及补位/回收额度未齐 | `assets/p0/p0_content.json:762`、`server/src/p0/view.ts:37`；NPC、FARM-6 |
| HUD引导 | 两行HUD、Energy引导卡已有；头像仍到Skills，体力详情/Inbox/Profile未齐，Today仅标签 | `p0_ui.gd:137,139,171,1309`；PROFILE-1、HUD-2/4 |
| 出口 | 有局部运行记录；无新方案对应的完整导演、P0子集七日账本与真人观察通过记录 | 方案 §14.8、§17.2.2；HANDOFF §11–13 |

文件简写 `p0_ui.gd` 均为 `scenes/p0/p0_ui.gd`。服务器旧 domain 功能与9月QA不能代替独立P0实现。

本轮实时读取 Figma Prototype 分区与修订文字，并目视核对 COOK-2a、COOK-2b、BAG-2、PROFILE-1、FARM-6、SOC-4 截图。Figma 里的多灶/48菜/社交等示意数据按P0子集收敛，不自动全量纳入。当前源码已经落实无人驿站与Bag/Gear合并，旧桌面截图中的Bao及独立装备页不能作为当前未做的证据。

## 方案口径待收口

已建 SGODOT-153，未自行改写玩法规则：

- Cooking Lv5–10便利在§17.2写P0、§17.1/17.3写P1。
- 鲭鱼目前Coast-only，但P0要求8鱼且排除Coast。
- 水面不响应点击与FISH-1/钓鱼章允许点击走岸抛竿冲突。
- 首鱼XP40/50、失败竿之后鱼数量不足却需交付再做菜，导演脚本需校准。
- 结束Energy旧目标≥120与P0出口≥180不同，本次验收卡采用§17.2的≥180。
- “批次1共31张”与后续补画不同，需用最新有效页面/状态矩阵验收。

## Plane 已写入并回读

项目：Sensen Godot / SGODOT。用户确认“wipi”即 **In Progress**，state id `38d9c52b-bc9c-4e46-a261-1b19599ec9d4`。

**20张可执行卡：新建18张（153–170），复用更新2张（131、150）。全部回读为In Progress，含现状证据、Figma链接、验收标准、依赖与范围边界。** 原131/150历史描述保留在折叠块内，其他历史卡不作状态重排。In Progress是本次用户指定排程状态，不声称这些任务已开始施工。

| 卡片 | 范围 | 操作 |
|---|---|---|
| [SGODOT-153](https://plane.sensenjoy.cn/zili/projects/47d11337-c390-4b42-8b05-ef60fa2633f7/issues/6dee2ec7-9aa4-4df2-8ff4-4df6b7942f95) | 收口玩法方案与 Figma 的验收口径冲突 | 新建 |
| [SGODOT-154](https://plane.sensenjoy.cn/zili/projects/47d11337-c390-4b42-8b05-ef60fa2633f7/issues/eefa17f7-d0c3-42ec-a42a-5015a5a213bc) | 补齐14页料理结构、三槽菜与8鱼可达性 | 新建 |
| [SGODOT-155](https://plane.sensenjoy.cn/zili/projects/47d11337-c390-4b42-8b05-ef60fa2633f7/issues/0dec7e51-53fb-4024-bcf1-056354fb1536) | 补齐可操作径向菜单、Pin快捷栏与收起把手 | 新建 |
| [SGODOT-156](https://plane.sensenjoy.cn/zili/projects/47d11337-c390-4b42-8b05-ef60fa2633f7/issues/d94b413d-2a9e-4d2d-b0ce-fc59af7c4ec2) | 完成堆肥、Plot Marks与Row Hoe三格播种 | 新建 |
| [SGODOT-157](https://plane.sensenjoy.cn/zili/projects/47d11337-c390-4b42-8b05-ef60fa2633f7/issues/5f5e3430-8e15-4c61-a518-75d399d90336) | 完成Bag七分类、仓库、扩容I与满包收获裁剪 | 新建 |
| [SGODOT-158](https://plane.sensenjoy.cn/zili/projects/47d11337-c390-4b42-8b05-ef60fa2633f7/issues/0c3210a5-003a-4282-b5f2-f09297df9fb2) | 修复满包升级礼丢失并接入Inbox奖励包裹 | 新建 |
| [SGODOT-159](https://plane.sensenjoy.cn/zili/projects/47d11337-c390-4b42-8b05-ef60fa2633f7/issues/86ee2d76-9b2a-40b2-9370-353888897095) | 落地厨房室内与3D灶台烹饪舞台 | 新建 |
| [SGODOT-160](https://plane.sensenjoy.cn/zili/projects/47d11337-c390-4b42-8b05-ef60fa2633f7/issues/82a25137-b4b9-455d-a04c-2336c153ad06) | 补齐Cookbook五态与v5网格、Experiment及早期Cooking便利 | 新建 |
| [SGODOT-161](https://plane.sensenjoy.cn/zili/projects/47d11337-c390-4b42-8b05-ef60fa2633f7/issues/30f68525-57e9-4bcf-8341-448b6bbdbd73) | 实现Homestead Lv1–3升级与可见后果 | 新建 |
| [SGODOT-162](https://plane.sensenjoy.cn/zili/projects/47d11337-c390-4b42-8b05-ef60fa2633f7/issues/3d36d932-27c8-4e2a-bbf0-5cddc9cdb8fd) | 接入1–2层矿洞、按层计费与每日局状态 | 新建 |
| [SGODOT-163](https://plane.sensenjoy.cn/zili/projects/47d11337-c390-4b42-8b05-ef60fa2633f7/issues/a4d57393-e82e-4746-9ec1-324e78d168b5) | 实现7材料、6采集点、工作台与铜镐装备 | 新建 |
| [SGODOT-164](https://plane.sensenjoy.cn/zili/projects/47d11337-c390-4b42-8b05-ef60fa2633f7/issues/1bab1d82-c521-47e5-9555-78cebf93c340) | 补齐家一套据点空间与地图进出 | 新建 |
| [SGODOT-165](https://plane.sensenjoy.cn/zili/projects/47d11337-c390-4b42-8b05-ef60fa2633f7/issues/4b6b30f0-cbb1-408f-80ed-e8fcd48d5977) | 接入热茶、居民赠餐与六类Energy恢复渠道 | 新建 |
| [SGODOT-166](https://plane.sensenjoy.cn/zili/projects/47d11337-c390-4b42-8b05-ef60fa2633f7/issues/3f8009c3-daed-44cd-974f-108b19b0a4ae) | 补齐8委托模板、柜台背包同屏与回收额度 | 新建 |
| [SGODOT-167](https://plane.sensenjoy.cn/zili/projects/47d11337-c390-4b42-8b05-ef60fa2633f7/issues/7e50277c-4385-4850-9939-d8b2b62bf5e7) | 接通Profile主入口与Energy详情，补齐HUD真实状态 | 新建 |
| [SGODOT-168](https://plane.sensenjoy.cn/zili/projects/47d11337-c390-4b42-8b05-ef60fa2633f7/issues/e3b8dad7-306f-4c04-afe8-2c673b7fcf79) | 完成Today世界引导、12步首会话与七日回退脚本 | 新建 |
| [SGODOT-169](https://plane.sensenjoy.cn/zili/projects/47d11337-c390-4b42-8b05-ef60fa2633f7/issues/cba346b9-53df-45cb-87d3-0cf3dd22ebcb) | 重跑8作物8鱼14菜的三类玩家七日数值账本 | 新建 |
| [SGODOT-170](https://plane.sensenjoy.cn/zili/projects/47d11337-c390-4b42-8b05-ef60fa2633f7/issues/d559c7e5-17db-4de5-8fae-b23a18626c12) | 按最新Figma完成交互、英文文案和多尺寸验收 | 新建 |
| [SGODOT-131](https://plane.sensenjoy.cn/zili/projects/47d11337-c390-4b42-8b05-ef60fa2633f7/issues/c00f05f8-fe71-40d8-a7d6-95edaeaada23) | 三轨XP、首会话升级礼与门禁反馈收尾 | 复用更新 |
| [SGODOT-150](https://plane.sensenjoy.cn/zili/projects/47d11337-c390-4b42-8b05-ef60fa2633f7/issues/ce47899b-7ceb-499d-9cf1-d8e2711fc216) | 4–6人自然试玩与可玩纵切出口验收 | 复用更新 |

建议顺序：153先收口；158/131/154优先修复会阻断核心体验的问题；随后并行补功能链与UI；168导演、169数值、170交互验收、150真人观察共同判定P0出口。

## 验证与边界

本轮实际运行：
```sh
pnpm --filter farm-server test -- test/p0
```
此命令展开为 `vitest run -- test/p0`，并未限缩测试，实际结果为 **82 files passed / 5 skipped；861 tests passed / 115 skipped**，耗时34.09s。其中P0两个文件为13+25，**38/38通过**。证据为本轮工具stdout，没有另存完整测试日志。测试通过只证明已有断言，不证明上述缺失功能或真人出口已完成。

客户端26项P0原生测试定义和既有301绿/局部模拟器一圈仅作为历史证据；本轮未重新跑客户端、未新做设备验收。审计未改玩法源码、未操作生产或安装包。

结构化卡片与回读：`output/p0-progress-audit-2026-10-05/plane-receipts.json`、`plane-readback.json`；Figma Section 06原文：`figma-section06.json`。
