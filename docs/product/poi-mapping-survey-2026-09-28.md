# Mapbox POI 可用信息调研与图标映射方案

日期：2026-09-28。基线：`farm-dev` `31f7a3f`。调研脚本在 `tools/map/poi_survey/`（`sample.py` 采样、`taxonomy.py` 规则草案、`sim.py` 覆盖率）。

## 定案（2026-09-28）

1. 只用瓦片 `poi_label` 自带字段综合判断：`brand`、`maki`、`type`、`class`、`iso_3166_1`。
2. 不接 Search Box，不产生额外请求。
3. 不按店名关键词推断任何分类。
4. 没有名字的 POI 一律不上图。

5. 同一子类有多款 icon 时，沿用现有做法：按 POI 名字哈希固定选款，保证同一个 POI 始终是同一张图，不随机。

下文中关于 Search Box、店名关键词的内容只作调研记录保留。

## 1. 采样方法

- 数据源：当前底图 `Style.MAPBOX_STREETS` 使用的 `mapbox.mapbox-streets-v8` 矢量瓦片（与 `GodotMapPlugin.queryCityPois` 读的是同一份数据）。
- 每城以市中心为圆心取 z16 瓦片 12×12 = 144 张（约 7 km 见方），解码 `poi_label` 图层。

| 城市 | 中心 | POI 数 | 其中 filterrank ≤ 3（地图主要显示层） |
| --- | --- | ---: | ---: |
| 旧金山 | Union Square | 10,160 | 1,652 |
| 纽约 | Midtown | 13,807 | 1,733 |
| 北京 | 王府井 | 3,971 | 1,622 |
| 上海 | 人民广场 | 6,788 | 1,964 |

另用 Search Box API 在四城各做了“餐厅 / 购物”类别搜索（美国两城每城 9 个点）。

## 2. 瓦片里每个 POI 能拿到的字段

TileJSON 公布的字段比官方文档多三个：`brand`、`maki_beta`、`maki_modifier`。

| 字段 | 旧金山 | 纽约 | 北京 | 上海 | 说明 |
| --- | ---: | ---: | ---: | ---: | --- |
| `class` | 100% | 100% | 100% | 100% | 20 个大类 |
| `maki` | 100% | 100% | 100% | 100% | 四城实见 92 个值；其中 27% 是通用 `marker` |
| `type` | 100% | 100% | 100% | 100% | OSM 原始标签值，四城共 453 种；**细分信息主要在这里** |
| `category_en` / `category_zh-Hans` | 80% | 84% | 71% | 83% | 基本是 `type` 的显示文案（翻译版），没有额外信息 |
| `brand` | 9% | 18% | 13% | 16% | 连锁品牌：星巴克、瑞幸、麦当劳、全家、庆丰包子铺、全聚德、蜜雪冰城等 |
| `maki_beta` | 1.4% | 0.8% | 0.2% | 0.3% | 只见 `parking-paid`、`taxi`、`car-wash` |
| `maki_modifier` | 0 | 0 | 0 | 0 | 四城都为空 |
| `filterrank` / `sizerank` | 100% | | | | 疏密与大小排序 |
| `name_en` / `name_zh-Hans` | 2% / 2% | 3% / 1% | 33% / 28% | 42% / 24% | 中国城市的英文名只有三到四成 |

### 关键发现

1. **瓦片里没有菜系。** `maki=restaurant` 的 4,308 个 POI，`type` 与 `category_en` 只有 `Restaurant` 或 `Food Court` 两个值。瓦片层面的细分餐饮只有 `maki`：`restaurant-pizza / -noodle / -seafood`，加上 `fast-food`、`bakery`、`confectionery`、`ice-cream`、`bar`、`beer`。四城均未出现 `restaurant-sushi` 和 `restaurant-bbq`。
2. **商店的细类在 `type` 里。** `maki=shop` 下有 25 种 `type`：Books、Florist、Cosmetics、Mall、Pet、Electronics、Stationery、Toys、Antiques 等。
3. **通用 `marker` 里藏着大量可用细类。** 它有 318 种 `type`，例如 Hairdresser 403、Beauty 389、Dry Cleaning 164、Massage 115、Tobacco 92、Pastry 45、Butcher 27、Tea 22。但也有大量噪音：建筑 `Yes` 2,388、Residential、Apartments、Company、Diplomatic。
4. **品牌可以补菜系和品类，且中国城市命中率不低。** 例如肯德基（`maki=fast-food`）可判为炸鸡，蜜雪冰城（`maki=cafe`）可判为奶茶，庆丰包子铺判为包子，全聚德判为烤鸭。只取品类，不画 logo，以避开商标问题。
5. **Search Box 在美国能补菜系，在中国不能用。**
   - 美国两城约 **72%** 的餐厅带细分类（`japanese_restaurant`、`mexican_restaurant`、`thai_restaurant` 等），全目录共 502 个类别。
   - **北京、上海返回 0 条**；官方文档写明只支持美国、加拿大、欧洲。
   - 按请求计费，结果只允许临时使用，不能永久缓存。
   - 数据源和瓦片不同，按店名只能对上 28%（纽约）和 42%（旧金山）的瓦片 POI。
   - 结论：不适合用来驱动地图图标。
6. **店名关键词能再补一些餐饮细类。** 四城 `maki=restaurant` 中有 17–19% 的店名命中菜系关键词：北京以面、烤鸭、火锅为主；上海以面、泰式、饺子、火锅为主；美国以寿司、taco、饺子、泰式为主。
   - 注意：`city_map_data.gd` 现有注释写明“不从店名推断菜系”。这一级是否启用需要你拍板。

## 3. 映射机制方案

### 3.1 两级 key：`大类.子类`

- 例如 `food.hotpot`、`shop.books`、`service.hair`。
- 选图时先找子类图标，没有就回退到大类图标。因此映射表可以比美术先行：美术画好一个子类，它就自动生效，不用改代码。
- 草案共 13 个大类：food、drink、grocery、shop、service、health、lodging、edu、culture、leisure、religion、civic、transport。四城实际出现约 105 个子类。

### 3.2 解析优先级（从细到粗，命中即停）

**2026-09-28 定案：只用瓦片 `poi_label` 字段，不接 Search Box，不产生额外请求。**

| 级 | 依据 | 例子 | 说明 |
| --- | --- | --- | --- |
| 0 | 隐藏规则 | `parking`、`bridge`、`toilet`、`bicycle`（共享单车桩）、`picnic-site`、`information`、`drinking-water`；`maki_beta=taxi/parking-paid`；`class` 为 building / place_like / general / motorist 的 `marker` | 先剔除噪音 |
| 1 | `brand` 白名单 | 星巴克 → `drink.coffee`；肯德基 → `food.fried_chicken`；全聚德 → `food.roast_duck`；全家 → `grocery.convenience` | 维护几十个高频品牌即可 |
| 3 | 具体 `maki` | `restaurant-noodle` → `food.noodle`；`bakery` → `drink.bakery`；`religious-buddhist` → `religion.buddhist` | 排除 shop / restaurant / cafe 等通用 maki |
| 4 | `type`（OSM 标签值） | Books → `shop.books`；Hairdresser → `service.hair`；Hostel → `lodging.hostel`；Kindergarten → `edu.kindergarten` | 主要补 shop 和 marker |
| ~~5~~ | ~~店名关键词~~（已定不启用） | 火锅 / hot pot → `food.hotpot`；拉面 / ramen → `food.noodle`；steak / 牛排 → `food.steak`（仅 `maki=restaurant`，排除 cheese steak） | 高精度词表，中英双语 |
| 6 | 通用 `maki` | restaurant → `food.restaurant`；cafe → `drink.coffee`；shop → `shop.retail` | |
| 7 | `class` 兜底 | store_like → `shop.retail`；medical → `health.clinic` | 仍无结果则不上图 |

每个 POI 的解析结果都记下来源（brand / maki / type / name / class），方便调试和统计。

### 3.3 覆盖率（在四城样本上跑草案规则）

| 城市 | 现行规则上图率（filterrank≤3） | 方案上图率 | 方案上图中落到子类（非泛类）的比例 |
| --- | ---: | ---: | ---: |
| 旧金山 | 69% | 83% | 36% / 41%（关 / 开店名词） |
| 纽约 | 75% | 88% | 35% / 39% |
| 北京 | 58% | 75% | 39% / 44% |
| 上海 | 61% | 74% | 38% / 41% |

餐饮单看：主要显示层（filterrank≤3）的餐厅绝大多数 `maki` 就是泛 `restaurant`。

- 关掉店名关键词时，仍有 69–90% 只能显示为“泛餐厅”。
- 打开后降到 60–80%。
- 全量采样下是 36–50%。
- 这是 Mapbox 数据本身的上限：想要更多“特色餐饮”图标，只能靠品牌和店名关键词。

### 3.4 美术优先级（按四城主要显示层的出现次数）

1. **先保证 13 个大类各有兜底图**，任何子类缺图都不会空白。
2. **高频但现在没有独立图、或款数偏少的：**
   - 酒店：显示层 773 次，现在只有 3 款。
   - 医院：129 次，现在没有图。
   - 景点：150 次；纪念碑 / 城门：106 次；游艇码头 / 栈桥：75 次。
   - 大学：79 次；幼儿园：32 次。
3. **中国特色餐饮：** 面（44）、饺子 / 包子（44）、火锅（20）、烤鸭（18）、炸鸡（11）、奶茶。
4. **美国常见：** 寿司、墨西哥菜、泰式、甜甜圈、三明治。
5. **现有 125 款怎么复用：**
   - 按新 key 重挂，例如 `restaurant_*` 挂到 `food.restaurant`，`park_*` 挂到 `leisure.park`。
   - `ICON_VARIANTS` 改为以子类或大类为 key。
   - 选图仍用店名哈希固定到同一款。


### 3.5 代码改动点

- **Android** `tools/android/overlay/GodotMapPlugin.kt` 的 `queryCityPois`：除现有的 maki / class / category 外，再带上 `type`、`brand`、`maki_beta` 和 `name_en`。
- **iOS**：当前代码没有找到 iOS 端的 POI 查询；如需同样能力，要补一个对等实现。
- **`modules/map/city_map_data.gd`**：
  - 用一张数据驱动的规则表替换 `art_key` / `icon_key`（brand / maki / type / name_kw / class 五张映射表，加隐藏规则）。
  - 输出 `icon_key = 大类.子类`，并记录 `icon_source`。
- **测试**：在 `tests/map/test_city_map.gd` 里按四城样本各挑典型 POI 做用例。例如北京全聚德应得 `food.roast_duck`，纽约 Books 应得 `shop.books`。

## 4. 待拍板

1. ~~店名关键词~~：已定不启用（2026-09-28）；无名 POI 不上图。
2. 子类清单与首批美术范围：建议 13 张大类兜底图，加 20–30 个高频子类。
3. ~~Search Box~~：已定不用（2026-09-28）。

## 附录 A：完整子类表（定案规则）

- 共 13 个大类、128 个子类。其中 118 个在四城样本中出现，10 个样本无（规则保留，别的城市可能出现）。
- 次数只计有名字的 POI；“显示层”为 filterrank≤3 的四城合计。
- 解析优先级：隐藏规则 > 品牌 > 细分 maki > type > 通用 maki > class 兜底。
- 园林／花园按 `iso_3166_1` 区分。

美术 icon 数量规则（2026-09-28 用户定）：按四城“合计”取档，>1000 出 10 款，500–1000 出 8 款，200–499 出 5 款，<200 出 3 款。按此规则总计 **479 款**（3 个子类×10、8×8、17×5、100×3；其中样本无的 10 个子类占 30 款）。

| # | 大类 | 子类 key | 中文名 | 判定依据（POI 字段） | 旧金山/纽约/北京/上海 | 合计 | 显示层 | 美术 icon 数 |
| ---: | --- | --- | --- | --- | --- | ---: | ---: | ---: |
| 1 | 餐饮 | `food.restaurant` | 餐厅（泛） | maki: restaurant；class 兜底: food_and_drink | 1044/1715/360/615 | 3734 | 1697 | 10 |
| 2 | 餐饮 | `food.fast_food` | 快餐（泛） | maki: fast-food | 214/576/27/57 | 874 | 28 | 8 |
| 3 | 餐饮 | `food.pizza` | 比萨 | 品牌: 必胜客, Pizza Hut；maki: restaurant-pizza | 82/200/14/20 | 316 | 2 | 5 |
| 4 | 餐饮 | `food.burger` | 汉堡 | 品牌: 麦当劳, McDonald's, Burger King, 汉堡王 | 6/30/22/42 | 100 | 16 | 3 |
| 5 | 餐饮 | `food.sandwich` | 三明治 | 品牌: 赛百味, Subway, Pret A Manger | 10/55/3/14 | 82 | 2 | 3 |
| 6 | 餐饮 | `food.noodle` | 面馆 | maki: restaurant-noodle | 18/20/10/27 | 75 | 1 | 3 |
| 7 | 餐饮 | `food.seafood` | 海鲜 | maki: restaurant-seafood | 28/34/0/1 | 63 | 6 | 3 |
| 8 | 餐饮 | `food.fried_chicken` | 炸鸡 | 品牌: 肯德基, KFC | 1/1/20/26 | 48 | 11 | 3 |
| 9 | 餐饮 | `food.mexican` | 墨西哥菜 | 品牌: Chipotle | 5/34/0/0 | 39 | 0 | 3 |
| 10 | 餐饮 | `food.food_court` | 美食广场 | type: Food Court | 8/16/1/8 | 33 | 3 | 3 |
| 11 | 餐饮 | `food.western` | 西餐 | 品牌: Wagas | 0/0/1/14 | 15 | 5 | 3 |
| 12 | 餐饮 | `food.dumpling` | 包子／饺子 | 品牌: 庆丰包子铺 | 0/0/11/0 | 11 | 8 | 3 |
| 13 | 餐饮 | `food.roast_duck` | 烤鸭 | 品牌: 全聚德, 便宜坊 | 0/0/7/1 | 8 | 8 | 3 |
| 14 | 餐饮 | `food.steak` | 牛排 | 品牌: Outback Steakhouse, Morton's The Steakhouse, 王品牛排 | 1/2/0/0 | 3 | 0 | 3 |
| 15 | 餐饮 | `food.hotpot` | 火锅 | 品牌: 海底捞 | 样本无 | 0 | 0 | 3 |
| 16 | 餐饮 | `food.bbq` | 烧烤 | maki: restaurant-bbq | 样本无 | 0 | 0 | 3 |
| 17 | 餐饮 | `food.sushi` | 寿司 | maki: restaurant-sushi | 样本无 | 0 | 0 | 3 |
| 18 | 饮品甜点 | `drink.coffee` | 咖啡馆 | 品牌: Starbucks, 星巴克, 瑞幸咖啡, Manner Coffee, Costa咖啡, Peet's Coffee, Philz Coffee, Blue Bottle Coffee；maki: cafe | 481/706/107/431 | 1725 | 141 | 10 |
| 19 | 饮品甜点 | `drink.bar` | 酒吧 | maki: bar | 250/355/44/130 | 779 | 152 | 8 |
| 20 | 饮品甜点 | `drink.bakery` | 面包／烘焙 | 品牌: Le Pain Quotidien；maki: bakery；type: Pastry | 91/148/34/42 | 315 | 26 | 5 |
| 21 | 饮品甜点 | `drink.pub` | 啤酒馆／精酿 | maki: beer；type: Brewery | 91/148/7/15 | 261 | 12 | 5 |
| 22 | 饮品甜点 | `drink.ice_cream` | 冰淇淋 | maki: ice-cream | 31/52/9/21 | 113 | 2 | 3 |
| 23 | 饮品甜点 | `drink.nightclub` | 夜店 | type: Nightclub | 31/25/2/14 | 72 | 12 | 3 |
| 24 | 饮品甜点 | `drink.dessert` | 甜品／糖果／巧克力 | maki: confectionery；type: Chocolate | 23/37/4/4 | 68 | 0 | 3 |
| 25 | 饮品甜点 | `drink.donut` | 甜甜圈 | 品牌: Dunkin' | 0/61/0/0 | 61 | 2 | 3 |
| 26 | 饮品甜点 | `drink.milk_tea` | 奶茶 | 品牌: 蜜雪冰城, 喜茶, 奈雪的茶, CoCo都可 | 0/0/18/14 | 32 | 1 | 3 |
| 27 | 饮品甜点 | `drink.tea` | 茶馆／茶叶 | maki: teahouse；type: Tea | 7/6/4/5 | 22 | 0 | 3 |
| 28 | 食品零售 | `grocery.convenience` | 便利店 | 品牌: 全家, 罗森, 7-Eleven；maki: convenience | 172/222/63/257 | 714 | 99 | 8 |
| 29 | 食品零售 | `grocery.supermarket` | 超市 | maki: grocery；class 兜底: food_and_drink_stores | 52/125/31/58 | 266 | 170 | 5 |
| 30 | 食品零售 | `grocery.alcohol` | 酒类专卖 | maki: alcohol-shop；type: Wine | 68/142/2/8 | 220 | 3 | 5 |
| 31 | 食品零售 | `grocery.deli` | 熟食店 | type: Deli | 25/55/0/0 | 80 | 5 | 3 |
| 32 | 食品零售 | `grocery.market` | 市场 | type: Marketplace, Seafood | 15/21/4/5 | 45 | 8 | 3 |
| 33 | 食品零售 | `grocery.greengrocer` | 果蔬店 | type: Greengrocer | 24/4/4/7 | 39 | 4 | 3 |
| 34 | 食品零售 | `grocery.butcher` | 肉铺 | type: Butcher | 14/8/0/5 | 27 | 0 | 3 |
| 35 | 商店 | `shop.retail` | 零售（泛） | class 兜底: store_like | 423/489/63/113 | 1088 | 86 | 10 |
| 36 | 商店 | `shop.clothing` | 服装 | maki: clothing-store；type: Boutique, Fabric, Tailor | 219/476/58/115 | 868 | 28 | 8 |
| 37 | 商店 | `shop.jewelry` | 珠宝／钟表 | maki: jewelry-store, watch；type: Watches | 72/118/20/35 | 245 | 3 | 5 |
| 38 | 商店 | `shop.gift` | 礼品 | maki: gift；type: Gift | 99/79/7/11 | 196 | 4 | 3 |
| 39 | 商店 | `shop.furniture` | 家具家居 | maki: furniture；type: Houseware, Interior Decoration, Kitchen | 84/84/3/11 | 182 | 7 | 3 |
| 40 | 商店 | `shop.electronics` | 电子／手机 | maki: mobile-phone；type: Electronics, Computer, Camera | 38/87/22/23 | 170 | 7 | 3 |
| 41 | 商店 | `shop.mall` | 商场／百货 | maki: department-store；type: Mall, Department Store | 16/37/33/58 | 144 | 45 | 3 |
| 42 | 商店 | `shop.shoes` | 鞋店 | maki: shoe | 19/66/9/17 | 111 | 2 | 3 |
| 43 | 商店 | `shop.books` | 书店 | type: Books | 35/30/18/17 | 100 | 13 | 3 |
| 44 | 商店 | `shop.optician` | 眼镜 | maki: optician | 29/63/2/2 | 96 | 0 | 3 |
| 45 | 商店 | `shop.florist` | 花店 | maki: florist；type: Florist, Garden Centre | 48/38/4/2 | 92 | 4 | 3 |
| 46 | 商店 | `shop.tobacco` | 烟草 | type: Tobacco | 26/51/0/15 | 92 | 2 | 3 |
| 47 | 商店 | `shop.cosmetics` | 美妆 | type: Cosmetics, Chemist | 16/63/0/6 | 85 | 2 | 3 |
| 48 | 商店 | `shop.pet` | 宠物店 | type: Pet, Pet Grooming | 30/48/0/4 | 82 | 2 | 3 |
| 49 | 商店 | `shop.bicycle` | 自行车店 | type: Bicycle | 25/24/12/13 | 74 | 11 | 3 |
| 50 | 商店 | `shop.hardware` | 五金 | maki: hardware | 26/27/1/4 | 58 | 5 | 3 |
| 51 | 商店 | `shop.sports` | 运动户外用品 | type: Sports, Outdoor | 14/16/8/11 | 49 | 2 | 3 |
| 52 | 商店 | `shop.art` | 艺术品 | type: Art | 20/15/4/5 | 44 | 3 | 3 |
| 53 | 商店 | `shop.stationery` | 文具 | type: Stationery | 12/23/0/3 | 38 | 0 | 3 |
| 54 | 商店 | `shop.antique` | 古董／二手 | type: Antiques, Second Hand | 10/20/0/2 | 32 | 3 | 3 |
| 55 | 商店 | `shop.toys` | 玩具 | type: Toys | 5/15/6/2 | 28 | 1 | 3 |
| 56 | 生活服务 | `service.bank` | 银行 | maki: bank | 120/256/104/185 | 665 | 54 | 8 |
| 57 | 生活服务 | `service.beauty` | 美容／按摩／纹身 | type: Beauty, Massage, Tattoo | 204/292/6/33 | 535 | 6 | 8 |
| 58 | 生活服务 | `service.generic` | 商业服务（泛） | class 兜底: commercial_services | 169/145/61/101 | 476 | 110 | 5 |
| 59 | 生活服务 | `service.hair` | 理发 | type: Hairdresser | 163/208/6/26 | 403 | 3 | 5 |
| 60 | 生活服务 | `service.laundry` | 洗衣／干洗 | maki: laundry；type: Dry Cleaning | 124/146/1/4 | 275 | 10 | 5 |
| 61 | 生活服务 | `service.post` | 邮局／复印 | maki: post；type: Copyshop | 67/71/15/27 | 180 | 13 | 3 |
| 62 | 生活服务 | `service.car` | 车行／租车 | maki: car-rental, car | 39/39/7/11 | 96 | 1 | 3 |
| 63 | 生活服务 | `service.car_repair` | 修车 | maki: car-repair | 78/5/0/0 | 83 | 9 | 3 |
| 64 | 生活服务 | `service.travel` | 旅行社／票务 | maki: suitcase；type: Ticket | 19/19/8/6 | 52 | 7 | 3 |
| 65 | 生活服务 | `service.fuel` | 加油站 | maki: fuel | 24/6/7/10 | 47 | 22 | 3 |
| 66 | 生活服务 | `service.charging` | 充电站 | maki: charging-station | 14/24/1/7 | 46 | 2 | 3 |
| 67 | 住宿 | `lodging.hotel` | 酒店 | maki: lodging；class 兜底: lodging | 303/334/161/183 | 981 | 773 | 8 |
| 68 | 住宿 | `lodging.hostel` | 青旅 | type: Hostel | 16/6/19/14 | 55 | 22 | 3 |
| 69 | 文化景点 | `culture.monument` | 纪念碑／城门／历史遗迹 | maki: monument；type: City Gate；class 兜底: historic | 103/115/104/30 | 352 | 106 | 5 |
| 70 | 文化景点 | `culture.theatre` | 剧院／演出场地 | maki: theatre；type: Events Venue | 68/160/30/31 | 289 | 160 | 5 |
| 71 | 文化景点 | `culture.gallery` | 美术馆／艺术中心 | maki: art-gallery | 77/161/5/17 | 260 | 98 | 5 |
| 72 | 文化景点 | `culture.attraction` | 景点 | maki: attraction；class 兜底: arts_and_entertainment, landmark | 27/55/44/86 | 212 | 145 | 5 |
| 73 | 文化景点 | `culture.museum` | 博物馆 | maki: museum | 36/36/35/43 | 150 | 123 | 3 |
| 74 | 文化景点 | `culture.cinema` | 电影院 | maki: cinema | 11/22/6/21 | 60 | 6 | 3 |
| 75 | 文化景点 | `culture.viewpoint` | 观景台 | maki: viewpoint | 11/10/1/5 | 27 | 17 | 3 |
| 76 | 文化景点 | `culture.tower` | 塔／钟鼓楼 | type: Tower | 0/1/8/7 | 16 | 8 | 3 |
| 77 | 文化景点 | `culture.music` | 音乐场所 | maki: music | 7/8/0/1 | 16 | 1 | 3 |
| 78 | 文化景点 | `culture.palace` | 宫殿／城堡 | maki: castle；type: Palace | 0/1/12/0 | 13 | 12 | 3 |
| 79 | 休闲运动 | `leisure.park` | 公园（泛） | maki: park, garden；class 兜底: park_like | 109/143/26/42 | 320 | 167 | 5 |
| 80 | 休闲运动 | `leisure.fitness` | 健身房 | maki: fitness-centre；type: Fitness Centre；class 兜底: sport_and_leisure | 124/138/15/14 | 291 | 27 | 5 |
| 81 | 休闲运动 | `leisure.playground` | 儿童游乐场 | maki: playground | 48/39/0/1 | 88 | 35 | 3 |
| 82 | 休闲运动 | `leisure.sports_centre` | 体育中心／体育馆 | type: Sports Centre, Sports Hall | 28/31/4/7 | 70 | 25 | 3 |
| 83 | 休闲运动 | `leisure.garden` | 花园（海外） | type: Garden（非中日港台） | 24/30/0/0 | 54 | 13 | 3 |
| 84 | 休闲运动 | `leisure.amusement` | 游乐园／电玩／密室 | maki: amusement-park；type: Escape Game, Arcade Machine, Amusement Arcade | 24/4/1/13 | 42 | 5 | 3 |
| 85 | 休闲运动 | `leisure.pitch` | 运动场地（泛） | maki: pitch | 8/21/2/9 | 40 | 24 | 3 |
| 86 | 休闲运动 | `leisure.dog_park` | 狗公园 | maki: dog-park | 9/19/0/0 | 28 | 13 | 3 |
| 87 | 休闲运动 | `leisure.classical_garden` | 园林（中日港台） | type: Garden（中日港台） | 0/0/7/7 | 14 | 8 | 3 |
| 88 | 休闲运动 | `leisure.dance` | 舞蹈室 | type: Dance | 7/5/0/1 | 13 | 1 | 3 |
| 89 | 休闲运动 | `leisure.martial_arts` | 武馆／道场 | type: Dojo | 7/5/0/0 | 12 | 0 | 3 |
| 90 | 休闲运动 | `leisure.nature` | 自然保护区／树林 | type: Nature Reserve, Forest, Wood, Protected Area, National Park | 4/3/1/2 | 10 | 8 | 3 |
| 91 | 休闲运动 | `leisure.lawn` | 草坪／休闲场地 | type: Recreation Ground | 3/4/0/2 | 9 | 6 | 3 |
| 92 | 休闲运动 | `leisure.swimming` | 游泳池 | maki: swimming | 1/5/2/0 | 8 | 5 | 3 |
| 93 | 休闲运动 | `leisure.basketball` | 篮球场 | maki: basketball | 0/4/1/2 | 7 | 3 | 3 |
| 94 | 休闲运动 | `leisure.ice_rink` | 溜冰场 | type: Ice Rink | 1/5/0/0 | 6 | 2 | 3 |
| 95 | 休闲运动 | `leisure.pocket_park` | 口袋公园 | type: Parklet | 5/0/0/0 | 5 | 0 | 3 |
| 96 | 休闲运动 | `leisure.zoo` | 动物园／水族馆 | maki: zoo, aquarium | 1/2/0/1 | 4 | 4 | 3 |
| 97 | 休闲运动 | `leisure.community_garden` | 社区菜园 | type: Allotments | 4/0/0/0 | 4 | 0 | 3 |
| 98 | 休闲运动 | `leisure.stadium` | 体育场 | maki: stadium | 3/1/0/0 | 4 | 4 | 3 |
| 99 | 休闲运动 | `leisure.bowling` | 保龄球馆 | maki: bowling-alley | 2/1/0/0 | 3 | 0 | 3 |
| 100 | 休闲运动 | `leisure.picnic` | 野餐区 | type: Picnic Site | 1/0/0/0 | 1 | 0 | 3 |
| 101 | 休闲运动 | `leisure.karaoke` | KTV | type: Karaoke | 0/1/0/0 | 1 | 0 | 3 |
| 102 | 休闲运动 | `leisure.table_tennis` | 乒乓球 | maki: table-tennis | 0/1/0/0 | 1 | 0 | 3 |
| 103 | 休闲运动 | `leisure.baseball` | 棒球／击球练习 | maki: baseball；type: Batting Cage | 1/0/0/0 | 1 | 0 | 3 |
| 104 | 休闲运动 | `leisure.american_football` | 美式橄榄球场 | maki: american-football | 样本无 | 0 | 0 | 3 |
| 105 | 休闲运动 | `leisure.soccer` | 足球场 | maki: soccer | 样本无 | 0 | 0 | 3 |
| 106 | 休闲运动 | `leisure.volleyball` | 排球场 | maki: volleyball | 样本无 | 0 | 0 | 3 |
| 107 | 休闲运动 | `leisure.casino` | 赌场 | maki: casino；type: Casino | 样本无 | 0 | 0 | 3 |
| 108 | 休闲运动 | `leisure.tennis` | 网球场 | maki: tennis | 样本无 | 0 | 0 | 3 |
| 109 | 休闲运动 | `leisure.golf` | 高尔夫 | maki: golf | 样本无 | 0 | 0 | 3 |
| 110 | 休闲运动 | `leisure.skate` | 滑板场 | maki: skateboard | 样本无 | 0 | 0 | 3 |
| 111 | 教育 | `edu.school` | 中小学 | maki: school；class 兜底: education | 88/195/99/145 | 527 | 267 | 8 |
| 112 | 教育 | `edu.college` | 大学 | maki: college；type: University | 53/107/8/5 | 173 | 79 | 3 |
| 113 | 教育 | `edu.kindergarten` | 幼儿园 | type: Kindergarten | 13/16/7/38 | 74 | 32 | 3 |
| 114 | 教育 | `edu.library` | 图书馆 | maki: library | 17/29/5/9 | 60 | 18 | 3 |
| 115 | 医疗 | `health.clinic` | 诊所 | maki: doctor；class 兜底: medical | 72/174/3/6 | 255 | 12 | 5 |
| 116 | 医疗 | `health.pharmacy` | 药店 | 品牌: Walgreens, CVS Pharmacy, Duane Reade；maki: pharmacy | 35/126/5/14 | 180 | 12 | 3 |
| 117 | 医疗 | `health.hospital` | 医院 | maki: hospital；type: Hospital | 15/26/47/74 | 162 | 129 | 3 |
| 118 | 医疗 | `health.dentist` | 牙科 | maki: dentist | 36/65/0/4 | 105 | 2 | 3 |
| 119 | 医疗 | `health.vet` | 宠物医院 | maki: veterinary | 12/35/0/0 | 47 | 0 | 3 |
| 120 | 宗教 | `religion.christian` | 教堂 | maki: religious-christian | 116/132/10/18 | 276 | 102 | 5 |
| 121 | 宗教 | `religion.generic` | 宗教场所（泛） | maki: place-of-worship；class 兜底: religion | 12/16/14/14 | 56 | 26 | 3 |
| 122 | 宗教 | `religion.buddhist` | 佛寺 | maki: religious-buddhist | 14/4/14/8 | 40 | 19 | 3 |
| 123 | 宗教 | `religion.jewish` | 犹太会堂 | maki: religious-jewish | 3/22/0/1 | 26 | 8 | 3 |
| 124 | 宗教 | `religion.muslim` | 清真寺 | maki: religious-muslim | 3/2/4/2 | 11 | 5 | 3 |
| 125 | 公共机构 | `civic.town_hall` | 市政厅／社区中心／法院 | maki: town-hall；type: Community Centre, Courthouse；class 兜底: public_facilities | 95/47/12/25 | 179 | 38 | 3 |
| 126 | 公共机构 | `civic.police` | 警察局 | maki: police | 10/11/18/17 | 56 | 21 | 3 |
| 127 | 公共机构 | `civic.fire` | 消防站 | maki: fire-station | 16/21/4/1 | 42 | 8 | 3 |
| 128 | 交通 | `transport.harbor` | 码头／栈桥 | maki: harbor；type: Pier | 53/37/1/5 | 96 | 75 | 3 |

**不上图（隐藏规则）：**
- 无名 POI。
- maki 为 parking、parking-garage、bridge、toilet、drinking-water、bicycle、information、slipway、prison、cemetery、communications-tower 的 POI。
- `maki_beta` 为 taxi、parking-paid 的 POI。
- `picnic-site` 中 type 不是 Picnic Site 的（野餐桌）。
- 呼号形式的广播发射塔（如 WNYE-TV）。
- class 为 building、place_like、general、motorist、visitor_amenities、industrial，且没有命中更细规则的 POI。

## 附录 B：定案规则下各子类在四城的出现次数（只计有名字的 POI）

| 子类 | 旧金山 | 纽约 | 北京 | 上海 | 合计 | 其中 filterrank≤3 |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| `food.restaurant` | 1044 | 1715 | 360 | 615 | 3734 | 1697 |
| `drink.coffee` | 481 | 706 | 107 | 431 | 1725 | 141 |
| `shop.retail` | 423 | 489 | 63 | 113 | 1088 | 86 |
| `lodging.hotel` | 303 | 334 | 161 | 183 | 981 | 773 |
| `food.fast_food` | 214 | 576 | 27 | 57 | 874 | 28 |
| `shop.clothing` | 219 | 476 | 58 | 115 | 868 | 28 |
| `drink.bar` | 250 | 355 | 44 | 130 | 779 | 152 |
| `grocery.convenience` | 172 | 222 | 63 | 257 | 714 | 99 |
| `service.bank` | 120 | 256 | 104 | 185 | 665 | 54 |
| `service.beauty` | 204 | 292 | 6 | 33 | 535 | 6 |
| `edu.school` | 88 | 195 | 99 | 145 | 527 | 267 |
| `service.generic` | 169 | 145 | 61 | 101 | 476 | 110 |
| `service.hair` | 163 | 208 | 6 | 26 | 403 | 3 |
| `culture.monument` | 103 | 115 | 104 | 30 | 352 | 106 |
| `leisure.park` | 109 | 143 | 26 | 42 | 320 | 167 |
| `food.pizza` | 82 | 200 | 14 | 20 | 316 | 2 |
| `drink.bakery` | 91 | 148 | 34 | 42 | 315 | 26 |
| `leisure.fitness` | 124 | 138 | 15 | 14 | 291 | 27 |
| `culture.theatre` | 68 | 160 | 30 | 31 | 289 | 160 |
| `religion.christian` | 116 | 132 | 10 | 18 | 276 | 102 |
| `service.laundry` | 124 | 146 | 1 | 4 | 275 | 10 |
| `grocery.supermarket` | 52 | 125 | 31 | 58 | 266 | 170 |
| `drink.pub` | 91 | 148 | 7 | 15 | 261 | 12 |
| `culture.gallery` | 77 | 161 | 5 | 17 | 260 | 98 |
| `health.clinic` | 72 | 174 | 3 | 6 | 255 | 12 |
| `shop.jewelry` | 72 | 118 | 20 | 35 | 245 | 3 |
| `grocery.alcohol` | 68 | 142 | 2 | 8 | 220 | 3 |
| `culture.attraction` | 27 | 55 | 44 | 86 | 212 | 145 |
| `shop.gift` | 99 | 79 | 7 | 11 | 196 | 4 |
| `shop.furniture` | 84 | 84 | 3 | 11 | 182 | 7 |
| `health.pharmacy` | 35 | 126 | 5 | 14 | 180 | 12 |
| `service.post` | 67 | 71 | 15 | 27 | 180 | 13 |
| `civic.town_hall` | 95 | 47 | 12 | 25 | 179 | 38 |
| `edu.college` | 53 | 107 | 8 | 5 | 173 | 79 |
| `shop.electronics` | 38 | 87 | 22 | 23 | 170 | 7 |
| `health.hospital` | 15 | 26 | 47 | 74 | 162 | 129 |
| `culture.museum` | 36 | 36 | 35 | 43 | 150 | 123 |
| `shop.mall` | 16 | 37 | 33 | 58 | 144 | 45 |
| `drink.ice_cream` | 31 | 52 | 9 | 21 | 113 | 2 |
| `shop.shoes` | 19 | 66 | 9 | 17 | 111 | 2 |
| `health.dentist` | 36 | 65 | 0 | 4 | 105 | 2 |
| `shop.books` | 35 | 30 | 18 | 17 | 100 | 13 |
| `food.burger` | 6 | 30 | 22 | 42 | 100 | 16 |
| `transport.harbor` | 53 | 37 | 1 | 5 | 96 | 75 |
| `shop.optician` | 29 | 63 | 2 | 2 | 96 | 0 |
| `service.car` | 39 | 39 | 7 | 11 | 96 | 1 |
| `shop.tobacco` | 26 | 51 | 0 | 15 | 92 | 2 |
| `shop.florist` | 48 | 38 | 4 | 2 | 92 | 4 |
| `leisure.playground` | 48 | 39 | 0 | 1 | 88 | 35 |
| `shop.cosmetics` | 16 | 63 | 0 | 6 | 85 | 2 |
| `service.car_repair` | 78 | 5 | 0 | 0 | 83 | 9 |
| `shop.pet` | 30 | 48 | 0 | 4 | 82 | 2 |
| `food.sandwich` | 10 | 55 | 3 | 14 | 82 | 2 |
| `grocery.deli` | 25 | 55 | 0 | 0 | 80 | 5 |
| `food.noodle` | 18 | 20 | 10 | 27 | 75 | 1 |
| `shop.bicycle` | 25 | 24 | 12 | 13 | 74 | 11 |
| `edu.kindergarten` | 13 | 16 | 7 | 38 | 74 | 32 |
| `drink.nightclub` | 31 | 25 | 2 | 14 | 72 | 12 |
| `leisure.sports_centre` | 28 | 31 | 4 | 7 | 70 | 25 |
| `drink.dessert` | 23 | 37 | 4 | 4 | 68 | 0 |
| `food.seafood` | 28 | 34 | 0 | 1 | 63 | 6 |
| `drink.donut` | 0 | 61 | 0 | 0 | 61 | 2 |
| `culture.cinema` | 11 | 22 | 6 | 21 | 60 | 6 |
| `edu.library` | 17 | 29 | 5 | 9 | 60 | 18 |
| `shop.hardware` | 26 | 27 | 1 | 4 | 58 | 5 |
| `religion.generic` | 12 | 16 | 14 | 14 | 56 | 26 |
| `civic.police` | 10 | 11 | 18 | 17 | 56 | 21 |
| `lodging.hostel` | 16 | 6 | 19 | 14 | 55 | 22 |
| `leisure.garden` | 24 | 30 | 0 | 0 | 54 | 13 |
| `service.travel` | 19 | 19 | 8 | 6 | 52 | 7 |
| `shop.sports` | 14 | 16 | 8 | 11 | 49 | 2 |
| `food.fried_chicken` | 1 | 1 | 20 | 26 | 48 | 11 |
| `service.fuel` | 24 | 6 | 7 | 10 | 47 | 22 |
| `health.vet` | 12 | 35 | 0 | 0 | 47 | 0 |
| `service.charging` | 14 | 24 | 1 | 7 | 46 | 2 |
| `grocery.market` | 15 | 21 | 4 | 5 | 45 | 8 |
| `shop.art` | 20 | 15 | 4 | 5 | 44 | 3 |
| `civic.fire` | 16 | 21 | 4 | 1 | 42 | 8 |
| `leisure.amusement` | 24 | 4 | 1 | 13 | 42 | 5 |
| `religion.buddhist` | 14 | 4 | 14 | 8 | 40 | 19 |
| `leisure.pitch` | 8 | 21 | 2 | 9 | 40 | 24 |
| `grocery.greengrocer` | 24 | 4 | 4 | 7 | 39 | 4 |
| `food.mexican` | 5 | 34 | 0 | 0 | 39 | 0 |
| `shop.stationery` | 12 | 23 | 0 | 3 | 38 | 0 |
| `food.food_court` | 8 | 16 | 1 | 8 | 33 | 3 |
| `shop.antique` | 10 | 20 | 0 | 2 | 32 | 3 |
| `drink.milk_tea` | 0 | 0 | 18 | 14 | 32 | 1 |
| `leisure.dog_park` | 9 | 19 | 0 | 0 | 28 | 13 |
| `shop.toys` | 5 | 15 | 6 | 2 | 28 | 1 |
| `grocery.butcher` | 14 | 8 | 0 | 5 | 27 | 0 |
| `culture.viewpoint` | 11 | 10 | 1 | 5 | 27 | 17 |
| `religion.jewish` | 3 | 22 | 0 | 1 | 26 | 8 |
| `drink.tea` | 7 | 6 | 4 | 5 | 22 | 0 |
| `culture.music` | 7 | 8 | 0 | 1 | 16 | 1 |
| `culture.tower` | 0 | 1 | 8 | 7 | 16 | 8 |
| `food.western` | 0 | 0 | 1 | 14 | 15 | 5 |
| `leisure.classical_garden` | 0 | 0 | 7 | 7 | 14 | 8 |
| `leisure.dance` | 7 | 5 | 0 | 1 | 13 | 1 |
| `culture.palace` | 0 | 1 | 12 | 0 | 13 | 12 |
| `leisure.martial_arts` | 7 | 5 | 0 | 0 | 12 | 0 |
| `religion.muslim` | 3 | 2 | 4 | 2 | 11 | 5 |
| `food.dumpling` | 0 | 0 | 11 | 0 | 11 | 8 |
| `leisure.nature` | 4 | 3 | 1 | 2 | 10 | 8 |
| `leisure.lawn` | 3 | 4 | 0 | 2 | 9 | 6 |
| `leisure.swimming` | 1 | 5 | 2 | 0 | 8 | 5 |
| `food.roast_duck` | 0 | 0 | 7 | 1 | 8 | 8 |
| `leisure.basketball` | 0 | 4 | 1 | 2 | 7 | 3 |
| `leisure.ice_rink` | 1 | 5 | 0 | 0 | 6 | 2 |
| `leisure.pocket_park` | 5 | 0 | 0 | 0 | 5 | 0 |
| `leisure.community_garden` | 4 | 0 | 0 | 0 | 4 | 0 |
| `leisure.stadium` | 3 | 1 | 0 | 0 | 4 | 4 |
| `leisure.zoo` | 1 | 2 | 0 | 1 | 4 | 4 |
| `food.steak` | 1 | 2 | 0 | 0 | 3 | 0 |
| `leisure.bowling` | 2 | 1 | 0 | 0 | 3 | 0 |
| `leisure.picnic` | 1 | 0 | 0 | 0 | 1 | 0 |
| `leisure.baseball` | 1 | 0 | 0 | 0 | 1 | 0 |
| `leisure.karaoke` | 0 | 1 | 0 | 0 | 1 | 0 |
| `leisure.table_tennis` | 0 | 1 | 0 | 0 | 1 | 0 |
