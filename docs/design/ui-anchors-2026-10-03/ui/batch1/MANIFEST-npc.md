# 批次 1 · 地图、据点与 NPC 设计

更新：2026-10-05。规则基准为[玩法方案 v2](../../../../product/gameplay-plan-v2-2026-10-02.md)第 9、11、12、16 章；视觉对照使用 [Figma 原型](https://www.figma.com/design/OMLTC3yw3u2WDjOZhLnhaR/Gensen--US-?node-id=310-2955)。[返回设计索引](../../REPORT.md)。

## 当前结构

每个功能岗位对应一处系统生成空间和一枚地图 pin：Tea House、Tackle Shop、Market Square、Travel Post；小城和荒野使用提供相应服务的 Trading Post。除 Market Square 外均为室内微缩场景。落点可以参考 POI 密度，但不认领真实商店；真实 POI 仅显示视觉图标与只读名片。

每类据点离家最近的一处组成 Home Set。数量和分档以玩法方案第 9 章为准；图中的上海与其他城市数字是分布示例，不能反推固定全局点位。

有掌柜的据点先显示问候卡，选择 Trade 后再进入服务。掌柜指尖卡为 `<名字> · Tap to talk`，对话中为 Talking；设施如公告板、茶桌、盖章台、门仍各自点击触发。农场内 Homestead Stall 是无人值守设施，直接打开交易抽屉，见 [FARM-6](FARM-6.html)。

## 页面索引

| 编号 | 当前设计源 | 内容 |
|---|---|---|
| MAP-1 | [地图](MAP-1.html) | 各岗位据点 pin、鱼塘、农场、朋友、城市气泡与同类聚合；迷雾和只读 POI |
| NPC-1a | [Tea House](NPC-1a.html) | Ama、茶桌、居民与回地图出口 |
| NPC-1b | [Tackle Shop](NPC-1b.html) | Finn、Old Kai、Bite Board 与出口 |
| NPC-1c | [Market Square](NPC-1c.html) | Mei、Market Board、周末集市与居民；唯一室外据点 |
| NPC-1d | [Travel Post](NPC-1d.html) | Sigrid、Pip、Stamp desk 与出口 |
| NPC-1e | [Trading Post](NPC-1e.html) | 小城/荒野的茶、渔具、集市、旅行服务与居民 |
| NPC-G1 / G1-2 / G1-3 / G1-4 | [集市问候](NPC-G1.html) · [茶馆问候](NPC-G1-2.html) · [渔具问候](NPC-G1-3.html) · [旅行问候](NPC-G1-4.html) | 掌柜近景、岗位、问候、Trade、岗位信息问句与 Just passing by；具体画面以页面自身岗位文案为准 |
| NPC-2 / NPC-2-2 | [集市柜台](NPC-2.html) · [渔具柜台](NPC-2-2.html) | 柜台与背包同屏、库存、门禁、可在此出售的物品与回购额度 |
| NPC-3 / NPC-3-2 | [从背包出售](NPC-3.html) · [额度满](NPC-3-2.html) | Sell here 筛选、价格与 Sell All、共享额度及禁用原因 |
| NPC-4 / NPC-4-2 | [委托板](NPC-4.html) · [一起做委托](NPC-4-2.html) | 追踪、地图引导、交付、刷新；共同委托及人数不足回退 |
| NPC-5 / NPC-5-2 | [居民交流](NPC-5.html) · [居民馈赠](NPC-5-2.html) | Pip 与好感、Gift / Request；Granny Wu 分享料理 |
| NPC-6 / NPC-6-2 | [茶馆点单](NPC-6.html) · [茶馆状态](NPC-6-2.html) | 掌柜栏、茶品、共用次数与茶桌入口 |
| NPC-7 | [旅行柜台](NPC-7.html) | Permits / Passport / Fares，材料、条件、Craft / Buy |
| OUTPOST-DIAGRAM | [据点分布图](OUTPOST-DIAGRAM.html) | 分档数量和 Home Set 的结构说明 |

## 柜台与背包

集市和渔具铺使用同一抽屉结构：上半柜台含掌柜栏及 Buy / Board，下半为背包、分类与物品详情。出售在背包中完成，`Sell here` 标出可在当前柜台出售的物品；不可在此卖的物品说明去处。库存、委托板和回购额度的共享范围按岗位与城市规则显示，不能沿用所有据点共用同一额度的表述。

抽屉须保留掌柜形象与可读问候。当前柜台商品区最多展示四行，背包可滚动，不能靠把整个网格压到屏底安全区外容纳内容。具体数值与恢复/重置时间回查玩法方案。

## 底图、依赖与预览

当前底图为 `../../scenes/tea-house.png`、`tackle-shop.png`、`market-square-v2.png`、`travel-post.png`、`trading-post.png`。室内主场景相机为 `1.12 / −30 / 360`，集市为 `1.1 / −32 / 307`；NPC-6 茶柜近景为 `2.0 / −220 / −440`，局部取景以各页参数为准。

MAP-1 使用 `../../scenes/map-tile.png`，由社交地图插画裁切，来源见 [SOURCE](../../scenes/map-tile.SOURCE.txt)。这是布局占位，不是真实 Mapbox 地理和点位验收。

共享依赖为 `../kit.css`、`../icons.svg`，本组使用 `../kit-npc.css`、`../icons-npc.svg`、设施样式与图标；柜台页还必须加载 `../kit-farm.css`。`.kpanel` 为掌柜栏，`.drawer.is-stall-bag.is-counter` 为柜台/背包结构。旅行材料卡使用 `.pcard / .pchip`，避免与共享 `.recipe / .chip` 样式冲突。

页面为 1080 × 2400 静态设计，须经 HTTP 预览 SVG sprite，方法见[总索引](../../REPORT.md)。NPC 服务和居民页不构成当前客户端功能完成证据，P0 只取玩法方案第 17 章的对应范围。
