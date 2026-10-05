# 玩法改造前的代码与地点界面审查

- 日期：2026-09-07。
- 目的：查明首日断档、菜单集中和地图/3D 价值不足的机制原因。
- 结论入口：[以好玩为先的产品改造](https://github.com/IndieMiao/sensen-godot/blob/25b7a8a6e0574f9b0c4c97f480238e98d5d9985c/docs/product/fun-first-rework-2026-09-07.md)。

## 证据范围

本轮检查当前工作区，包括已有未提交修改。使用 Godot 4.7.2 的 Metal Mobile 原生渲染运行既有 `tools/dev/place_visual_probe.tscn`，生成 360×640、390×844 两种尺寸的地点界面。捕获使用合成 D6 状态；网络请求由探针拒绝，没有运行真实新账号的完整首日，也没有验证自然七日节奏。

探针生成 32 张图，报告非空场景像素和 UI 边界检查通过；人工逐图检查了下列三个状态在两种尺寸中的共六张。其余输出保留为原始材料，不当作人工审查完成的证明。[原始报告](../../output/gameplay-audit-2026-09-07/place/report.json)。

```sh
godot --path . --scene res://tools/dev/place_visual_probe.tscn -- \
  --place-probe-chapter=6 --place-probe-all-panels \
  --place-probe-out=res://output/gameplay-audit-2026-09-07/place
```

## 三个检查步骤

以下是分别打开的场景状态，顺序用于比较交互，不表示一次真实玩家旅程。

### 1. 小馆居民页：人物可见，交谈入口仍在面板

![本轮渲染：小馆居民页，390×844](../../output/gameplay-audit-2026-09-07/place/bistro-d6-390x844.png)

- 健康度：渲染与排版可用，场景交互不足。
- 已有优势：人物有明确造型，建筑、餐桌与植被形成地点辨识；返回和 Talk 按钮清楚。
- 发现：中央 NPC 没有对应的普通世界点击处理，玩家通过底部 Talk 交谈。人物难以成为玩家记住的行动目标。
- 依据：`scenes/place/place.gd` 的 `_unhandled_input` 在当前页直接返回；`modules/farm/resident_cast.gd` 创建固定站位并播放 idle。
- 改造：点击人物后走近、转向，再显示短对话和当次选项；结束后回到人物活动。

### 2. 小馆厨房页：页面变了，场景没有参与制作

![本轮渲染：小馆厨房页，390×844](../../output/gameplay-audit-2026-09-07/place/bistro-d6-390x844-kitchen.png)

- 健康度：配方信息可读，制作的场所感偏弱。
- 已有优势：食材图片和数量让资源需求可辨识，材料用量清楚。
- 发现：与居民页相比，上方小馆场景相同，主要变化是底部滚动内容。在较小屏幕中，更多材料和后续操作需要滚动；玩家容易把厨房理解为配方清单。
- 依据：地点通过 `_activate_tab` 切换 `KitchenPanel`；服务端 `cook_dish` 负责固定扣料与成品入仓。截图不能说明动作动画质量，相关结论限于现有入口和状态结构。
- 改造：从备餐台开始操作，材料上台、成品上桌，居民共同用餐；菜单只保留本次配方和材料选择。

### 3. 庭院布置页：已具备场景点选基础，入口和解锁仍受面板约束

![本轮渲染：庭院布置页，390×844](../../output/gameplay-audit-2026-09-07/place/courtyard-d6-390x844-decorations.png)

- 健康度：已有可复用能力，表达开始得太晚。
- 已有优势：`decoration_tap`、选取/落点、预览、撤销和保存已存在，不能说当前完全没有场景布置。
- 发现：需要先进入对应页签；物品从下拉项选择；合成状态中尚未购买成长，故显示 Preview only。该锁定来自夹具条件，不代表真实玩家到 D6 都未解锁。
- 依据：`scenes/place/decoration_panel.gd` 与 `place.gd`；场景点选只在布置面板激活时接受。
- 改造：首个制作物开放布置，直接拖入或点地放置；保留现有撤销和不确定保存恢复机制。

## 跨步骤发现

地点面板高度为 `min(310, root.size.y * 0.46)`，常驻占据明显空间，并通过相机框选给场景预留剩余区域。这能避免遮挡，但还没有把场景变成主要操作面。

同一个 NPC、灶台、餐桌、工作台和工程需要各自的动作入口与完成反馈。仅增加场景装饰或缩小面板不足以改变玩家的行为。

截图中的图标页签较多；陌生图标在触摸设备上不能依赖悬停说明。新方案需提供选中名称、可辨认物件、足够命中范围，以及不用精确拖动也可完成的操作。此次未测读屏、焦点、实际触摸命中与系统字号，不作完整无障碍合规结论。

## 节奏与地图的代码证据

| 结论 | 可复查位置 |
| --- | --- |
| 教学 3 分钟后恢复 4–18 小时 | `assets/farm/data/crops.json`；`server/src/domain/handlers/farming.ts` 的 `durationOf` |
| 同一真实玩家日不开下一章 | `server/src/domain/derive.ts` 的 `opens`；`server/src/domain/time.ts` 的 04:00 换日 |
| 厨房 D3、访问 D4、成长 D5 | `assets/farm/data/chapters.json`，并由对应服务端处理器校验 |
| 作物生长时农活推荐停在等待 | `modules/farm/next_step.gd` 的 `bulk` |
| 地点通过底部 Places 按钮进入 | `scenes/map/nearby_panel.gd` 的 `_place_buttons`；`scenes/map_poc/map_poc.gd` 的 `_open_place` |
| 不同蓝图在农场内部变成相同田畦坐标 | `modules/farm/farm_interior.gd` 的 `_init` |

本轮没有捕获移动端真实 Mapbox 流程，因此地图结论限于代码架构和入口，不评价当前真机底图清晰度或手势性能。用户所述“90% 交互在抽屉”作为反馈保留，没有行为统计支持精确比例。

没有观察真实玩家的主动退出、乐趣评分、D1/D7 留存。新方案中的首会话时长、数值与验收人数均是待验证的设计目标，不能由这次渲染通过推导产品已经更好玩。
