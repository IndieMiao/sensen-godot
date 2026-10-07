# Gensen UI 组件体系归类与复用总结

**本轮组件归类、复用改造与验收已完成。** 720 张业务弹窗已接入共享组合组件；当前审阅页的 222 个主组件、25 个组件集全部归类。组件生成包已同步本轮结构并通过完整性检查。

直接查看：[Figma 组件体系与维护说明](https://www.figma.com/design/OMLTC3yw3u2WDjOZhLnhaR/Gensen--US-?node-id=946-76647)。说明板包含不同物品和数量共用一个主件的实例，后续调整可以从这里进入。

## 发现的问题

上一轮删除了完全相同弹窗的副本，并缩短了过高的空白区域，但「内容不同、结构相同」的弹窗仍需要分别维护。例如 Apple ×2／×6、Carp ×2／×7，虽然外观几乎一样，仍分别组装标题、数量、正文与关闭区。修改边距或信息层级时，无法可靠地一次调整全部使用处。

另一类问题是组件名称相似、归入同一个变体集合，却没有真正引用共同的上游主件。变体集合本身不提供继承；复制出更多 master 也不会自动解决复用。

因此，本轮把物品名称、数量、价格和文案归为实例内容，把布局、状态语言和公共样式归到共享组件。**Apple ×2 改成 ×6，只改数量，不增加主件或变体。**

## 已完成的改造

| 范围 | 完成结果 |
|---|---|
| 常规信息弹窗 | 576 张接入 InformationSheet，共享外壳、身份头、正文区和关闭区 |
| Pin／Unpin 状态 | 84 张使用同一个 InformationSheet 组合结构，保留各自物品、数量与状态切换 |
| 反馈弹窗 | 60 张接入 Feedback，复用已有 Toast 和关闭组件 |
| 正文段落 | 685 个直接绘制的正文改为共享 Paragraph 实例 |
| 特殊覆盖层 | 15 张场景预览、教学等覆盖层保留专属结构 |
| 全库分类 | 222 个实际主件、25 个组件集全部归类，未归类项为 0 |

InformationSheet 共承载 **660 个业务实例**，由 576 张信息窗和 84 张 Pin 状态组成。不同业务仍保留自己的目标 Frame、文本、变量和连线；复用样式不会把不同数量或不同操作结果合并成同一业务状态。

新增的三个公共修改入口：

| 入口 | Figma 主件 | 调整什么 |
|---|---|---|
| InformationSheet | [932:71686](https://www.figma.com/design/OMLTC3yw3u2WDjOZhLnhaR/Gensen--US-?node-id=932-71686) | 信息窗表面、内边距、标题／正文／关闭区的布局 |
| Paragraph | [932:71684](https://www.figma.com/design/OMLTC3yw3u2WDjOZhLnhaR/Gensen--US-?node-id=932-71684) | 共享正文的字体、行距与文本样式 |
| Feedback | [932:71702](https://www.figma.com/design/OMLTC3yw3u2WDjOZhLnhaR/Gensen--US-?node-id=932-71702) | 反馈消息与关闭区的组合布局 |

信息窗表面直接绑定公共 surface、border、radius tokens，适应内容高度；内部身份头是真正的 ObjectHeader 实例。正文使用原生内容 Slot，继续容纳现有 Fact、Cost、ItemRow、NeedTile 与语义动作组件。

## 从基础到业务的组件层级

| 层级 | 负责内容 | 修改方式 |
|---|---|---|
| Tokens／文字样式 | 颜色、Nunito 字体、字号、间距、圆角、触区 | 修改 Variables／Text Styles，影响绑定它们的组件 |
| 基础组件 | 身份、数量、效果、事实、费用、材料条件、按钮、图标 | 修改实际使用的基础主件 |
| 组合组件 | 信息窗、快捷栏、库存、厨房、柜台、Profile 等结构 | 保留内部基础实例，统一布局和可选区域 |
| 业务实例 | 本次物品、数量、来源、门槛、动作和原型上下文 | 覆盖内容属性、设置必要行为，不复制或脱离主件 |

必须沿真实的实例关系修改。**当前 ObjectHeader 的数量字段仍由 ObjectHeader 自身管理**；修改独立 Quantity 主件，并不会自动修改 ObjectHeader 内的数量。信息窗的数量样式应进入 ObjectHeader 调整。本轮没有把尚未实施的更深层基础组件拆分描述为已完成。

## 信息弹窗的六种内容组合

迁移前 576 张信息窗有 56 种具体正文排列，但不需要 56 套独立外壳。它们可以归入以下组合，并在同一内容 Slot 中按需要搭配。

| 内容组合 | 结构 | 示例 |
|---|---|---|
| 简洁物品 | 身份头＋可选数量／效果＋关闭 | Apple、Carp |
| 说明 | 身份头＋正文段落 | Food Buff 规则、来源说明 |
| 事实与费用 | 身份头＋Fact／Cost | 库存、价格、成长、装备属性 |
| 材料与门槛 | 身份头＋所得＋NeedTile | 制作、升级、解锁 |
| 条目列表 | 身份头＋ItemRow 和附属事实 | Fishing slot、居民、采集点 |
| 操作组合 | 上述内容＋Command／Navigation／Dismiss | Pin、Equip、Buy、查看来源 |

保持已验收的内容自适应规则：短说明不撑成整张高面板，长内容按完整行滚动，关闭入口明确可见。材料的满足、不足和未知必须区分，不能把未知库存当作 0 或绿色已满足。

## 属性与变体怎么选

| 类型 | 用于 | 不用于 |
|---|---|---|
| TEXT | 名称、数量、数量含义、效果、正文、事实值、按钮文案 | 用不同文字暗中改变动作语义 |
| BOOLEAN | 是否显示数量、状态、效果、说明或次要区域 | 推测未知库存 |
| INSTANCE_SWAP | 图标、允许替换的内容模块 | 整张 UI 截图 |
| SLOT | 数量可变的正文行、材料、列表和操作组件 | 脱离规范的任意排版 |
| VARIANT | 默认／选中／空，满足／不足／未知，主要／次要／危险等状态 | Apple／Carp、数量 2／6／7、具体价格或目标页面 |

Pin 是一种业务偏好状态，不需要每种种子或鱼饵各建一套 master。动作也不因视觉复用而合并：执行使用 Command，打开信息使用 Navigation，关闭使用 Dismiss；各业务目标和变量继续属于对应实例。

## 全库修改入口

完整逐主件 ID、家族、属性边界与引用范围在 [family-catalog.json](cloud/component-consolidation/family-catalog.json)。以下为日常维护时最常用的入口。

| 家族 | 主要入口 | 应统一调整的内容 |
|---|---|---|
| 身份与信息 | ObjectHeader `483:196`；ItemRow `483:228`；SelectedItem `633:41257` | 标题、状态、效果与数量分区 |
| 事实与条件 | Fact `483:222`；Cost `483:225`；NeedTile 集 `483:261` | 左侧标签、右侧数值、费用强调、材料三态 |
| 执行与导航 | CommandButton 集 `483:216`；NavigationRow `483:217`；Dismiss `483:220`；Close `483:336` | 动作语义、按钮外观与触区 |
| 库存与装备 | Compact/InventoryCell 集 `633:41278`；Compact/GearSlot 集 `663:61299` | 五列库存格、六装备槽、选中和空态 |
| 快捷栏 | Compact/QuickSlot 集 `633:41279`；QuickEnd/Bag `907:72112`；QuickEnd/Close `907:72121` | 统一 68px 行高、名称、数量、钉住、空槽和末端入口 |
| HUD 与世界操作 | HUD `483:304`；Compact/HUD `633:41154`；SceneAction `488:781`；FacilityMarker 集 `534:13708` | 资源、位置、主行动、工具与设施标记 |
| 厨房 | Compact/Kitchen/Mode、Slot、Cell、Recipe；HeatRing | 菜谱信息、投料槽、火候与多灶状态 |
| 柜台 | Compact/ShopProduct 集 `702:80447` | essential／detailed 两种行结构；商品和价格为内容属性 |
| Avatar | Part Tile 集 `594:37683`；Wardrobe 集 `629:38466` | 真实角色预览、五分类、三列部件网格 |
| 场景控件 | ReferenceCatchProgress、Hook、ReelMeter、Joystick、Energy、StatusBadge | 沿用的钓鱼、体力和世界状态控件；Reference 前缀不表示废弃 |
| 资产与兼容 | 原图标、真实角色素材、Legacy 系列 | 保留原资产来源与跨页依赖，不能按命名批量删除 |

**Legacy 必须保留兼容。** 实际扫描确认，7 个 Legacy 主件仍在其它页面 `578:18207` 有 72 个实例引用，包括旧库存格、快捷槽和选中项摘要。本页完成迁移不代表其它页面已替换。只有全部页面引用清零、替换效果验证后，才可讨论删除。

## 后续调整的推荐方法

1. 改全局颜色、字号、圆角或间距，先找到对应 Variables／Text Styles，避免逐实例重复覆盖。
2. 改信息窗布局，修改 InformationSheet；改信息窗标题、数量、状态和效果，修改其实际使用的 ObjectHeader；改正文，修改 Paragraph。
3. 改单个物品的名字、库存或效果，只修改业务实例属性。不要 detach，也不要为新数量复制主件。
4. 加事实、材料或操作，在 Content Slot 中放入对应共享组件，保持内容高度与滚动规则。
5. 修改后抽查 Apple ×2／×6、Carp ×2／×7，以及长列表、带材料条件和带操作的实例。外观应一起变化，数值和业务行为仍各自正确。

## 验收结果与边界

720 张迁移弹窗逐帧原生审计通过，问题 0；13 个视觉标杆通过。共享间距从 12 改为 16 的实际试验中，Apple ×2／×6 与 Carp ×2／×7 高度同步增加 4，Pin 和图鉴示例增加 8，所有文字与数量保持。随后还原为 12，独立回读确认所有示例恢复原高度。

最终全局检查确认：735 个覆盖层全部可达，1,039 个目标 ID 有效，3,841 条 NODE 动作可解析，288 张主稿完整；缺失目标、不可达覆盖层、损坏实例和未归类项均为 0。

这些结果证明组件引用、内容、原型连接与检查过的视觉效果，不等同于所有交互路径的浏览器实点、游戏运行或真机验收。未模拟的业务动作仍以已有缺口记录为准；真实角色试穿分镜也不代表任意组合的实时 3D 引擎。

## 证据与交付记录

| 证据 | 内容 |
|---|---|
| [Figma 维护说明板](https://www.figma.com/design/OMLTC3yw3u2WDjOZhLnhaR/Gensen--US-?node-id=946-76647) | 组件层级与可修改的实例示例 |
| [组件目录](cloud/component-consolidation/family-catalog.json) | 222 个主件、25 个组件集的完整分类和引用范围 |
| [迁移审计目录](cloud/component-consolidation/) | 720 张信息／Pin／反馈迁移与六批逐帧审计 |
| [继承试验](cloud/component-consolidation/inheritance-probe-read.json)／[独立还原回读](cloud/component-consolidation/inheritance-restored-readback.json) | 上游调整传播，文字不变并成功还原 |
| [全局完整性回读](cloud/component-consolidation/final-integrity-result.json) | 全部目标可达，主稿和实例完整 |
| 最终归档包 | 已更新，ZIP 读回、输入哈希与代码哈希通过 |

## 归档包验证

原生 Figma 组件生成包已同步本轮结构：38 个模块、161 个输入哈希。288 张主稿、40 处快捷栏、23 张业务补态与 20 作物图鉴的已有检查通过；独立构建的弹窗可见文本与完整反应前后相同。云端迁移统计仍以正文的实际回读为准，不把本地新生成数量混入云端数量。

- 文件：`figma-plugin/gensen-ui-refactor-plugin.zip`
- 字节数：6,697,170
- SHA-256：`9c2a9c1c8200bde8b5160aceb64ee7b2e852f46e675a1050c1dcf9fa1416933e`

本轮不涉及游戏代码部署或玩家数据变更。
