# 文档入口

## 当前基准

1. [玩法方案 v2](product/gameplay-plan-v2-2026-10-02.md)：玩法、数值、文案、操作与 P0/P1/P2/P3 分期的唯一来源，采用正文最新修订。
2. [Figma 页面 14 · UI semantic refactor](https://www.figma.com/design/5SVgfevrLzZXqD83uyPgmV/Gensen_US_2026?node-id=5-4)：当前游戏 UI 设计稿（R1 修订中，锁定项以 [锁定组件清单](governance/locked-components.md) 为准）；旧 [Figma · Prototype](https://www.figma.com/design/5SVgfevrLzZXqD83uyPgmV/Gensen_US_2026?node-id=5-3) 为 Archive，截至 2026-10-06。[本地设计索引](design/README.md) 标出有效稿与素材来源。
3. [P0 进度核查](qa/p0-progress-audit-2026-10-05.md)：实现证据、剩余范围和 SGODOT-131/150/153–170 卡片。

方案中的 P1/P2/P3 设计仍有效，只是不属于 P0；不能因尚未开发而删除。当前文档内部的待收口矛盾按 SGODOT-153 处理，不用旧方案补写新规则。

## 资料用途

| 目录 | 用途 |
|---|---|
| [product](product/README.md) | v2 主方案，以及明确标注范围的技术资料和竞品研究 |
| [design](design/README.md) | 当前界面稿、保留美术素材、制作来源及历史视觉证据 |
| [architecture](architecture/online-spaces.md) | 既有实现的协议、持久化和恢复机制，不代表 v2 功能已完成 |
| [reference](reference/mapbox-water-research-2026-09-24.md) | 从旧方案中保留的独立技术调研 |
| [superpowers](superpowers/README.md) | 沿用的 Avatar / 地图 / 移动端技术资料与历史交接 |
| [release](release/release-log.md) | P0 Demo 各版本的内容、构建身份与发布记录 |
| [qa](qa/README.md) | 按日期的实际检查、发布、设备与数据完整性证据 |
| [legal](legal/dynamic-farm-privacy-analytics.md) | 动态农场隐私政策条文草稿和 Google Play 数据安全表单答案（未发布） |

开发与发布工具见 [服务端](../server/README.md)、[Android](../tools/android/README.md)、[iOS](../tools/ios/README.md)。这些技术资料不能覆盖 v2 的玩法与分期，也不能把历史安装结果解释为当前设备状态。

For a fresh art environment, start with the English [Art environment setup](design/art-environment-setup.md), then follow the [Mobile 3D asset workflow](design/mobile-3d-asset-workflow.md). The accepted Basic Room is the reproducible example.

## 清理与历史追溯

2026-10-05 已移除明确被取代的玩法规格、阶段计划与界面草稿，见 [清理记录与逐文件清单](design-cleanup-2026-10-05.md)。历史 QA 引用旧设计时使用固定 Git 版本，避免误指向当前方案。运行代码、测试、工具脚本、运行资产与配置没有因本次清理而修改。
