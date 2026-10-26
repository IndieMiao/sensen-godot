# 批次 1 · 钓鱼、烹饪与背包操作设计

更新：2026-10-05。规则以[玩法方案 v2](../../../../product/gameplay-plan-v2-2026-10-02.md)第 4、6、7、10、16 章为准；视觉对照使用 [Figma 原型](https://www.figma.com/design/icmfLGHkiMBfMQApCiw13D/Gensen--US-?node-id=310-2955)。[返回设计索引](../../REPORT.md)。

## 页面索引

| 编号 | 当前设计源 | 内容与适用范围 |
|---|---|---|
| FISH-2 | [咬钩与收线](FISH-2.html) | 下沉、Hook 窗口、绿带鱼影、收线进度；小游戏期间由 Hook 接管操作区 |
| FISH-3 | [鱼获结果](FISH-3.html) | 鱼种、稀有度、首次收集、XP 与继续钓鱼 |
| FISH-4 | [鱼篓满](FISH-4.html) | 主动抛竿容量门禁、打开背包或回家引导 |
| FISH-5 / FISH-5-2 | [技能门禁](FISH-5.html) · [鱼竿与保护期变体](FISH-5-2.html) | 挣脱原因、解锁目标与退还；具体 XP、次数、退款按玩法方案 |
| COOK-2a / COOK-2a-2 | [Cookbook](COOK-2a.html) · [图鉴状态](COOK-2a-2.html) | 菜谱、已品尝、线索、未知、可做与等级锁，详情与材料需求同屏 |
| COOK-2b / COOK-2b-2 | [Experiment](COOK-2b.html) · [投料与门禁状态](COOK-2b-2.html) | 原料进入场景中的锅，锅下槽条、第三槽解锁、族标签、稀有原料确认 |
| COOK-3 / COOK-3-2 | [火候小游戏](COOK-3.html) · [火候结果与多灶](COOK-3-2.html) | 针入金区、Missed / Nice heat / Perfect、品质与额外份数提示 |
| COOK-4 | [完成料理](COOK-4.html) | 料理、稀有度、品质、首次制作、Eat / Keep |
| COOK-6 | [Mystery Dish](COOK-6.html) | 失败料理保留回能用途，并给 Cookbook 增加线索 |
| COOK-7 / COOK-7-2 | [进食](COOK-7.html) · [重复、额度与溢出](COOK-7-2.html) | 恢复体力、今日食物额度、同菜衰减、满体力与部分收益确认 |
| BAG-3 | [物品详情](BAG-3.html) | 鱼的来源、稀有度、用途、价格与可执行动作；材料与装备变体见批次 2 |
| BAG-4 / BAG-4-2 | [拖入快捷栏](BAG-4.html) · [钉住与取消](BAG-4-2.html) | 背包消耗品拖入当前行动快捷栏，长按 Pin / Unpin |

厨房总览为 [COOK-1](../kitchen.html)；基础物品网格为 [BAG-1](../bag.html)。完整背包入口是 Bag / Gear，装备与包裹分别见 [BAG-2](../batch2/BAG-2.html) 和 [SOC-4](../batch2/SOC-4.html)。

## 当前烹饪约定

点击灶台后相机推近，锅留在 3D 场景里。锅内显示选中原料，锅下显示槽条与菜品预览胶囊；下方抽屉切换 Cookbook / Experiment。Cookbook 集合菜谱查阅、发现进度与制作入口，Experiment 的抽屉显示背包原料。投料初始为 2 槽，Cooking Lv4 开第 3 槽。

Cookbook 以可做、已发现但缺料、Tasted、有线索、未知区分展示；可做排序与稀有度顺序按玩法方案第 7.2.7 节。`Can cook` 可包含已品尝且材料足够的料理；已发现计数不能直接把 Tasted 一并相加。当前分镜同时保留菜谱详情、材料需求、线索原料族和等级条件。

Experiment 允许从锅下槽条取回原料；投入物与背包数量联动。第三槽锁定态可见，页面底部按钮为 `Cook`。稀有鱼的不可烹饪状态与高价值材料确认依据玩法方案，不能仅根据图标是否可拖动判定规则。

`COOK-2b-2` 已采用与主页面一致的场景锅、锅下槽条与原料背包结构。锅位受静态底图约束；真实实现应在玩家实际点击的灶上展示对应锅与状态。

## 依赖与预览

本组共享 `../kit.css`、`../icons.svg`，使用 `../kit-cook.css`、`../icons-cook.svg`；快捷栏钉住与部分分镜还复用农场样式。烹饪舞台样式为 `.stage / .pot-ing / .pot-slots / .pot-cap`，图鉴样式为 `.drawer.is-cookbook / .ck / .cell.is-page`。

COOK-2a/2b 的静态取景参数为 `1.85 / −511 / −499`，锅心约在画布 `(540, 580)`。画布为 1080 × 2400。须经 HTTP 加载外链 SVG sprite，方法见[总索引](../../REPORT.md)。

## 保留限制

钓鱼浮标、厨房锅与人物局部仍是静态底图或 CSS 示意，不能证明动画和实际操作。Kitchen Mishaps、部分满包结果、全部菜谱里程碑等未完整展开。被动奖励满包后进入 Inbox 的规则见 [BAG-5-2](../batch2/BAG-5-2.html)；不能把鱼篓满或主动收取容量门禁视为同一状态。所有样例奖励、XP、回能与价格以玩法方案正文为准。
