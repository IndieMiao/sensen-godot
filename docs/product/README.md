# 产品文档索引

## 规则与实施

- [玩法方案 v2](gameplay-plan-v2-2026-10-02.md) 是唯一玩法基准；[HTML 阅读版](gameplay-plan-v2-2026-10-02.html) 是阅读导出，冲突时回到 Markdown 最新修订。
- [Figma 页面 14 · UI semantic refactor](https://www.figma.com/design/5SVgfevrLzZXqD83uyPgmV/Gensen_US_2026?node-id=5-4)（R1 修订中，锁定项以 [锁定组件清单](../governance/locked-components.md) 为准）与 [本地设计索引](../design/README.md) 用于界面对照；旧 [Figma · Prototype](https://www.figma.com/design/5SVgfevrLzZXqD83uyPgmV/Gensen_US_2026?node-id=5-3) 为 Archive，截至 2026-10-06。
- [P0 进度](../qa/p0-progress-audit-2026-10-05.md) 区分已实现、缺失和未验收；[交接经过](research/gameplay-plan-v2-2026-10-02/HANDOFF-2026-10-04.md) 只补充各日期的事实和技术经验。
- [P1 第一步开发包：第 5 天之后的种田](p1-step1-farming-2026-10-08.md)（40 格、卷心菜 / 玉米 / 黄瓜、洒水器；q(59)）是方案 §17.3.3 第 1 行的开工依据，规则冲突时以方案为准。

旧 G0–G4、七日章节、双地域交换、v1 核心循环及旧背包/装备/矿洞/HUD 规格已移除，不再并列作为开工依据。

## 保留资料的边界

| 类型 | 保留内容 | 使用方式 |
|---|---|---|
| 钓鱼技术与表现 | fishing、fishing-presentation、fishing-feedback、fishing-shore-multiplayer | 沿用张力小游戏、动画与权威结算经验；鱼表、费用、控件与容量按 v2 |
| 地理与地图 | compact/private-geographic/shoreline/farm-relocation、system-fishing-ponds、la-map、griffith、poi 系列 | 技术来源、稳定地点与导航；旧农场池塘、入口和操作约束不覆盖 v2 |
| 既有服务 | account-global-city、multiplayer-spaces、party-cross-region-travel、party-voice、farm-pond-retirement | 维护现有账号、协议、迁移与数据安全；旧社交/旅行/战斗规则不用于 P0 |
| 美术与水体 | mine-art、water-material、water-detail、ui-clarity | 资产、渲染和性能经验；现 UI 由 Figma 与 v2 第16章定义，最新水体见 design 索引 |
| 竞品与长线研究 | farming-games、stardew-gensen、item-systems、monster-systems、gensen-endgame | 研究证据和未采纳假设，不是本期承诺 |
| 数值过程 | research 中的模拟器、输出与历史核对 | 复核旧推演；不代表当前 P0 子集七日验收已通过 |

[Mapbox 真实水域资料调研](../reference/mapbox-water-research-2026-09-24.md) 已从旧鱼塘提案中提取，旧玩法正文不再保留。各保留文档顶部注明了具体范围；原始 QA 和代码来源可以从 [清理记录](../design-cleanup-2026-10-05.md) 的固定版本追溯。
