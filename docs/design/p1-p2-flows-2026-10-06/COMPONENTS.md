# 组件维护与复用规则

2026-10-06。**以后先复用本库和原UI源，缺少组件时才新增。**用户明确要求复用既有规格；07初稿的实色卡片/两排Gear布局已撤回。所有下表尺寸均为1080×2400源稿尺寸，Figma审阅卡按1:3展示。

| 组件 | Figma主节点 | 源规格 | 主要实例 |
|---|---|---|
| Action Button | [主组件集](https://www.figma.com/design/OMLTC3yw3u2WDjOZhLnhaR/Gensen--US-?node-id=430-10) | Standard112高/56半径；Small80高；Primary绿渐变白字、Secondary描边、Disabled原因文案 | 新131卡与07面板按钮 |
| HUD / Two rows | [主组件](https://www.figma.com/design/OMLTC3yw3u2WDjOZhLnhaR/Gensen--US-?node-id=431-416) | 原头像112、Energy112、Inbox96；第二行64；Location icon可交换 | 07–12场景 |
| Bag Drawer | [主组件集](https://www.figma.com/design/OMLTC3yw3u2WDjOZhLnhaR/Gensen--US-?node-id=432-615) | y800、高1600、首行快捷栏；Bag/MiningAvailable/MiningEquipped3态 | BAG-1-P0、GEAR-P0-1/2 |
| Need Tile | [主组件集](https://www.figma.com/design/OMLTC3yw3u2WDjOZhLnhaR/Gensen--US-?node-id=448-11804) | L156/12/25，M112/9/22，S72/6/19；Complete/Short，Icon与Label属性 | 07–10材料要求 |
| Information Row | [主组件](https://www.figma.com/design/OMLTC3yw3u2WDjOZhLnhaR/Gensen--US-?node-id=445-8601) | 图标、标题、说明；文本属性+图标交换 | 155处列表信息 |
| Action Controls | [主组件集](https://www.figma.com/design/OMLTC3yw3u2WDjOZhLnhaR/Gensen--US-?node-id=458-12288) | 圆键176、徽标56、切换96、快捷格160/间距12；Farming/Fishing/Mining/Combat/SetTrap | 07劳作、当地钓鱼、投笼、战斗、Buff失效后 |
| Content icons / portraits | [资产样式板](https://www.figma.com/design/OMLTC3yw3u2WDjOZhLnhaR/Gensen--US-?node-id=438-3184) | 保留原SVG形状和配色；规范ID稳定 | 100个内容组件 |
| Outpost climate | [组件区](https://www.figma.com/design/OMLTC3yw3u2WDjOZhLnhaR/Gensen--US-?node-id=456-12024) | 5空间×4气候变体，共用底图、调色方向 | 内容板20个实例 |

## 修改方法

1. 修改整体外观：进入00B/00C对应主组件；保持尺寸基准和变量绑定，先看旁边预览实例，再核对至少一个真实页面。
2. 修改内容：使用Label、Title、Body、Icon属性或图标交换；不要detach实例，不要在每页重新画按钮、进度环或背包格。
3. 修改状态：优先切换Tone/Size/Mode/Stage/Climate；数字/剩余时间是示例内容，不能把主组件默认值当成实际玩家状态。
4. 已有截图卡：原01–06仍是历史批准视觉锚点。新的可编辑组件按其源样式重建，不能用整页图片铺底再叠几层文字冒充可编辑。
5. 变更规则先更新玩法基线对应表；本轮OPEN-ITEMS里的未知项不能被当前占位文案自动定案。

## 来源

- `../ui-anchors-2026-10-03/ui/kit.css`：HUD、快捷栏、背包格、按钮、抽屉、行动键。
- `../ui-anchors-2026-10-03/ui/kit-profile.css`：Bag/Gear切换、六槽、装备列表。
- `../ui-anchors-2026-10-03/ui/kit-need.css`：全局材料进度格。
- `../ui-anchors-2026-10-03/ui/icons*.svg`：基础符号。新增内容源在本目录`assets/`。

## 已知生产边界

本库整理的是界面和设计素材，不是Godot控件库/主题文件；尚未生成代码绑定。高等级房屋、独立鱼类/居民3D、完整植物生长模型仍需美术生产和真机检查。共享组件数量不等于完成了这些生产资产。

Energy Meter使用28个原型数值变体，通过HUD的Energy meter交换属性复用；这是示例数据，不是生产等级或体力规则。直接调整嵌套实例内部宽度在当前Figma连接器中不会持久化，后续调试应换对应计量变体或修改主组件。
