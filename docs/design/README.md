# 设计稿与素材索引

玩法、数值、文案和分期以 [玩法方案 v2](../product/gameplay-plan-v2-2026-10-02.md) 为准。原型文件为 [Figma · Prototype](https://www.figma.com/design/OMLTC3yw3u2WDjOZhLnhaR/Gensen--US-?node-id=310-2955)，file key `OMLTC3yw3u2WDjOZhLnhaR`，page `310:2955`。

## 当前 UI 与 P0 美术

- [本轮 UI 设计审阅清单](ui-refactor-2026-10-06/REVIEW.md)：美术总监、产品经理和实现负责人的审阅入口；标明当前 Figma 页、组件架构、最终证据与未完成动作。
- [全量 UI 语义重构（2026-10-06）](ui-refactor-2026-10-06/README.md)：288 张主卡已写入独立 Figma 审阅页，保留原 Prototype；另有 23 张独立补态（4 张流程修复＋15 张操作结果＋4 张免费旅行分支均有云端回执）。复用原背包规格、真实 Avatar 与组件属性／变体；已有实际截图和连线复核，**不代表全部最终视觉或游戏实现通过，本轮图稿与组件复核完成；未模拟动作见 ledger**。
- [后续设计与组件整理（2026-10-06）](p1-p2-flows-2026-10-06/README.md)：08–12新增131张P1/P2/P3页面与状态稿；13内容样式板；00B/00C共享组件。**后续出图先复用已完成设计和组件规格**，以原BAG-1/BAG-2、Section00及kit样式为依据。07背包的样式偏差已修正，见[组件维护说明](p1-p2-flows-2026-10-06/COMPONENTS.md)。
- [07 · P0流程与状态收口](p0-flow-2026-10-05/README.md)：新增73张可编辑Figma分镜与状态卡、4个审阅起点；首会话、材料制作、厨房、包裹与Profile往返。包含未定规则和共享美术边界，不表示P0全部完成。
- [P1逐项资产登记](p0-flow-2026-10-05/P1-ASSET-REGISTER.md)：20作物、20鱼、48料理、12居民逐项列出来源与缺口；P2免费旅行与P3后续顺序。
- [UI 有效稿索引](ui-anchors-2026-10-03/REPORT.md)：当前源页、基础锚定图、批次1/2与最新修订说明。
- [最新基础锚定图](ui-anchors-2026-10-03/out/current/)：FARM-1、FISH-1、COOK-1、BAG-1；从旧版本目录归一，图片内容未修改。Bag 的新 Gear 页以 batch2/BAG-2 为准。
- [P0 道具与室内候选](p0-props-2026-10-05/)：厨房、灶台、渔具铺、摊位/长椅、Kai 与入口图标。候选 A/B 尚不能因清理被自动视为已选定。
- [用户美术参考](art-style-reference-2026-09-23/README.md) 及 [农场资产来源](farm-art-2026-09-10/README.md)、[矿洞美术](mine-art-2026-09-24/README.md) 保留。

最新交互采用无人 Homestead Stall、Profile 主入口、Bag | Gear、奖励进入 Inbox Parcels、场景里的3D灶台和 Cookbook/Experiment、仅引导的 Energy Card。独立 EQUIP-1、Bao 问候卡、Keep which?、旧 Recipes 列表/抽屉内2D锅已作废。

## 地图与水体

- 地图/地标制作与来源：la-map 系列、landmark-scenes、landmark-3d-griffith、griffith-rebuild、shanghai-landmarks、maki-icons。它们用于保留的地图交互与美术管线，不重新定义岗位据点或当前 HUD。
- `la-map-round9-2026-09-23/mockups/farm-restyle-mockup-v1.png` 保留为当前农场/池塘生图的美术参考，旧 UI 不作为验收稿。
- 水体现行技术：[泡沫](pond-foam-2026-09-30.md)、[焦散动态修订](pond-caustics-motion-2026-09-30.md)、[纹理阈值高光](pond-water-breakdown-2026-09-30/README.md)。更早 pond 目录保留参考、制作来源与对照证据，参数被后续文档取代时以修订记录为准。
- `tools/p0/extract_icons.py` 仍读取 `ui-anchors-2026-10-03/ui/icons*.svg`；水体比对与地标预览工具仍读取部分 docs 图像，均保留。

## 历史材料

farm-ui-2026-09-05 和 game-ui-2026-09-21 只保留生产素材来源与实际 QA，旧概念图已清理。各历史目录中的 QA 不是 v2 完成证据。清理不影响 Figma 云端画板、运行代码、生成脚本或运行资产；逐文件处理与恢复方式见 [清理记录](../design-cleanup-2026-10-05.md)。
