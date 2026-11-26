# 设计稿与素材索引

玩法、数值、文案和分期以 [玩法方案 v2](../product/gameplay-plan-v2-2026-10-02.md) 为准。当前游戏 UI 设计稿为 [Figma 页面 14 · UI semantic refactor](https://www.figma.com/design/5SVgfevrLzZXqD83uyPgmV/Gensen_US_2026?node-id=5-4)，file key `5SVgfevrLzZXqD83uyPgmV`，page `5:4`（R1 修订中，锁定项以 [锁定组件清单](../governance/locked-components.md) 为准）；旧 [Figma · Prototype](https://www.figma.com/design/5SVgfevrLzZXqD83uyPgmV/Gensen_US_2026?node-id=5-3)（page `5:3`）为 Archive，截至 2026-10-06。

## 当前 UI 与 P0 美术

- [Art environment setup](art-environment-setup.md): start here on a fresh host; toolchain, Git access, Figma MCP, Windows/remote OAuth callbacks, Lark CLI application/user authorization and readiness checks.
- [Mobile 3D asset workflow](mobile-3d-asset-workflow.md): English production guide for agents, based on the accepted Basic Room; reference analysis, reusable modeling, atlases, mobile budgets, Godot/Android checks and verified delivery.
- [Basic Room (2026-10-06)](basic-room-2026-10-06/README.md): user-accepted Blender assets, reusable Godot room, offline movement benchmark and Android checks; includes committed review images and an evidence summary. Not a production release.
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
