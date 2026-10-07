# 全量 UI 语义重构 · 2026-10-06

给美术总监、产品经理和实现负责人的本轮入口：[设计审阅清单](REVIEW.md)。当前权威是 Figma 的 `14 · UI semantic refactor` 页面；各阶段截图按其日期与范围使用。

本轮依据用户要求，检查全部现有设计卡，并把身份、数量、效果、状态、成本与动作拆成稳定的组件字段。保留 Nunito、奶油底、圆角、原物品图标和场景资产；保留背包五列、装备六槽及五格消耗品快捷栏的既有规格。

**状态：本轮图稿重构、组件整理与截图复核已完成。** [Figma 审阅页](https://www.figma.com/design/OMLTC3yw3u2WDjOZhLnhaR/Gensen--US-?node-id=481-53) 已写入全部 288 张主卡，保留原 Prototype。另有 **23 张独立业务补态**：4 张流程修复态、15 张交易／装备／储物／进食结果态和 4 张免费旅行分支；还补了独立作物图鉴页。结果关闭后的场景、Avatar 保存／再次编辑与原型覆盖层属于支持节点，另计。

原稿 84 张重构后可见界面最终检查通过；后续 204 张均做实际截图审查，并完成发现问题的修复及针对性后验。背包、HUD、厨房、换装、柜台和短内容抽屉按原稿比例精修。各组记录区分初检、修改后截图与结构回读，不把一张标杆图扩大为整组逐图最终通过。

**仍有 36 个唯一原型动作未模拟或尚未绘制结果态**，见 [动作缺口记录](figma-plugin/prototype-gap-ledger.json)；这些入口没有伪造成功。图稿完成不等于全玩法、内容美术或游戏实现完成。本地浏览器不可用，完整原型实点、真机运行与真实结算未据此宣称通过。


## 2026-10-07 复核：快捷栏与 Overlay

根据新增审图反馈，40 处完整快捷栏（200 物品槽、40 个末端入口）已统一到同一组槽位与 Bag / Close 主组件，并逐张截图通过。非空槽均显示图标、两行名称、独立的 `×N` 数量；空槽、选中上抬、Pin 暖底／顶条／徽标及容量提醒统一。补齐 PARCEL-6、LOCAL-FISH 的空快捷栏。4 张 Buff 页的 14 项库存补为明确的设计示例，来源记录在 `data/toolbar-fixture-provenance.json`，不是玩家库存。

- [统一组件与实例示例](https://www.figma.com/design/OMLTC3yw3u2WDjOZhLnhaR/Gensen--US-?node-id=925-71414)
- [40 张逐图验收](cloud/toolbar-unification/visual-review.json) · [结构回读](cloud/toolbar-unification/final-toolbar-audit-result.json)
- [组件最终截图](cloud/toolbar-unification/toolbar-component-examples-final.png)

Overlay 是原型弹窗／状态目标，不是一张一个新组件。本次基于完整内容、样式、变量和行为匹配，重定向入口后删除 138 个精确重复副本。576 个信息弹窗共用既有 Sheet / ObjectHeader / Dismiss，按内容缩高；仅长内容保留滚动。735 个存活弹窗（信息 576、交互状态 99、反馈 60）已分组到页面右侧三个 Section。最终检查重复、不可达、断链与损坏实例均为 0，288 张主卡完整。详见 [弹窗视觉与引用验收](cloud/toolbar-unification/overlay-review.json) 和 [最终回读](cloud/toolbar-unification/final-overlay-audit-result.json)。原 Prototype 和游戏实现未修改。


## 2026-10-07 组件族与上游复用

进一步按结构复用：576 个信息弹窗及 84 个 Pin 状态共用一个 InformationSheet 主件，60 个反馈窗共用 Feedback 主件；685 个正文段落共用 Paragraph。正文长度通过原生 Content Slot 组合，Apple／Carp、库存和价格均为实例内容，不按物品或数量新增变体。

- [Figma 组件架构与维护入口](https://www.figma.com/design/OMLTC3yw3u2WDjOZhLnhaR/Gensen--US-?node-id=946-76647)
- [组件分类与复用总结](COMPONENT-FAMILIES.md) · [222 个主件与 25 个组件集目录](cloud/component-consolidation/family-catalog.json)
- [720 窗口内容与反应守恒检查](cloud/component-consolidation/migration-validation-summary.json) · [全局连线完整性](cloud/component-consolidation/final-integrity-result.json)

实际上游间距 12→16→12 试验确认 Apple／Carp 数量窗、Pin 和图鉴同步变化并恢复；不同内容和业务动作不变。13 类标杆做了截图检查，735 个原型 Overlay 全部可达，288 张主卡完整。15 个场景／教学覆盖层保留专用结构；跨页仍被引用的 Legacy 主件保留兼容。详细边界与后续修改方法见总结。

## 查看与审阅

- [Figma 重构审阅页](https://www.figma.com/design/OMLTC3yw3u2WDjOZhLnhaR/Gensen--US-?node-id=481-53) 与本目录的实际 PNG 是本轮视觉审阅依据。
- [本地结构审阅稿](preview/review-offline.html)：包含 84 张旧稿与 204 张后续流程稿，共 288 张主卡；另接入独立补态，数量以 `preview/build-report.json` 为准。Avatar 三张正式页已同步专属布局；保存失败等补态与其余页面尚未完整同步全部视觉精修，仅用于字段与流程结构检查。数据、样式和脚本已内嵌，可在本仓库内用浏览器打开；场景图片仍引用仓库相对路径，因此单独拷出 HTML 不能保留全部图片。
- [组件视觉方向](review/component-direction.png)：洒水器、旅行、邀请三种决策结构的本地概念示例。它是规范示意，不是 Figma 导入后的截图。
- [审查报告](AUDIT.md)、[84 张旧稿现场视觉复核](VISUAL-LEGACY.md)、[204 张后续稿语义核查](CURRENT-AUDIT.md)。这些现场截图是重构前的证据。
- [84 张旧稿重构后最终视觉验收](cloud/rows/LEGACY-FINAL-REVIEW.md)：84/84 可见界面通过，待修项为 0；逐卡 ID 与截图哈希见 [验收记录](cloud/rows/legacy-final-visual-review.json)。长目录滚动和所有原型路径尚未逐项实点。
- [P2/P3 的 80 张实际截图审查](cloud/p2p3-visual-review.json)：包括 7 张短抽屉标杆的修改后截图；68 张抽屉已推广，674 条反应保持不变，不把此结构检查扩大为 68 张逐图最终验收。
- [信息与交互契约](CONTRACT.md)、[验收清单](data/review-checklist.json)、[设计 tokens](data/tokens.json)。
- [背包前轮视觉对照](cloud/bag-visual-comparison.svg)、[前轮背包截图](cloud/bag-polish-final.png)、[Seeds 筛选截图](cloud/bag-polish-seeds.png)：记录原稿比例与筛选检查；最新快捷栏见 [BAG-1](cloud/toolbar-unification/BAG-1-after.png)及[40 页验收](cloud/toolbar-unification/visual-review.json)。
- [换装与 Profile 最终对照](cloud/avatar/avatar-final-review.svg)：真实角色预览、五类原图标、三列部件网格；386 条有效连线回读无错误，31 处再次编辑正确重置。详见 `cloud/avatar/polish-state.json`。另有 [保存失败／继续编辑两态验收](cloud/avatar/recovery-review.json)，确认错误面板关闭后保留同一个真实 Silver Crop 草稿。
- [前轮共享组件库整理截图](cloud/component-library-organized.png)：六个功能组、原资产图标板与完整衣柜变体库；最新归类与上游复用见[组件总结](COMPONENT-FAMILIES.md)及[架构指南截图](cloud/component-consolidation/component-architecture-guide.png)。
- [商店与背包精修](cloud/legacy-shop-review.json)：复用原柜台与五列格，商品名称、门槛、库存、价格分离，购买与查看详情具有不同外观。
- [免费旅行连续性验收](cloud/free-travel-qa/review.json)：9 张实际截图及 11 帧资源／12 条路线回读通过；浏览、购买、钓鱼、返乡保持各分支自己的资源。
- [原生 Figma 导入包说明](figma-plugin/README.md)、[本地构建验证](figma-plugin/local-validation.json)、[未完成原型目标记录](figma-plugin/local-destination-warnings.json)。云端分批写入回执见 `cloud/state.json`；本地 Plugin API mock 只验证构建，不作为云端执行证明。

## 重构规则

1. 标题只表示名称。数量独立右对齐；状态、来源、核心效果各有字段。库存格保留图标和数量，名称与作用在选中项详情显示。
2. 决策前常驻呈现实际所得、成本、付费者、替换损失、到期和容量去向；重复规则进入详情，普通操作失败使用可处理的反馈。
3. 执行使用深绿主按钮；导航使用无填充文字与箭头；取消/关闭使用安静文字；危险操作明确后果。一个页面最多一个主要执行操作。
4. 通用页使用 20 标题、14 正文及至少 12 的辅助文字。原稿紧凑容器使用独立 Compact 规格：物品标题 14、核心效果 12、核心动作至少 12、分类与数量 10–11；仅QuickSlot 辅助物品名、GearSlot 只读标签、Profile ID、社交统计标签、集合／图鉴格 caption允许 9。不得把此例外推广到普通正文、核心数量或动作。主要执行触区至少 44；长内容滚动，不机械缩小字号。
5. 共用 ObjectHeader、Quantity、Effect、Fact、Cost、NeedTile、ItemRow、InventoryCell、GearSlot、HUD、Sheet、Command、NavigationRow、Dismiss、Toast。纯场景图片允许复用，完整 UI 截图不进入新页面。
6. 分镜跳转和未定规则写在设备画面外；不能把“查看下一个状态”伪装成游戏行为，也不能给缺少结果页的操作伪造成功。

## 范围与来源

玩法与数字以 [玩法方案 v2](../../product/gameplay-plan-v2-2026-10-02.md) 的最新修订为准。288 张设计卡包含状态变体与组件参考表，不代表 288 个独立产品页面，更不代表 P0–P3 的内容美术或实现已完成。

| 来源 | 数量 | 映射 |
|---|---:|---|
| Prototype 的 00–06 旧稿 | 84 | [旧稿语义数据](data/legacy-screens.json)，其中 83 张原为图片，1 张是修订后的可编辑 COOK-3-2 |
| 07 P0 流程与状态 | 73 | [P0 数据](data/current-07.json) |
| 08–12 P1/P2/P3 后续稿 | 131 | [全部后续稿数据](data/current-all.json) |

每张卡保留原 ID。旧稿用 `figmaNodeId` / `sourceHtml` 记录来源，后续稿用 `sourceRef`；适用页面另记录 `reviewOnly`、`reviewActions`、`unresolvedRules`。旧稿的 `items` 是语义行，原库存格由 `gridItems` 表达；不能把两者混用。导入时创建独立新审阅页，保留原节点，新的节点映射须以实际导入产生的 ledger 为准。

当前验证包括语义数据、原图来源、脚本语法、模拟 Plugin API 构建、云端回执和实际 Figma 截图。84 张旧稿重构后可见界面均已完成最终截图验收。后续 204 张卡分为 P0/P1 的 124 张与 P2/P3 的 80 张完成实际图审查；发现问题已修正并做针对性后验，具体修改后截图与结构回执按各组记录。Avatar 三张正式页与专属连线已完成回读。其余最终视觉覆盖以各回执和截图记录为准，不能由 288/288 写入数推导全部通过。

共享库包含通用语义组件与原稿紧凑组件，保留真正的实例引用、文本／图标属性和状态变体。`cloud/organize-library.js` 仅整理新审阅页的库、缩略图和素材位置；执行前后检查组件属性、实例引用和支持帧位置。实际整理回执为 `cloud/organize-library-result-1791308126560.json`：212 个组件、25 个组件集、11,636 条实例引用保持；组件属性零变更，支持帧零位移，库所在区域无重叠。组件按换装、厨房、信息、行动与选择、容器与物品、游戏状态六组整理，资产与 30 个衣柜变体另设专区。另分两次清理 1,249 个不可达旧覆盖层副本；当前连线以最终原生回读记录为准。

独立补态来源为 `data/flow-repair-states.json`（4 张）、`data/legacy-npc-flow-states.json`（15 张）与 `data/free-travel-flow-states.json`（4 张）。23 张业务补态均已有实际写入回执；15 个操作后场景与 3 个免费旅行返乡场景是结果的关闭去向，属于支持节点，不再重复算作业务状态。它们修复具体操作前后状态，不改变主卡统计，也不表示游戏后端已实现这些操作。

## 维护

- 后续稿字段：`data/current-all.json` 与分区文件同步维护；旧稿字段：`data/legacy-screens.json`。
- 本地预览：编辑 `preview/review.js` / `review.css`，运行 `python3 preview/build_preview.py`。
- 原生组件与页面组装：编辑 `figma-plugin/src.js`，按其 README 构建验证，再重打包。
- 确认新稿云端验收前，不删除旧稿，不将本地概念图称为 Figma 回读，不修改游戏运行、发布或存档数据。
