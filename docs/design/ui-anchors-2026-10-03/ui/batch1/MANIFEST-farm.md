# 批次 1 · HUD、农场与操作设计

更新：2026-10-05。规则基准为[玩法方案 v2](../../../../product/gameplay-plan-v2-2026-10-02.md)第 3、5、10、14、16 章；视觉对照使用 [Figma 原型](https://www.figma.com/design/icmfLGHkiMBfMQApCiw13D/Gensen--US-?node-id=310-2955)。[返回设计索引](../../REPORT.md)。

本清单描述当前设计源及适用范围。静态图中的存档数值和坐标为排版样例，不能用作新的玩法规则或实现完成证明。

## 页面索引

| 编号 | 当前设计源 | 内容与操作 |
|---|---|---|
| HUD-1 / HUD-1-2 | [骨架](HUD-1.html) · [状态](HUD-1-2.html) | 两行 HUD、体力色态、位置芯片、摇杆与底部操作区；头像入口为 Profile |
| HUD-3 | [Energy Card 归零态](HUD-3.html) | 显示当前体力、回满时间与恢复途径；引导瓦片不代替用户执行动作 |
| HUD-4 | [Today](HUD-4.html) | 芯片下展开三条引导；Show on map 只移动相机并高亮目标 |
| CTRL-1 / CTRL-1-2 | [摇杆与安全框](CTRL-1.html) · [缩放与回中](CTRL-1-2.html) | 角色越出安全框后相机跟随；缩放与双击回中参考玩法方案第 10 章 |
| FARM-2 | [播种](FARM-2.html) | 种子选中、脚前目标、按住劳作、单次与批量反馈；工具选择来自背包 Gear |
| FARM-3 | [收获](FARM-3.html) | 成熟标记、免费收获、合并飘字、物品进入背包 |
| FARM-6 / FARM-6-2 | [购买](FARM-6.html) · [从背包出售](FARM-6-2.html) | 无人值守 Homestead Stall；上半柜台，下半背包，购买库存与物品选择联动 |
| FARM-7 / FARM-7-2 | [长椅设施](FARM-7.html) · [休息](FARM-7-2.html) | 点击长椅打开设施卡；主行动键仍表示当前劳作，状态区分可用、冷却与今日已用 |
| BAR-1 / BAR-1-2 | [快捷栏与钉住](BAR-1.html) · [收起态](BAR-1-2.html) | 当前行动的消耗品、幽灵格、长按 Pin / Unpin；Bag 保留在右端 |
| BAR-2 | [行动径向](BAR-2.html) | 切换 Farming / Fishing / Mining / Combat；矿洞以外显示相应不可用原因 |
| BAR-3 / BAR-3-2 | [体力不足](BAR-3.html) · [引导长椅](BAR-3-2.html) | 与 HUD-3 共用 Energy Card；点击 Rest 后高亮长椅，体力和物品尚未变化 |
| SKILL-3 / SKILL-3-2 | [钓鱼升级](SKILL-3.html) · [种植与烹饪解锁](SKILL-3-2.html) | 解锁反馈、礼物、蓝图与第三投料槽；确切门槛及奖励查玩法方案 |
| TUT-2 / TUT-2-2 | [情境教学](TUT-2.html) · [首次遇锁](TUT-2-2.html) | 首会话短提示、技能条件、距离解锁所需 XP 与退还反馈 |

总览场景见 [FARM-1](../farm.html)、[FISH-1](../pond.html)、[COOK-1](../kitchen.html)。HUD-2、农场升级、果园和工作台见[批次 2](../batch2/MANIFEST-batch2.md)。

## 当前约定

- 画布 1080 × 2400；主行动键 176、切换键 96；快捷栏为 5 个消耗品位加 Bag。这些是设计画布尺寸，实际终端仍须按安全区与触摸尺寸适配。
- 摇杆移动与劳作输入分开。主行动键执行当前行动；灶台、驿站、长椅、工作台等设施靠点击触发。
- 工具不占快捷栏。`FARM-2` 等局部示意中的工具名称仅说明行动效果；装备入口统一遵循 [BAG-2](../batch2/BAG-2.html)，不得据此另建工具抽屉。
- Energy Card 使用 `../kit-energycard.css` 的 `.ec-*` 组件。HUD-3 与 BAR-3 仅在数值和副标题上区分；Eat / Cook / Tea / Rest 显示系统确知的数量或状态，点击后引导到背包、厨房、地图或长椅。`Free to do now` 关闭卡片。
- 农场驿站使用 `../../scenes/homestead-stall-v2.png`，标题为 Homestead Stall。没有掌柜、问候卡或居民服务；点击棚屋直接打开 FARM-6。上半 Buy / Stall Board，下半背包；Sell / Sell All 在物品详情内，额度与不可卖原因留在同屏。
- 钉住态采用格顶中央琥珀图钉徽标、顶条和淡底色；选中态的绿色外框与上抬同时可见。Pin / Unpin 通过长按小卡操作，拖拽分镜见 [BAG-4](BAG-4.html)。

## 共享依赖与保留限制

基础样式与图标为 `../kit.css`、`../icons.svg`；本组使用 `../kit-farm.css`、`../icons-farm.svg`，Energy Card 与设施卡另用 `../kit-energycard.css`、`../kit-facility.css`、`../icons-facility.svg`。交易抽屉的共用样式还涉及 `../kit-npc.css`，不能按单页名称移除共享依赖。

底图定位使用 `canvas = source × scale + (x, y)`。一般场景相机为 farm `1.22 / −127 / 356`、pond `1.45 / −207 / 246`、kitchen `1.39 / −229 / 280`，局部页以自身 `body` 参数为准。预览必须经 HTTP，方法见[总索引](../../REPORT.md)。

Today 完整任务文案可能在与位置芯片同行时省略；CTRL-1 的取景和田格覆盖是静态示意；移动、休息、升级与物品飞入效果还需真实动画验证。Stall Board 完整页、部分满包/灰态以及 Today 完成行切换未在本组完整展开。此前静态巡检不等于当前客户端验收。
