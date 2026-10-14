# 设计稿与素材索引

玩法、数值、文案和分期以 [玩法方案 v2](../product/gameplay-plan-v2-2026-10-02.md) 为准。原型文件为 [Figma · Prototype](https://www.figma.com/design/OMLTC3yw3u2WDjOZhLnhaR/Gensen--US-?node-id=310-2955)，file key `OMLTC3yw3u2WDjOZhLnhaR`，page `310:2955`。

## 当前 UI 与 P0 美术

- [刘备 · 布告栏 SGODOT-284](notice-board-284-2026-10-13/README.md)：Lv5 独立双柱布告栏，v1.1 真实尺寸、原值顶点色、种子箱/井零交叠验证与三张 Godot 图；目标 0.2.6 之后，待双审。
- [刘备 · 名厨招牌 SGODOT-282](chef-sign-282-2026-10-13/README.md)：v1.3 朝左木作/石作两款，吊牌收窄至 0.50 m；含 (4,14) 路格 / (5,14) 锚点格截图、7.7 cm 悬挑说明和可复现源文件，交哪吒接入检查。
- [刘备 · 铁匠铺烟 R2.5](blacksmith_shop-smoke-r25-2026-10-08/README.md)：178 最新烟贴图评审包，暖白亮面/冷灰暗面、窄柔边、8 秒录屏与字节保全；火与 236 PR 不变。
- [刘备 · 酒馆 R2.1 / 铁匠铺 R2.2](tavern-forge-r2-2026-10-07/README.md)：177/178 Review，177 暖光/亮度/植物位置、178 共享粒子烟火、动态录像，63 项角色检查；Basic Room 236 等粒子复审后开工。
- [刘备 · 场景返修统一复审（2026-10-07）](shop-series-2026-10-07/README.md)：179/181/184 Done；180/182/183 R2.1、185/186 R2 Review；252 项最新角色检查、地台对齐、预算/取色/交付回读。
- [Art environment setup](art-environment-setup.md): start here on a fresh host; toolchain, Git access, Figma MCP, Windows/remote OAuth callbacks, Lark CLI application/user authorization and readiness checks.
- [Mobile 3D asset workflow](mobile-3d-asset-workflow.md): English production guide for agents, based on the accepted Basic Room; reference analysis, reusable modeling, atlases, mobile budgets, Godot/Android checks and verified delivery.
- [Basic Room (2026-10-06)](basic-room-2026-10-06/README.md): user-accepted Blender assets, reusable Godot room, offline movement benchmark and Android checks; includes committed review images and an evidence summary. Not a production release.
- [暖木室内系列当前进度](warm-wood-scenes-2026-10-07/README.md)：173正式anchors、175糕点小修已交付；172/173/175复用共享GPU炉火，109/109角色检查、每场8秒近景与15秒走位，房间GLB/图集未改。174/176已验收。
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
