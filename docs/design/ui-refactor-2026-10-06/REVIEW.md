# Gensen UI 设计审阅 · 2026-10-07

本提交供美术总监、产品经理和实现负责人审阅：涵盖 P0 流程补齐、P1–P3 后续设计，以及 288 张主卡的原生 Figma 重构、视觉细化和组件归类。审阅通过后再进入下一轮统一细节优化；本提交没有游戏运行代码、部署或玩家数据改动。

## 从哪里开始

1. [当前 Figma 审阅页：14 · UI semantic refactor](https://www.figma.com/design/OMLTC3yw3u2WDjOZhLnhaR/Gensen--US-?node-id=481-53)。这是当前图稿入口。
2. [组件架构与维护指南](https://www.figma.com/design/OMLTC3yw3u2WDjOZhLnhaR/Gensen--US-?node-id=946-76647)：Apple／Carp 的相同结构如何复用，属性、插槽、变体与上游修改关系。
3. [组件归类与本轮问题总结](COMPONENT-FAMILIES.md)及[未模拟动作清单](figma-plugin/prototype-gap-ledger.json)。
4. 对照[原 Prototype](https://www.figma.com/design/OMLTC3yw3u2WDjOZhLnhaR/Gensen--US-?node-id=310-2955)与[玩法基线](../../product/gameplay-plan-v2-2026-10-02.md)。原 Prototype 保留。

`p0-flow-2026-10-05`、`p1-p2-flows-2026-10-06` 与本目录中的早期截图提供设计来源和过程证据；各处“final”是当时批次的结论。当前组件族以本文、组件总结和最新 Figma 页为准。离线 HTML 主要供结构与字段核对，不能代替最终 Figma 视觉。

## 本轮可审阅结果

| 范围 | 结果与证据 |
|---|---|
| 页面与流程 | 288 张主卡，另有 23 张业务结果／分支补态与独立作物图鉴；见[总览](README.md)。 |
| 快捷栏 | 40 处完整栏、200 个物品槽统一图标／名称／`×N`、选中、Pin、空槽及 Bag／Close；[逐图检查](cloud/toolbar-unification/visual-review.json)。 |
| 信息与上下文弹窗 | 576 个信息窗和 84 个 Pin 状态共用 InformationSheet；名称、数量为实例数据，正文使用原生 Content Slot。 |
| 反馈 | 60 个反馈窗共用 Feedback；685 个信息正文段落共用 Paragraph。 |
| 组件目录 | 222 个主组件、25 个组件集全部归类，包含图标、素材和状态变体；[完整目录](cloud/component-consolidation/family-catalog.json)。 |
| 整理与连线 | 前轮删除 138 个精确重复 Overlay；当前 735 个 Overlay 全部可达，288 主卡完整，无缺失目标或损坏实例；[最终回读](cloud/component-consolidation/final-integrity-result.json)。 |
| 内容与行为保持 | 720 个迁移弹窗的可见文字与完整原型反应逐帧对比一致；[检查摘要](cloud/component-consolidation/migration-validation-summary.json)。 |
| 上游联动 | 实测共享间距 12→16→12：Apple／Carp、图鉴、Pin 同步变化，数值不变，独立回读确认恢复。 |

## 美术总监关注项

- [ ] 以农场、背包、矿洞、钓鱼、厨房和 Avatar 为代表，核对既有风格、布局比例、留白、字体与场景露出。
- [ ] 标题、数量、效果、状态和费用的层级清楚；文字与数量无混排、遮挡或裁切。
- [ ] 执行按钮、导航入口、关闭与危险操作的视觉区分明确。
- [ ] [统一快捷栏样例](https://www.figma.com/design/OMLTC3yw3u2WDjOZhLnhaR/Gensen--US-?node-id=925-71414)与实际页面一致，空／选中／钉住状态完整。
- [ ] Avatar 保留上方真实预览和下方三列部件网格；短信息窗与长滚动详情都适合后续统一微调。
- [ ] 明确哪些场景、图标、居民和内容资产仍是原型示意，哪些可进入正式美术生产。

## 产品经理关注项

- [ ] 核对首会话、材料制作装备、厨房储物、包裹和 Profile／换装的路径与异常状态。
- [ ] 核对 P1 内容边界、P2 免费旅行闭环、收费／社交入口和 P3 Buff 状态。
- [ ] 信息披露与操作决策一致；详情、返回、确认不会引起库存或资源状态重置。
- [ ] 检查 36 个唯一未模拟动作：区分未做本地状态、未绘制精确结果、账号操作、信息跳转等，不能全部解释为“玩法未定义”。
- [ ] Buff 页新增数量是已记录来源的设计示例，不是玩家实际库存，也不据此推断消耗；见[样例来源](data/toolbar-fixture-provenance.json)。

## 组件与实现负责人关注项

- [ ] 名称、数量和价格使用实例属性；不要按 Apple、Carp 或每个数量新增主件。
- [ ] 结构／状态差异才使用变体；变体的共用样式来自真实嵌套基础组件或变量，不能依靠复制或相似命名。
- [ ] 新增正文通过 Content Slot 插入现有 Paragraph、Fact、Cost、NeedTile、ItemRow 和语义动作组件。
- [ ] 保留外层原型目标和实例上的业务动作；不要 detach，也不要把某页的跳转目标写进通用主件。
- [ ] Legacy 中 7 个主件仍有 72 个跨页引用，应保留兼容；独立 Quantity 尚未嵌入 ObjectHeader，数量样式的实际修改入口见组件指南。

## 审阅边界与反馈格式

40 处快捷栏做了逐张视觉检查；本次弹窗组件化做了 13 个代表样例视觉检查及 720 个迁移窗口结构／文字／反应检查。没有据此声明所有原型路径已实点、全部生产美术已完成、真机运行或游戏结算已验收。15 个相机／教学场景覆盖层继续使用专用布局。

建议每条反馈写为：**角色／优先级 → Figma 页面与 Frame ID → 当前问题 → 期望结果 → 影响的组件族或业务状态**。优先评论主组件或样例，再说明受影响页面，便于下一轮集中调整。

## 复现与归档

[便携 Figma 插件包](figma-plugin/gensen-ui-refactor-plugin.zip)及[输入／文件校验清单](figma-plugin/artifact-manifest.json)已保留。源码构建需要本仓库的既有 `ui-anchors` 以及前两批设计数据；ZIP 已内嵌导入所需数据。构建入口见[插件说明](figma-plugin/README.md)。

个人通信回执、短期截图下载链接、锁文件和逐页编译缓存留在本地；最终设计数据、构建输入、截图及验收回读随提交归档。
