# 批次 2 · 内容、成长与个人页设计

更新：2026-10-05 下午审图口径。规则以[玩法方案 v2](../../../../product/gameplay-plan-v2-2026-10-02.md)及第 1.5 节 p(6)–p(9) 为基准；视觉对照使用 [Figma 原型](https://www.figma.com/design/OMLTC3yw3u2WDjOZhLnhaR/Gensen--US-?node-id=310-2955)。[返回设计索引](../../REPORT.md)。

## 页面索引

| 编号 | 当前设计源 | 内容与约定 |
|---|---|---|
| HOME-1 | [农场等级](HOME-1.html) | 等级、下一阶段与材料需求；按内容高度展示抽屉 |
| HOME-2 | [升级时刻](HOME-2.html) | 农场变化、解锁反馈、体力与背包升级提示 |
| SKILL-1 | [三轨技能](SKILL-1.html) | Farming / Fishing / Cooking；等级门槛、解锁与首次收集 |
| SKILL-2 | [技能门禁](SKILL-2.html) | 从无人农场驿站的锁定商品进入；显示当前 XP、目标与查看田地入口 |
| FISH-6 | [Fish-dex](FISH-6.html) | 稀有度、收集数量、剪影、地点/时段提示与技能锁 |
| HUD-2 | [体力信息](HUD-2.html) | 上限、食物/茶/休息/失败退还的今日用量与新手祝福；纯信息 |
| PROFILE-1 | [自己的 Profile](PROFILE-1.html) | 外观、身份、关注关系、技能、农场、收藏、勋章与留言入口 |
| PROFILE-2 | [他人的 Profile](PROFILE-2.html) | Visit farm、Send a gift、Follow 与密友进度 |
| SETTINGS-1 | [设置](SETTINGS-1.html) | 从 Profile 进入；具体开关与账户状态须对照实际功能 |
| BAG-2 | [Bag / Gear](BAG-2.html) | 背包同一抽屉中的 Gear 一侧；四工具槽 + Ring / Charm，点槽显示对应候选 |
| BAG-2-2 | [材料与仓库](BAG-2-2.html) | 材料分类、入库标识、Take 10 / Take all；仓库规则以玩法方案为准 |
| BAG-5 | [满包提示](BAG-5.html) | 容量、整理与背包升级条件；主动操作仍受容量规则限制 |
| BAG-5-2 | [被动奖励进包裹](BAG-5-2.html) | 奖励进入 Inbox 的飘条、铃铛与农舍信箱 Parcel 标记 |
| SOC-4 | [Inbox · Parcels](SOC-4.html) | To do / Parcels / Updates；领取、容量和有效期说明 |
| MINE-1 | [矿洞一层](MINE-1.html) | 岩石、楼梯、电梯、火把、行动与层费提示；数值以第 13 章为准 |
| FARM-4 | [果园](FARM-4.html) | 成熟、首次结果、再生长与果树容量 |
| FARM-5 | [工作台与设施](FARM-5.html) | 蓝图、材料进度、缺口与技能条件 |

对应截图位于 `../../out/batch2/<编号>.png`；[批次总览](../contact-batch2.html)用于浏览，操作与规则仍以各页和玩法方案为准。超出 P0 的页面保留为后续阶段设计，不因此计入 P0 完成度。

## 最新入口与信息结构

- Homestead Stall 无人值守，点棚屋直接打开交易抽屉。[FARM-6](../batch1/FARM-6.html)、[FARM-6-2](../batch1/FARM-6-2.html) 和 SKILL-2 使用无人驿站底图，不显示掌柜问候。
- 头像打开 PROFILE-1；收藏与 Passport 汇入个人页。外观编辑从 Profile → Edit look 进入，设置从 Profile 进入。
- Bag / Gear 是同一背包抽屉的两侧。Gear 不占 Bag 空间；Tackle 分类用于消耗品，外观不放在 Gear。保留的 [bag.html](../bag.html) 只作为基础物品网格与详情来源，完整入口结构以 BAG-2 为准。
- 被动奖励满包后进入包裹，不弹丢弃二选一。右上角铃铛与农舍信箱打开同一 Inbox，Parcels 页处理领取；有效期与容量门禁按玩法方案第 10 章。
- `need-tile` 表达“已有 / 需要”；收集进度与今日用量采用绿色部分环，琥珀用于材料不足，避免把未集齐和缺料混为同一警告。

## 素材与依赖

本组使用 `../kit-b2.css`、`../kit-need.css`、`../kit-profile.css` 及共享 kit；图标来自 `../icons-home.svg`、`../icons-profile.svg` 和公共 sprite。PROFILE 底图为 `profile-avatar.png` / `profile-avatar-mia.png`；升级、矿洞、果园、设施底图分别为 `farm-lv3.png`、`mine-floor1.png`、`farm-orchard.png`、`farm-facilities.png`。

预览需经 HTTP，画布 1080 × 2400、DPR 1，方法见[总索引](../../REPORT.md)。底图、示例账号、背包数量和动画截图不代表运行中的游戏状态。

## 生成脚本使用边界

`_gen.py` 与 `_gen_rev.py` 保留为设计制作工具，本次未修改。`_gen.py` 仍包含已被当前规则替代的生成分支；不要执行全量生成后直接覆盖、交付现有页面。

需要重建时应先限定具体目标，检查生成函数，再核对玩法方案。相关页面必须在基础生成后应用 `_gen_rev.py` 的对应修订（`farm6 / skill2 / profile1 / profile2 / bag2 / soc4 / bag5b`），随后逐页检查。修订脚本不是通用迁移器，也不能保证恢复所有后续手工排版与场景替换。

`_gen.py` 从 `../batch1/FARM-6.html` 读取 HUD，`_gen_rev.py` 导入 `_gen.py`；因此不能移除当前 FARM-6 或共用素材。生成器内部仍有历史名称不代表恢复相应入口的授权，当前索引和玩法方案才是核对依据。

工作台放置预览、矿洞完整流程和部分短屏/边界状态尚未由本组静态页覆盖；实现与真人验收情况请看 [P0 核查](../../../../qa/p0-progress-audit-2026-10-05.md)。
