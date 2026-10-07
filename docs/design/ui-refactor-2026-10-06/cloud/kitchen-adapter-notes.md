# 厨房云端适配交接（仅准备，root执行）

本文件与两个 `.root.js`/JSON 文件没有调用 Figma。`cloud/build_cloud.py` 未修改。

1. 使用现有 root bootstrap 加载当前页、KIT/ICON/VAR/STYLE及标准helper；再加载 `kitchen-scene-fixes.js`、`kitchen-selection-fixes.js`。两个patch捕获之前的函数，顺序不能倒置。
2. 只执行 `kitchen-component-delta.root.js` 中的新组件部分；不要再调用整条 `library()`，否则会重建既有主件。新增键是 `FacilityMarker/{compact|wide}/{navigate|commit|blocked}` 六个，组件集 `FacilityMarker`；选材只需补不存在的源 `i-lock`，其余复用 `LegacySelectedSummary`、`LegacyInventoryCell`、`NeedTile`、`IngredientSlot`、`Tab`、`Close`、`Command`。
3. 把返回的Marker主件与lock图标ID合入root state。root已有的颜色/字体/图标继续复用。
4. 在新审阅页既有目标FRAME内重建子节点，保留框ID及Row/Section。只清理 `kitchen-adapter-config.json` 列出的**新稿**目标，不触碰旧Prototype。
5. 各目标先 `scene(frame,descriptor)` 与当前最终的 `hud(frame,descriptor)`。入口调用 `kitchenSceneEntrance(frame,descriptor)`；选材调用最终 `kitchen(frame,descriptor)`。入口不加普通panel/footer/Close/劳作键/空QuickBar；选材自带一个Close，不能再加通用Close。
6. `wire()` 与 `STYLE_JOBS` 继续使用root现有阶段。确定源各页文字/几何后再截图；本地mock通过不能替代截图。

目标精确节点和调用分类见 `kitchen-adapter-config.json`。优先实建 COOK-1、COOK-2a、COOK-2b、COOK-P0-2；随后验证单/双/三灶入口。火候三个已验页面不在本次重建名单。

验收要点：

- COOK-1：3个灶Marker分别对应原图约 `(139,294)/(218,312)/(294,330)`；柜台约 `(348,354)`。细引线不穿过Marker正文。名称、状态/时间、操作分别占位；没有列表与底部导航重叠。
- COOK-P0-1/P1-1/P1-3/P1-5：分别1/2/2/3个可用灶；保留各自Empty/Cooking/Ready和实际时间；满包Collect阻塞，菜留灶。复用房间图的装饰灶不计为交互灶；不是运行时投影/碰撞验收。
- COOK-2a：25格完整保留，默认至少两行可见；固定摘要保留Grilled Crucian、5s、基础+20、单份与Crucian3/1。XP只在详情，不再正文/底部重复。
- COOK-2b：20格完整，2个已投食材使用鱼/草真实图标，第三格源lock+CookingLv4；默认至少两行候选可见。Koi是Not for cooking，不出现Silhouette技术词。
- 旧COOK-2b的源图明确是Fine/15s/Unknown dish，不能提前揭示菜名或假定40回复。Mystery5Energy是规则说明，不是假定当前结果。
- COOK-P0-2：1/2投入、锁定第三槽、全部五个候选、5s/+20/Cook可见；不添加不存在的候选凑行数。
- 只写有可靠后继的连线。COOK-1原Collect→COOK-4会把Grilled Crucian变成Herb Grilled Fish，补丁将该不匹配结果留warning。柜入口改为真正的Warming Cabinet稿，不能进入材料仓。

当前线全量QA接续表在 `current-flow-qa-checklist.json`：row11后4卡、row12全部、row13–24全部，共108张；旧稿代理负责row11前4张。这是一份待执行清单，不是已完成视觉验收的声明。
