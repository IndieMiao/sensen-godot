# 当前 UI 设计索引

整理日期：2026-10-05。玩法、规则、数值与分期以[玩法方案 v2](../../product/gameplay-plan-v2-2026-10-02.md)为基准；视觉对照进入 [Figma 原型](https://www.figma.com/design/OMLTC3yw3u2WDjOZhLnhaR/Gensen--US-?node-id=310-2955)。文件 key 为 `OMLTC3yw3u2WDjOZhLnhaR`，原型页为 `310:2955`。

本目录保存 HTML 静态设计稿、场景底图、共享图标和截图。它们不是游戏实现或验收证据。最新产品修订与局部旧示意不一致时，先按玩法方案对应章及第 1.5 节最新修订判断；实现进度另见 [P0 核查](../../qa/p0-progress-audit-2026-10-05.md)。

## 当前入口

| 范围 | 设计源 | 说明 |
|---|---|---|
| FARM-1 农场主场景 | [farm.html](ui/farm.html) · [基准图](out/current/FARM-1.png) | 农场取景、两行 HUD、摇杆、主行动键与消耗品快捷栏 |
| FISH-1 鱼塘主场景 | [pond.html](ui/pond.html) · [基准图](out/current/FISH-1.png) | 保留钓鱼手感；鱼竿属于装备，鱼饵进入快捷栏 |
| COOK-1 厨房总览 | [kitchen.html](ui/kitchen.html) · [基准图](out/current/COOK-1.png) | 点击场景中的灶台、图鉴与设施；烹饪抽屉见 COOK-2a/2b |
| BAG-1 基础背包 | [bag.html](ui/bag.html) · [基准图](out/current/BAG-1.png) | 保留物品网格、分类与详情的基础源；完整 Bag / Gear 结构以 [BAG-2](ui/batch2/BAG-2.html) 为准 |
| HUD、移动、种植、驿站、休息、快捷栏 | [farm 组索引](ui/batch1/MANIFEST-farm.md) | 包含 Energy Card、Today、行动径向与首会话提示 |
| 钓鱼结果、烹饪、进食、背包操作 | [cook 组索引](ui/batch1/MANIFEST-cook.md) | 当前 Cookbook / Experiment、场景中的锅与投料槽 |
| 地图、据点、掌柜、居民、柜台 | [npc 组索引](ui/batch1/MANIFEST-npc.md) | 每岗位一处空间、掌柜先问候再 Trade、柜台与背包同屏 |
| 农场成长、技能、图鉴、Profile、Gear、包裹 | [批次 2 索引](ui/batch2/MANIFEST-batch2.md) | 已合入 2026-10-05 下午审图修订 |

`out/current/` 的四张基准图是既有锚定截图的归一保存，保留原图像内容；迁移目录不代表重新出图或已补齐后续所有细节。局部交互与入口按当前 HTML、两组清单及玩法方案判断，尤其是厨房设施点击和 Bag / Gear。其余当前分镜截图位于 `out/batch1/`、`out/batch2/`，文件名与页面编号对应。

## 当前约定

- 画布为 1080 × 2400。使用 Nunito、奶油卡片、粉彩 3D 微缩场景；用户可见文案使用英文。排版与组件规则见玩法方案第 16 章。
- HUD 第一行是头像、体力、金币、Inbox；第二行是 Today 与位置芯片。头像打开 Profile；包裹从右上角铃铛或农舍信箱进入同一 Inbox。
- 摇杆负责位移，主行动键执行当前劳作，切换键打开行动径向。快捷栏只放当前行动可使用的消耗品；工具与功能性饰品放在背包 Gear 一侧，外观入口为 Profile → Edit look。
- 设施由点击设施触发。Energy Card 的 Eat / Cook / Tea / Rest 只负责引导或打开对应入口，不自动消耗物品、支付或休息。
- 农场驿站无人值守，点击棚屋直接打开交易抽屉。各类据点掌柜则先问候、再由 Trade 进入服务。柜台与背包同屏，出售在背包物品详情中完成。
- Cookbook 与 Experiment 共用灶台舞台：锅与原料在 3D 场景中，槽条在锅下；初始 2 槽，Cooking Lv4 开第 3 槽。
- 满包后的被动奖励直接进入包裹。主动操作的容量门禁仍按玩法方案处理；满包不代表所有生产都可以无条件继续。
- 文档与分镜包含多个阶段；P0 范围与出口只由玩法方案第 17 章定义，目录中有图不代表属于 P0 或已经完成。

## 素材与预览

当前底图以页面的 `src` 为准：农场、池塘、厨房、无人驿站、各岗位据点、升级农场、果园、设施、矿洞和 Profile 立绘保存在 `scenes/`。地图底图 `map-tile.png` 是从既有社交地图插画裁切的视觉占位，来源见 [SOURCE](scenes/map-tile.SOURCE.txt)，不能证明真实地理或点位分布。

共享样式为 `ui/kit*.css`，图标源为 `ui/icons*.svg`。后者同时是 `tools/p0/extract_icons.py` 的实际输入，必须与当前资产提取流程一起维护。

从仓库根目录启动静态预览：

```sh
python3 -m http.server 8765 --bind 127.0.0.1 --directory docs/design/ui-anchors-2026-10-03
```

随后以 `http://127.0.0.1:8765/ui/farm.html` 等路径打开页面。截图视口为 1080 × 2400、DPR 1；必须经 HTTP 加载，`file://` 下 Chromium 会拦截跨文件 SVG sprite。页面支持的 `?guide=1` 只用于设计标注。

生成脚本保留原样。批次 2 的 `_gen.py` 含早期输出分支，不能全量执行后直接把结果当成当前稿；使用约束见[批次 2 说明](ui/batch2/MANIFEST-batch2.md)。本次只整理设计文档，未重跑生图、截图或游戏验证。

## 审阅边界

静态底图中的角色、田格、锅位与覆盖层只是构图示意；样例库存、价格、XP、恢复量与倒计时不能替代玩法方案表格。Today 长文案、移动分镜、短屏布局和部分状态尚须在真实 UI 中验证。旧版本的制作与审阅过程保存在 Git 历史，本入口只列当前可用设计及明确保留的局部来源。
