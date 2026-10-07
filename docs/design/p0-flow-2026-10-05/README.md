# 07 · P0流程与状态收口

**当前审阅版本（2026-10-07）**：本目录保留首轮流程稿、原卡 ID 和过程证据；后续原生重构、真实 Avatar、统一快捷栏与组件族已汇入[UI 设计审阅入口](../ui-refactor-2026-10-06/REVIEW.md)。下文的“本轮”“最新”均指本目录的历史批次，不能替代当前 Figma 审阅页。

**2026-10-06后续修正**：用户指出背包风格偏离原稿，现已按BAG-1/BAG-2恢复半透明抽屉、原格子与数量角标、单排六槽Gear；HUD、按钮、材料环和劳作控件同步整理为共享组件。本文原轮次计数和`qa/section-07-final.png`是修正前证据；最新视觉见[当前07整板](../p1-p2-flows-2026-10-06/qa/final/section-07.png)与[后续组件说明](../p1-p2-flows-2026-10-06/COMPONENTS.md)。原型卡ID保留。

2026-10-05启动，2026-10-06完成本轮核对 · **第一轮可审阅补稿**。新增73张可编辑设计卡：首会话18、材料/矿洞/制作18、厨房/储物12、容器/引导/Profile/分支25。它们是流程与状态设计，不能作为游戏实现、阶段验收或专属美术完成证明。

[打开 Figma Section 07](https://www.figma.com/design/OMLTC3yw3u2WDjOZhLnhaR/Gensen--US-?node-id=396-2) · [完整画板截图](qa/section-07-final.png) · [P1逐项资产清单](P1-ASSET-REGISTER.md)

## 本轮覆盖

- 首会话：选城/建场/失败重试；12个检查点串起播种、委托、找塘、抛竿、退款、交付、第一锅、进食、生菜、Fine挣脱、Fishing Lv2、Fine首鱼、第二锅与Cooking Lv2。第一锅Keep另有分支，不能套用Eat路径的体力账。
- 材料链：六点产物/冷却/等级要求，采集直接入库；矿洞1–2层进入/清层/付费/续局/重开/满包/日切；Tools、Supplies、铜镐制作装备、被动手套、Homestead升级。
- 厨房：新手单灶近景、2槽Experiment、场景锅火候、满包留灶、调味架、保温柜、领取后开灶、Cook Again足料/缺料/重复XP。
- 状态：无人Stall Board、完成4h/放弃8h补位、Today≤3行、25格Bag/Gear、Parcels单领/批领/满包/8件上限/到期、Profile→换装→保存/取消/重试返回。
- 旧稿同步：Figma COOK-3-2整体替换为可编辑火候三态，移除Cook · Free及切换FAB；对应HTML移除两个旧控件；05/06组标题更新至无人农场驿站口径。

## 可点击审阅

Figma提供4个起点：P0 · 首会话、P0 · 材料与矿洞、P0 · 厨房、P0 · 包裹与换装。跳转目标是包含中文审阅说明的顶层设计卡，因此呈现的是分镜演示。共有438个点击反应（含关闭返回）；不是实时游戏、可变库存或完整玩法模拟器。主流程和指定异常分支已连线，库存分类、每件外观试穿及所有列表行没有实现数据驱动交互。

## 规则与内容边界

采用 [玩法方案v2](../../product/gameplay-plan-v2-2026-10-02.md) 最新p(6)–p(9)。本批不擅自修改主方案里的未定规则。

| 项 | 本稿处理 | 待收口 |
|---|---|---|
| 首鱼XP | 按§14.2与§14.2.2账本50，累计前三鱼60 | §14.8.3步骤5仍写40，应统一；不能据旧40实现 |
| 老树/硬木 | 六点登记保留老树Lv3，硬木标后续内容 | §13.2与§17.2的P0“排除硬木”冲突；P0可见但不产出是本稿范围处理，需产品基线落字 |
| 第9份系统奖励 | 展示Parcels8/8与清理入口 | 8件已满后新增系统奖励如何保留未定义；不能覆盖旧包、丢弃或自动折现。**实现阻塞项** |
| 铜镐 | 两岩/挥、两岩4体力；不增加掉落承诺 | §13.3.1还有每岩2石料表述，需与§10.5“只省时间”统一 |
| 多灶/深矿/社交 | P1/P2边界；P0只单灶、矿洞1–2、被动系统奖励 | 原多灶并行需在P1单独展开 |

## 美术来源与保真范围

新卡的文字、按钮、图标、材料环、页签、网格与面板是Figma原生可编辑图层；73张场景填充都来自既有独立场景图，没有导入整张UI截图。颜色变量来自现有kit.css，字体Nunito；未找到匹配的已发布Gensen组件或Code Connect，故沿用现有源样式和SVG构建原生层。

场景仍是构图占位：厨房以现有中间灶裁切为单灶近景，不等于Lv1整屋新美术；矿洞两层共享mine-floor1，清层后背景岩石不作为运行状态；换装格共用衣架图，没有生成5套服装；地图不是地理校准图。P0 props的A/B候选未因此被选定。布局按360×800审阅比例（对应1080×2400基准）组织，真实短屏、动画和触控仍需实现验证。

## 验证

- 云端回读73卡、1,226个文本节点、73个纯场景图像填充；原生按钮/网格/材料环可编辑。
- 原型反应逐项核对目标存在并清除Bag自跳转；4个起点已保存。
- 13行完整画板截图逐组检查；修正文字高度、横排自适应、标题与关闭按钮、头像裁切、换装标签折行、Bag/Gear共用快捷栏、背包合法堆叠示例、材料/火候环及等级体力上限。
- 抽屉均在y≥125且底部≤780；本仓库仅改设计资料及COOK-3-2静态HTML，git diff --check通过。未运行游戏测试，因为本次没有运行代码变更。

## 设计卡索引

| 编号 | 标题 | 触发/结果与边界 |
|---|---|---|
| [TUT-1](https://www.figma.com/design/OMLTC3yw3u2WDjOZhLnhaR/Gensen--US-?node-id=399-2) | 选城 | 前置｜IP 预填，可搜索改城；选城不受迷雾限制。地图底图仅作构图示意。→ 建场。 |
| [TUT-1-2](https://www.figma.com/design/OMLTC3yw3u2WDjOZhLnhaR/Gensen--US-?node-id=399-25) | 建场确认 | 前置｜确认家城后建场；建场成功才进入农场。失败保留选城与选择，不重复创建。 |
| [TUT-3-01](https://www.figma.com/design/OMLTC3yw3u2WDjOZhLnhaR/Gensen--US-?node-id=399-75) | 01 · 落地 | 检查点 01｜0–3′。初级四工具已装备；Radish 已选；20 格已翻地。仅教学提示，不代操作。 |
| [TUT-3-02](https://www.figma.com/design/OMLTC3yw3u2WDjOZhLnhaR/Gensen--US-?node-id=399-151) | 02 · 播种与浇水 | 检查点 02｜Sow 每格 −2，共 −40；Water 免费。点田格不劳作，走位后按主行动键。 |
| [TUT-3-03](https://www.figma.com/design/OMLTC3yw3u2WDjOZhLnhaR/Gensen--US-?node-id=399-230) | 03 · 接教学委托 | 检查点 03｜3–5′。无人驿站，无 Bao 或问候卡。Track 后板 ! 消失，鱼塘图钉 ! 出现。 |
| [TUT-3-04](https://www.figma.com/design/OMLTC3yw3u2WDjOZhLnhaR/Gensen--US-?node-id=399-299) | 04 · 找到新手塘 | 检查点 04｜5–9′。位置芯片 → 塘卡 → Go。同城不弹 Travel；Show on map 只移动相机。 |
| [TUT-3-05](https://www.figma.com/design/OMLTC3yw3u2WDjOZhLnhaR/Gensen--US-?node-id=399-352) | 05 · 第一条鱼 | 检查点 05｜9–14′。前三次咬钩鲫鱼。首鱼按 §14.2.2 总账 +50；§14.8.3 的 40 为待修订矛盾。 |
| [TUT-3-06](https://www.figma.com/design/OMLTC3yw3u2WDjOZhLnhaR/Gensen--US-?node-id=399-415) | 06 · 失手与再试 | 检查点 06A｜故意错过提竿的支路。Lv1–3 前 10 次全退；保留委托与已钓鱼。 |
| [TUT-3-06B](https://www.figma.com/design/OMLTC3yw3u2WDjOZhLnhaR/Gensen--US-?node-id=399-472) | 06 · 三鱼准备齐 | 检查点 06B｜第 2、3 条各 +5，累计 60。保留第 3 条给烤鱼；同种鱼堆叠 10/格。 |
| [TUT-3-07A](https://www.figma.com/design/OMLTC3yw3u2WDjOZhLnhaR/Gensen--US-?node-id=399-531) | 07 · 交付 | 检查点 07A｜14–16′。只扣 2 鲫鱼，钱包 180→194。下一张为点厨房门、点灶台之后。 |
| [TUT-3-07B](https://www.figma.com/design/OMLTC3yw3u2WDjOZhLnhaR/Gensen--US-?node-id=399-584) | 07 · 第一锅 | 检查点 07B｜仅一口灶、2 投料槽。Cookbook 点 Cook 扣 1 鲫鱼；第 2.5 秒点场景锅，首轮金区 50%。 |
| [TUT-3-07C](https://www.figma.com/design/OMLTC3yw3u2WDjOZhLnhaR/Gensen--US-?node-id=399-654) | 07 · 吃回体力 | 检查点 07C｜Eat 路径 151→176，≤16′闭环。Keep 为可停支路，不伪称已经完成进食指标。 |
| [TUT-3-08](https://www.figma.com/design/OMLTC3yw3u2WDjOZhLnhaR/Gensen--US-?node-id=399-705) | 08 · 再种一轮 | 检查点 08｜16–18′。Today 完成补位；回田预选 Farming，点 Lettuce 后播 10 格：176→156。 |
| [TUT-3-09](https://www.figma.com/design/OMLTC3yw3u2WDjOZhLnhaR/Gensen--US-?node-id=399-779) | 09 · 等级门可理解 | 检查点 09｜第 4 次咬钩为 Fine；Lv1 挣脱不加 XP，退 5。等级／差距／后果／退款同屏。 |
| [TUT-3-10](https://www.figma.com/design/OMLTC3yw3u2WDjOZhLnhaR/Gensen--US-?node-id=399-834) | 10 · Fishing Lv2 | 检查点 10｜约22′，第5/6竿累计70–85 XP。礼物进 Bag，满包进 Parcels；快捷栏闪一次。 |
| [TUT-3-11](https://www.figma.com/design/OMLTC3yw3u2WDjOZhLnhaR/Gensen--US-?node-id=399-903) | 11 · 立刻用新能力 | 检查点 11｜22–25′。Lv2 后首次挂饵咬钩 Fine；193→213 奖励区，自然回复暂停。 |
| [TUT-3-12](https://www.figma.com/design/OMLTC3yw3u2WDjOZhLnhaR/Gensen--US-?node-id=399-964) | 12 · 第二锅与 Cooking Lv2 | 检查点 12｜25–28′。Common 鱼+香草，15s／第9s火候；Eat 灰显，Keep 留下 +45 的菜。 |
| [TUT-3-END](https://www.figma.com/design/OMLTC3yw3u2WDjOZhLnhaR/Gensen--US-?node-id=399-1019) | 会话结束与下次回来 | 28–30′停点｜Fishing110–125、Cooking45、体力213。时间是观察窗口，不定时弹剧情。 |
| [MAT-1](https://www.figma.com/design/OMLTC3yw3u2WDjOZhLnhaR/Gensen--US-?node-id=402-2) | 六个采集点 | §13.2 总览／审阅导航，不新增采集菜单。场景点位 Ready 可点。老树可见；硬木属 P1，P0 不产出。 |
| [MAT-2](https://www.figma.com/design/OMLTC3yw3u2WDjOZhLnhaR/Gensen--US-?node-id=402-97) | 点击采集 → 自动入库 | 点场景树林，一次收完直接入仓；0体力0XP。Ready 变独立8小时计时；Bag满也可采集。 |
| [MAT-3](https://www.figma.com/design/OMLTC3yw3u2WDjOZhLnhaR/Gensen--US-?node-id=402-150) | 采集冷却与等级门 | 计时点不重复收取。点未开放黏土溪岸显示等级／差距／后果；来源信息按需打开。 |
| [MINE-P0-1](https://www.figma.com/design/OMLTC3yw3u2WDjOZhLnhaR/Gensen--US-?node-id=402-200) | 矿口 · 首次进入 | 固定矿口，走近主行动键进入；只付第1层2体力。工作台另点，不设 Explore 菜单。 |
| [MINE-P0-2](https://www.figma.com/design/OMLTC3yw3u2WDjOZhLnhaR/Gensen--US-?node-id=402-274) | 第一层 · 逐岩开采 | 每岩2，6岩12；本层合计14。岩石不响应点击；Mining已选，1–2层无Combat主按钮。 |
| [MINE-P0-3](https://www.figma.com/design/OMLTC3yw3u2WDjOZhLnhaR/Gensen--US-?node-id=402-350) | 清层与第二层层费 | 楼梯亮起；第一次进2层扣2，同局已付层往返免费。素材是Floor1共享底图，非Floor2专属美术。 |
| [MINE-P0-4](https://www.figma.com/design/OMLTC3yw3u2WDjOZhLnhaR/Gensen--US-?node-id=402-393) | 第二层 · 铜与岩盐 | 火把预览固定掉落，−1火把，0体力；选回Mining敲岩。2层清完全局总耗28，0技能XP。 |
| [MINE-P0-5](https://www.figma.com/design/OMLTC3yw3u2WDjOZhLnhaR/Gensen--US-?node-id=402-469) | 续局与免费往返 | 中途离矿保留进度，续局落最深已付层，不再收层费。未清2层不可重开，已入包材料保留。 |
| [MINE-P0-6](https://www.figma.com/design/OMLTC3yw3u2WDjOZhLnhaR/Gensen--US-?node-id=402-512) | P0两层清完 | P0只呈现1–2层，清2层不伪称精英Run complete。电梯0；回农场材料自动入库。 |
| [MINE-P0-7](https://www.figma.com/design/OMLTC3yw3u2WDjOZhLnhaR/Gensen--US-?node-id=402-566) | 可重开 · 明示后果 | 已清2层才可重开；计第2局，所有层费重算。确认卡为本批交互方案，避免误丢当前局进度。 |
| [MINE-P0-8](https://www.figma.com/design/OMLTC3yw3u2WDjOZhLnhaR/Gensen--US-?node-id=402-618) | 满包、日上限与日切 | 三状态规则板：主动挖矿满包阻止；2/2只限制新局、不挡续局；04:00结束旧局，材料不丢。 |
| [CRAFT-1](https://www.figma.com/design/OMLTC3yw3u2WDjOZhLnhaR/Gensen--US-?node-id=402-680) | 工作台 · Tools不足 | 点工作台打开。材料全用环形进度格；从Farm Storage扣，缺口只写按钮，点材料格才看来源。 |
| [CRAFT-2](https://www.figma.com/design/OMLTC3yw3u2WDjOZhLnhaR/Gensen--US-?node-id=402-748) | 铜镐制作成功 | 足料→Craft→获得铜镐。工具不占Bag；不自动替换当前镐，成功态给Equip入口。 |
| [CRAFT-3](https://www.figma.com/design/OMLTC3yw3u2WDjOZhLnhaR/Gensen--US-?node-id=402-808) | 工作台 · Supplies | 火把1木1芦→2、堆肥2芦1木→2；均0金币。产物在家仓库存储，带出门Take；炸药属P1不列P0。 |
| [CRAFT-4](https://www.figma.com/design/OMLTC3yw3u2WDjOZhLnhaR/Gensen--US-?node-id=402-889) | 采集手套 · 被动生效 | 做出即被动生效，不进Gear六槽，不新增装备槽。副产蚯蚓不随主材料+1；再次制作不可重复叠加。 |
| [GEAR-P0-1](https://www.figma.com/design/OMLTC3yw3u2WDjOZhLnhaR/Gensen--US-?node-id=402-960) | 制作后 → 装备铜镐 | Craft成功经同一Bag/Gear抽屉进入Mining槽；旧镐保留。Gear无容量条，工具不入Tackle。 |
| [GEAR-P0-2](https://www.figma.com/design/OMLTC3yw3u2WDjOZhLnhaR/Gensen--US-?node-id=402-1061) | 已装备与劳作后果 | 装备标识即时改；主行动键徽标同步。两岩4体力，不能显示一次两岩只扣2；资料石料加成冲突另列。 |
| [HOME-P0-1](https://www.figma.com/design/OMLTC3yw3u2WDjOZhLnhaR/Gensen--US-?node-id=402-1118) | 材料 → 农场升级 | 第5天独立示例，需Farming+Fishing技能和与金币同时满足；Cooking不计入。材料数字取§8.2.1。 |
| [COOK-P0-1](https://www.figma.com/design/OMLTC3yw3u2WDjOZhLnhaR/Gensen--US-?node-id=406-2) | 新手厨房 · 单灶 | 场景灶台点击打开Cookbook。厨房无主行动键、切换键或五格快捷栏；单灶镜头，新增整屋美术另计。 |
| [COOK-P0-2](https://www.figma.com/design/OMLTC3yw3u2WDjOZhLnhaR/Gensen--US-?node-id=406-55) | Experiment · 两槽投料 | 点击格入场景锅；锅下两槽，×撤回。投料预览不扣料，Cook才扣；第3槽Cooking Lv4，不画额外灰槽。 |
| [COOK-P0-3](https://www.figma.com/design/OMLTC3yw3u2WDjOZhLnhaR/Gensen--US-?node-id=406-152) | 场景锅 · 火候 | 首次5s锅在2.5s出现火候，点场景锅。此按钮是可点击原型热区说明，产品不新增劳作FAB。 |
| [COOK-P0-4](https://www.figma.com/design/OMLTC3yw3u2WDjOZhLnhaR/Gensen--US-?node-id=406-212) | 满包 · 菜留在灶上 | 主动烹饪结果不进Parcels。菜不消失，单灶占用，不能再开火；满体力不以Eat绕开。 |
| [COOK-P0-5](https://www.figma.com/design/OMLTC3yw3u2WDjOZhLnhaR/Gensen--US-?node-id=406-265) | Lv2 · 调味架储物 | 只储物、不解投料槽。Cooking Lv1仍2槽，Lv4才3槽；四类调味容量每类30，P0展示已有盐与香草。 |
| [COOK-P0-6](https://www.figma.com/design/OMLTC3yw3u2WDjOZhLnhaR/Gensen--US-?node-id=406-335) | Lv3 · 保温柜领取 | 柜里可直接吃；取包需空格。6份按份数计，柜满且Bag满则留灶。新手Lv1不显示柜。 |
| [COOK-P0-7](https://www.figma.com/design/OMLTC3yw3u2WDjOZhLnhaR/Gensen--US-?node-id=406-401) | Cook Again · 有料 | Cooking Lv2才显示；先收走上锅且有空闲灶，再次按下才扣料。2nd half XP；第3锅No XP提示。 |
| [COOK-P0-8](https://www.figma.com/design/OMLTC3yw3u2WDjOZhLnhaR/Gensen--US-?node-id=406-465) | Cook Again · 缺料 | 缺料不先扣现有材料。Show pond仅地图高亮；不传送、不自动钓鱼。 |
| [STORE-1](https://www.figma.com/design/OMLTC3yw3u2WDjOZhLnhaR/Gensen--US-?node-id=406-531) | 农场仓库 · 带出门 | 仓库不限格每堆99；材料／种子／肥料／火把／摆件回家入库。鱼、作物、料理不自动入库。Take受Bag可容纳数裁剪。 |
| [STORE-2](https://www.figma.com/design/OMLTC3yw3u2WDjOZhLnhaR/Gensen--US-?node-id=406-631) | 离家 · 仓库只读 | 在外只读，不凭空取物；返回农场再Take。回家引导是明确Go home，不冒充Show on map。 |
| [COOK-P0-9](https://www.figma.com/design/OMLTC3yw3u2WDjOZhLnhaR/Gensen--US-?node-id=406-686) | 留灶后 · 空位再领取 | 从Bag整理返回保留同一道菜、品质和数量；Keep成功才清灶，再允许Cook Again。 |
| [COOK-P0-10](https://www.figma.com/design/OMLTC3yw3u2WDjOZhLnhaR/Gensen--US-?node-id=406-738) | 火候三态 · 修订替代稿 | 替代旧COOK-3-2主操作示意。无Cook · Free、无切换FAB；多灶并行属于P1，沿用旧火候节奏说明。 |
| [BOARD-1](https://www.figma.com/design/OMLTC3yw3u2WDjOZhLnhaR/Gensen--US-?node-id=407-2) | 无人驿站 · 已追踪 | 首会话2槽；第二槽72h为新手特例。Tracked物品受Sell All保护；点棚即进交易，无人像。 |
| [BOARD-2](https://www.figma.com/design/OMLTC3yw3u2WDjOZhLnhaR/Gensen--US-?node-id=407-71) | 交付成功 · 四小时补位 | 普通完成槽4h补位；到账、扣物、Done一起发生。日6份合并计数；不重复点领同份奖励。 |
| [BOARD-3](https://www.figma.com/design/OMLTC3yw3u2WDjOZhLnhaR/Gensen--US-?node-id=407-134) | 放弃与每日上限 | 放弃8h；普通未接72h换单，已追踪永不过期。底部日满额为独立状态文案，不算放弃后额度增加。 |
| [TODAY-1](https://www.figma.com/design/OMLTC3yw3u2WDjOZhLnhaR/Gensen--US-?node-id=407-186) | Today · 完成后补位 | 完成行短暂打勾后补位，始终≤3行；可立即做优先。不加全部完成奖励；Show只相机高亮，仍需点灶。 |
| [TODAY-2](https://www.figma.com/design/OMLTC3yw3u2WDjOZhLnhaR/Gensen--US-?node-id=407-252) | Today · 结束与低体力 | 首会话结束三行。低体力变体：Sow10→needs20 Energy · +8 in21m，不隐藏、不灰掉；不催花光体力。 |
| [BAG-1-P0](https://www.figma.com/design/OMLTC3yw3u2WDjOZhLnhaR/Gensen--US-?node-id=407-322) | Bag · 七类统一容量 | 25格密度状态：五列五行、22/25、7分类横向滑动。工具仅在Gear，Tackle计容量；首行快捷栏见原BAG-1，切页保持选择。 |
| [PARCEL-1](https://www.figma.com/design/OMLTC3yw3u2WDjOZhLnhaR/Gensen--US-?node-id=407-593) | 包裹 · 正常领取 | HUD铃铛、农舍信箱同入口，非两容器。P0只成就/委托/升级被动奖励，赠礼和首访例留P2。 |
| [PARCEL-2](https://www.figma.com/design/OMLTC3yw3u2WDjOZhLnhaR/Gensen--US-?node-id=407-672) | 已领 · 列表与角标更新 | 只在领取成功后移除、更新Bag与待操作角标。重复点击不能再次入账；并发容量变化重检。 |
| [PARCEL-3](https://www.figma.com/design/OMLTC3yw3u2WDjOZhLnhaR/Gensen--US-?node-id=407-734) | 满包 · 领取门禁 | 不挤出原Bag物品，不弹Keep which。整理返回保留待领包裹与倒计时；允许空间范围内部分批量领取。 |
| [PARCEL-4](https://www.figma.com/design/OMLTC3yw3u2WDjOZhLnhaR/Gensen--US-?node-id=407-795) | 包裹满额 · 8/8 | 覆盖现有8/8状态。第9份系统奖励去向在基线未定义，不能虚构覆盖或丢弃；实现前须补规则（阻塞项）。 |
| [PARCEL-5](https://www.figma.com/design/OMLTC3yw3u2WDjOZhLnhaR/Gensen--US-?node-id=407-856) | 到期 · Updates回执 | 可回收品折现、不占回收额度，示例+18。P2赠礼到期退回、区域种子到期丢失另列，不混入P0奖励。 |
| [PARCEL-6](https://www.figma.com/design/OMLTC3yw3u2WDjOZhLnhaR/Gensen--US-?node-id=407-921) | 被动奖励 → 铃铛与信箱 | 2秒铃铛下飘条、铃铛+1、家中信箱Parcel小牌。此卡主行动键仍劳作；包裹只能点铃/信箱进入。 |
| [PROFILE-1-P0](https://www.figma.com/design/OMLTC3yw3u2WDjOZhLnhaR/Gensen--US-?node-id=407-995) | Profile · P0入口 | HUD头像/地图Me → Profile，Edit look →换装。P2关系等入口沿PROFILE-1，不在P0假装已实现。 |
| [KEEP-P0-1](https://www.figma.com/design/OMLTC3yw3u2WDjOZhLnhaR/Gensen--US-?node-id=407-1034) | 换装 · 预览与保存 | 沿用现有换装逻辑，选择只预览，Save成功回Profile；Cancel保留旧外观。服装格共用占位图，未声称专属资产。 |
| [KEEP-P0-2](https://www.figma.com/design/OMLTC3yw3u2WDjOZhLnhaR/Gensen--US-?node-id=407-1090) | 保存后返回个人页 | 保存成功回Profile，同一外观同步HUD与场景；不经过Gear、不加Outfit Tab。失败状态保留预览可Retry。 |
| [ENERGY-P0-1](https://www.figma.com/design/OMLTC3yw3u2WDjOZhLnhaR/Gensen--US-?node-id=407-1110) | 低体力 · 只引导 | 统一Energy Card，不写预测Eat+40，不替玩家吃/休息。零体力仍能离矿、坐电梯，免费支路可退出。 |
| [COOK-KEEP-BRANCH](https://www.figma.com/design/OMLTC3yw3u2WDjOZhLnhaR/Gensen--US-?node-id=407-1183) | 首锅选择Keep的支路 | 未Eat则没有+25，不能套用176/213标准路径。Today保留进食提醒；完成观察指标取实际操作。 |
| [SAVE-RETRY](https://www.figma.com/design/OMLTC3yw3u2WDjOZhLnhaR/Gensen--US-?node-id=407-1237) | 保存失败 · 可恢复 | 网络失败保持预览；Retry幂等保存，只有成功才出Look saved。关闭前Cancel放弃本次预览，不丢旧外观。 |
| [BOARD-DROPPED](https://www.figma.com/design/OMLTC3yw3u2WDjOZhLnhaR/Gensen--US-?node-id=407-1261) | 放弃成功 · 八小时补位 | 放弃分支：不加金币、不记一次完成；只该槽进入8h补位，Today移除追踪。 |
| [COOK-HERB-HEAT](https://www.figma.com/design/OMLTC3yw3u2WDjOZhLnhaR/Gensen--US-?node-id=407-1310) | 香草鱼 · 再做火候 | Cook Again实际仍是香草烤鱼15s、9s火候；不会错误回到烤鲫鱼5s的状态。 |
| [MAT-GLOVES-RESULT](https://www.figma.com/design/OMLTC3yw3u2WDjOZhLnhaR/Gensen--US-?node-id=407-1370) | 手套制作后 · 增量可见 | 制作即被动生效；现有冷却不提前刷新。下一次采集主材料+1，不给蚯蚓副产追加奖励。 |
| [FISH-P0-CAST](https://www.figma.com/design/OMLTC3yw3u2WDjOZhLnhaR/Gensen--US-?node-id=407-1424) | 到塘 · 抛竿与开局空饵 | 地图Go后真实落点。Fishing自动预选，五个幽灵格，仅鱼饵候选不放鱼竿；按Cast预扣5。 |
| [MINE-CONTINUE](https://www.figma.com/design/OMLTC3yw3u2WDjOZhLnhaR/Gensen--US-?node-id=407-1498) | 续局 · 原进度恢复 | 从4/6离场恢复4/6，不复活石头、不重收层费；材料回家入库后继续。 |
| [BUILD-RETRY](https://www.figma.com/design/OMLTC3yw3u2WDjOZhLnhaR/Gensen--US-?node-id=407-1572) | 建场失败 · 保留选择 | 建场请求失败保留选择；重复提交必须复用创建幂等标识。未知成功状态先查询，不能生成第二座农场。 |
| [PARCEL-ONE](https://www.figma.com/design/OMLTC3yw3u2WDjOZhLnhaR/Gensen--US-?node-id=419-2) | 单件领取后 · 继续领取 | 单件Claim成功只移除这一包；原3/8→2/8，Bag22→23，另外两件倒计时继续。 |

## 文件维护

`figma/all-screens.json`是本轮文案/状态清单；`figma/build.js`与分组JSON保留初稿构建来源（后续修订以Figma节点与回读记录为准），节点回执和原型连线在相邻JSON中。构建脚本有重复卡拦截，且引用已存在的Section与资源ID；后续应针对已知节点修订，不要全量重跑生成重复卡。`final-audit.json`记录最终节点映射与修正。
