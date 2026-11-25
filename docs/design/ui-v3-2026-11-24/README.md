# UI v3 风格说明与制作规范（含动效规范、设计令牌 v3）

| 项 | 内容 |
|---|---|
| 卡片 | C-84（需求卡 C-82 拆解第 1 张） |
| 版本 | 3.0（2026-11-24）：所有者已在 Q-121 确认按方案定稿（C-84 D-177 / D-198） |
| 作者 | 顾恺之·森（UI/UX 设计师） |
| 依据 | 概念稿视频 `20261124-163029.mp4`（74.4 s，668×1448，sha256 e4ec32df…85b4）的抽帧 C-82 attachment-576～584；现状盘点 C-82#7；所有者答复 C-82#19 |
| 现状代码 | `integration/dynamicfarm` @ 653824ae：`docs/design/tokens/tokens-v2.json`、`modules/ui/kit/ui_tokens.gd`、`modules/ui/game_ui.gd`、`modules/ui/design_tokens.gd` |
| 目录 | 随 C-105 入库：`docs/design/ui-v3-2026-11-24/README.md`（本文）、`figures/`（图 1～15）；令牌单一来源 `docs/design/tokens/tokens-v3.json` |
| 下游 | C-85 补页面设计稿、C-86 生图素材、C-105 令牌与组件换肤（原 C-87，已由 C-105 接替）、C-106～C-108 页面改造（原 C-88～C-90） |

## 0. 怎么读

- **单位**：逻辑像素，Godot 视口宽 360（`project.godot` viewport 360×640，stretch `canvas_items` + `expand`），与 tokens-v2 相同。概念稿视频宽 668 px，换算系数 **1.856**；文中“实测”= 视频像素 ÷ 1.856，规范值取整到 2/4 栅格。
- **令牌命名**：`组/名`，例如 `color/action/primary`、`radius/lg`、`type/body`、`motion/duration/moderate`。文中省略 `color/` 前缀。
- **规则编号**：风格规则 S-*，组件规则 C-*，动效 M-*。每条规则都标出对应的图（概念稿标注图或示意图）。
- **对照**：每个 v3 令牌都写了它在 tokens-v2（UiTokens）、GameUi、DesignTokens 里的对应项（第 2 节表格、图 15、`tokens-v3.json` 的 `v2` / `gameUi` / `designTokens` 字段）。

图清单：

| 图 | 内容 | 来源 |
|---|---|---|
| [图 1](figures/fig-01-overview.png) | 概念稿关键帧总览与组件索引 | 概念稿 6 帧 |
| [图 2](figures/fig-02-hud.png) | HUD 顶栏标注 | 00:05.5 原尺寸帧 |
| [图 3](figures/fig-03-quickbar.png) | 快捷栏、右侧竖排按钮标注 | 00:23.5 原尺寸帧 |
| [图 4](figures/fig-04-bag-panel.png) | 模态面板（背包）标注 | 00:16 缩略帧 |
| [图 5](figures/fig-05-npc-card.png) | NPC 对话卡标注 | 00:04.6 原尺寸帧 |
| [图 6](figures/fig-06-world.png) | 场景内气泡、地块选中、收获飘字 | 多帧 |
| [图 7](figures/fig-07-phone-todo.png) | 游戏内手机、任务下拉标注 | 01:08 / 01:12 缩略帧 |
| [图 8](figures/fig-08-palette.png) | 颜色令牌 | 示意图 |
| [图 9](figures/fig-09-type.png) | 字阶 | 示意图 |
| [图 10](figures/fig-10-icons.png) | 图标风格 | 概念稿取样 |
| [图 11](figures/fig-11-components.png) | 组件状态 | 示意图 |
| [图 12](figures/fig-12-radius-space-elevation.png) | 圆角、间距、层级 | 示意图 |
| [图 13](figures/fig-13-layout.png) | 布局与安全区 | 示意图 |
| [图 14](figures/fig-14-motion.png) | 缓动曲线与动效时间线 | 示意图 |
| [图 15](figures/fig-15-token-mapping.png) | 三套旧样式 → v3 对照 | 示意图 |

## 1. 风格说明

一句话：**暖色手绘 3D 农场是主角，界面像压在画面上的几片深色玻璃和几张暖白卡片，配青柠绿操作色、全圆角和会“跳出来”的立体物件。**

| 编号 | 规则 | 图 |
|---|---|---|
| S-1 | **场景优先。** 常驻 UI 只占屏幕四边：左上头像/体力/任务，右上金币，右侧竖排 3 个按钮，底部快捷栏。中间区域不放常驻控件。 | 图 1、图 13A |
| S-2 | **两种底。** 压在场景上的常驻件用深色半透明“玻璃”（`glass/fill`），不描边、不投影；需要阅读的内容（背包、NPC 卡）用暖白纸面（`surface/paper`）加遮罩。不混用。 | 图 2、图 3、图 4 |
| S-3 | **一个操作色。** 青柠绿 `action/primary` 只给主操作和选中；面板标题条用橄榄黄绿 `surface/header`；名牌用暖灰褐 `surface/tag`。不再用 v2 的深绿、DesignTokens 的青绿和蓝紫。 | 图 4、图 5、图 8 |
| S-4 | **全圆角。** 数值和标签都是胶囊（半圆端），物品格在面板里是正圆、在快捷栏里是圆角方块，卡片圆角 16～20。没有直角控件。 | 图 3、图 4、图 12 |
| S-5 | **立体物件。** 面板左上角放一个超出边框的立体物件（背包配鱼竿和小铲），物品图标是手绘写实风、无描边；系统图标是浅色泥塑质感。替代现有 lucide 线性图标。 | 图 4、图 10 |
| S-6 | **字少、粗、短。** 数字和标签用 ExtraBold，正文最多 3 行；同一屏只保留一个最大字号。 | 图 5、图 9 |
| S-7 | **轻快有弹性。** 弹出用回弹缓动（pop），退出比进入快，场景里的东西会轻轻浮动；所有动效 ≤ 320 ms（奖励飞入除外），不挡操作。 | 图 14 |
| S-8 | **世界里的提示贴着角色。** 对话、交互、NPC 头像都用带尾巴的气泡指向对象，颜色按交互类型区分；地块选中用白色虚线框。 | 图 6 |

## 2. 设计令牌 v3

单一来源是 [`tokens-v3.json`](../tokens/tokens-v3.json)（schema 3）。生成方式沿用 v2：`tools/ui/gen_theme.gd` 读 JSON → 生成 `UiTokens` 与 `gensen_theme.tres`（C-105 实现）。

### 2.1 颜色（图 8）

| v3 令牌 | 值 | 用途 | v2（UiTokens） | GameUi | DesignTokens | 概念稿取样 |
|---|---|---|---|---|---|---|
| `color/surface/paper` | `#F3F1EA` | 面板正文底（背包、NPC 卡） | COLOR_SURFACE FBF8F1 | PAPER fffdf8 | SURFACE fffdf8 | 背包正文 #F1EFE7 |
| `color/surface/raised` | `#FFFFFF` | 白色气泡、浮起卡片、输入框 | COLOR_SURFACE_RAISED FFFFFF | CARD FFFFFF@0.97 | — | 对话“…”气泡 |
| `color/surface/sunken` | `#E6E4DC` | 纸面上的凹槽行、分段控件底 | COLOR_TILE_CORE F4EEE1 | card_style f6f5ef | SURFACE_SUNK f0f1fc | —（推导） |
| `color/surface/slot` | `#D6D7D2` | 圆形物品格（背包） | —（v2 格子用描边） | — | — | 背包空格 #D2D5D2 |
| `color/surface/header` | `#C4C63C` | 面板标题色带（背包等） | — | LIME cafa91（近似） | — | 背包标题条 #C5C534 |
| `color/surface/tag` | `#7A725E` | 名牌/标签胶囊（Bag、NPC 名字），白字 4.8:1 | — | — | — | Bag #938E7E（白字 3.1:1，加深） |
| `color/glass/fill` | `#1E1C17` @0.62 | 压在场景上的胶囊与快捷栏底 | COLOR_SCRIM_DRAWER 2F3A33@0.18（用途不同） | — | — | 快捷栏 #454239（叠在亮场景上） |
| `color/glass/fillStrong` | `#1E1C17` @0.78 | 任务下拉行、离开按钮等小面积玻璃 | — | — | — | 任务行（01:12） |
| `color/glass/slot` | `#000000` @0.18 | 快捷栏空格 | — | — | — | 快捷栏空格 #3D393B |
| `color/glass/edge` | `#FFFFFF` @0.08 | 玻璃件 1px 内描边（可选） | — | — | — | — |
| `color/text/primary` | `#2B2A26` | 浅底正文、标题 | COLOR_TEXT 2F3A33 | INK 232b30 | INK 34416f | NPC 卡文字 #272621 |
| `color/text/secondary` | `#5E5C55` | 浅底次要正文（NPC 台词） | COLOR_SECONDARY 5D6A62 | MUTED 69716e | INK_SUB 56617d | — |
| `color/text/muted` | `#706E66` | 说明、关系等级、占位（对比度 4.5:1） | COLOR_MUTED 6E7B74 | MUTED 69716e | INK_MUTED 7d86a5 | Stranger #8B8B8B（3:1，加深） |
| `color/text/onDark` | `#FFFFFF` | 玻璃底、深色手机、主按钮上的文字 | — | — | — | 200/200、1533、x22 |
| `color/text/onDarkMuted` | `#FFFFFF` @0.60 | 深色底上的次要文字、已完成任务 | — | — | — | 已完成任务（删除线） |
| `color/action/primary` | `#94C242` | 主操作（CTA 条、主按钮、选中环） | COLOR_PRIMARY 3E7D43 | GREEN 5d8f2e / LIME_EDGE a6dc6c | ACCENT 239f9f | NPC 卡按钮条 #94C242 |
| `color/action/primaryPressed` | `#7DAA32` | 主操作按下 | COLOR_PRIMARY_PRESSED 2E6136 | — | ACCENT_DEEP 167e88 | —（主色 -12% 亮度） |
| `color/action/primaryTint` | `#EAF4D8` | 主色浅底（选中行、提示） | COLOR_PRIMARY_TINT ECF4E7 | MINT f1f6e6 | SURFACE_TINT e4eaff | — |
| `color/action/disabled` | `#D6D5CE` | 不可用按钮底 | COLOR_DISABLED D6D5CE | — | — | —（沿用 v2） |
| `color/action/disabledInk` | `#8A918C` | 不可用按钮文字 | COLOR_DISABLED_INK 8A918C | — | — | —（沿用 v2） |
| `color/action/danger` | `#D9604A` | 危险操作（丢弃、删除） | COLOR_DANGER 9C3F2E | CORAL d8787a | DANGER d8787a | — |
| `color/action/selected` | `#F2E69A` | 深色/玻璃底上的选中描边（快捷栏） | COLOR_GOLD F0D75E（近似） | — | — | 快捷栏选中描边（00:23.5） |
| `color/action/focus` | `#F2E69A` | 键盘/手柄焦点环 | — | — | — | — |
| `color/hud/energyFill` | `#5FD86A` | 体力胶囊填色 | COLOR_ENERGY_HUD_FILL E3B341 | — | — | 体力条 #66E36A |
| `color/hud/energyLow` | `#EE8A5B` | 体力低于 20% | COLOR_FLOAT_ENERGY_COST C0563F（近似） | — | — | — |
| `color/hud/energyBonus` | `#7FC66A` | 超上限加成段 | COLOR_ENERGY_BONUS 7FC66A | — | — | —（沿用 v2） |
| `color/hud/ringFrom` | `#58A8E8` | 头像进度环渐变起点 | COLOR_SKILL_FISHING 6FA8DC（近似） | — | — | 头像环蓝段 #75B4E4 |
| `color/hud/ringTo` | `#6BD66F` | 头像进度环渐变终点 | COLOR_SKILL_FARMING 7FC66A（近似） | — | — | 头像环绿段 |
| `color/hud/ringTrack` | `#FFFFFF` @0.90 | 头像进度环轨道 | — | — | — | — |
| `color/hud/coin` | `#F4C430` | 金币图标主色（素材取色基准） | COLOR_GOLD F0D75E | GOLD b57a1b | — | 金币 |
| `color/badge/notify` | `#F2B33D` | 新内容提示点（手机、任务） | COLOR_PIN_AMBER E3B341 | — | — | 手机按钮角标 |
| `color/badge/unread` | `#E07A5F` | 未读数字角标 | COLOR_UNREAD_BADGE E07A5F | — | — | —（沿用 v2） |
| `color/progress/fill` | `#B5E77A` | 关系/经验进度条填色 | COLOR_ENERGY_BONUS 7FC66A（近似） | — | — | NPC 关系条 #DAFFB5（压暗前） |
| `color/progress/track` | `#D5D5CF` | 进度条轨道 | COLOR_DISABLED D6D5CE | — | — | #D4D4D4 |
| `color/phone/bezel` | `#CDD0CE` | 游戏内手机外框 | — | — | — | 手机外框（01:06） |
| `color/phone/screen` | `#262D33` | 手机屏幕底 | — | — | — | #293138 |
| `color/phone/card` | `#2E363D` | 手机内容卡 | — | — | — | — |
| `color/phone/row` | `#1F252A` | 手机任务行、页签栏底 | — | — | — | #212729 |
| `color/phone/notch` | `#191D21` | 手机刘海 | — | — | — | — |
| `color/phone/text` | `#F2F4F3` | 手机正文、选中页签文字 | — | — | — | — |
| `color/phone/textMuted` | `#8C9398` | 手机未选中页签、已完成任务 | — | — | — | — |
| `color/phone/accent` | `#4A8FD4` | 手机内链接、选中页签图标基准色 | COLOR_INFO 426A88（近似） | — | — | Todo 图标 #4A83B8 |
| `color/world/bubble` | `#FFFFFF` | 对话“…”气泡 | COLOR_STATUS_AVAILABLE FBF8F1 | — | — | 00:02 |
| `color/world/bubbleNpc` | `#F2F8E6` | NPC 头像气泡底 | — | — | — | 01:10 头像气泡 |
| `color/world/actionFish` | `#6FA2D6` | 交互气泡：钓鱼 | COLOR_ROLE_TACKLE 2C6A8E（同族） | — | — | 00:48 鱼钩气泡 |
| `color/world/actionCook` | `#C7A43E` | 交互气泡：烹饪 | COLOR_ROLE_TEA 2B7369（不同） | — | — | 00:30 锅气泡 |
| `color/world/actionFeed` | `#8DAE4F` | 交互气泡：喂养/茶壶 | — | — | — | 00:52 茶壶气泡 |
| `color/world/actionSit` | `#A7A5D8` | 交互气泡：坐下/休息 | COLOR_STATUS_EVENT_RING 8D75ED（同族） | — | — | 00:32 椅子气泡 |
| `color/world/selection` | `#FFFFFF` @0.92 | 地块选中虚线框 | DASH_QUICK 白色（用途不同） | — | — | 00:23.5 白色虚线 |
| `color/scrim/modal` | `#17150F` @0.60 | 模态面板遮罩（背包、NPC 卡） | COLOR_SCRIM_MODAL 2F3A33@0.32 | — | — | 遮罩 #211E1A（叠后） |
| `color/scrim/phone` | `#17150F` @0.50 | 手机遮罩 | — | — | — | 01:06 |
| `color/scrim/drawer` | `#17150F` @0.18 | 底部抽屉遮罩 | COLOR_SCRIM_DRAWER 2F3A33@0.18 | — | — | —（沿用 v2 透明度） |
| `color/float/default` | `#FFFFFF` | 飘字默认（×1、+1），配描边 | — | — | — | 00:12 ×1 白字 |
| `color/float/outline` | `#1F2A17` @0.55 | 飘字描边 2 | — | — | — | — |
| `color/float/coins` | `#F6C744` | 飘字：金币 | COLOR_FLOAT_COINS 806C0C | — | — | — |
| `color/float/energyCost` | `#EE8A5B` | 飘字：体力消耗 | COLOR_FLOAT_ENERGY_COST C0563F | — | — | — |
| `color/float/energyGain` | `#8EE06A` | 飘字：体力恢复 | COLOR_FLOAT_ENERGY_GAIN 3E7D43 | — | — | — |
| `color/float/xp` | `#6CC4E8` | 飘字：经验 | COLOR_FLOAT_XP 17808F | — | — | — |
| `color/float/affinity` | `#F07AA5` | 飘字：好感 | COLOR_FLOAT_AFFINITY C04F7A | — | — | — |

沿用 v2、本次不改的玩法语义色：

| v3 组 | v2 来源 | 用途 |
|---|---|---|
| `color/rarity/*` | COLOR_RARITY_COMMON / FINE / RARE / LEGENDARY | 物品品质 |
| `color/family/*` | COLOR_FAMILY_FIELD / ORCHARD / SEASONING / WATER | 物品类别 |
| `color/status/*` | COLOR_STATUS_*（含 *_RING） | 场景状态徽章 |
| `color/heat/*` | COLOR_HEAT_NEAR / PAST / BURNT | 烹饪火候 |
| `color/role/*` | COLOR_ROLE_MARKET / POST / TACKLE / TEA（含 *_TINT） | NPC 职业色 |
| `color/skill/*` | COLOR_SKILL_FARMING / FISHING | 技能色 |
| `color/quality/gold, new, newInk, info, warning(*Tint)` | 同名 COLOR_* | 提示语义色 |

**对比度**（WCAG 2.1，计算值）：`text/primary` 在 `surface/paper` 上 12.7:1，`text/secondary` 5.9:1，`text/muted` 4.5:1；`surface/tag` 上白字 4.8:1；白字在 `glass/fill` 上叠最亮白底 4.8:1、常见草地/土路 5.5～7.5:1；手机 `phone/text` 14.0:1、`phone/textMuted` 5.0:1。
**例外**：白字在 `action/primary` 上 2.1:1、在 `hud/energyFill` 上 1.8:1。为保留概念稿的观感不改底色，文字一律 ExtraBold 并加 1.5 深色描边（`#3F5A12` @0.5），所有者已在 Q-121 确认（见第 8 节）。

### 2.2 字阶（图 9）

字体沿用仓库现有 `Nunito`（OFL）+ `Noto Sans SC`（中文回退）。概念稿里的数字字体接近几何无衬线（类似 Exo），差异不大，不引入新字体。

| v3 字阶 | 字号 | 字重 | 行高 | 用途 | v2 | DesignTokens | 概念稿 |
|---|---|---|---|---|---|---|---|
| `type/display` | 28 | extrabold | 1.2 | 奖励弹窗标题、大数字 | QuantityXB32（32→28） | — | —（概念稿未出现，按字阶推导） |
| `type/title` | 20 | extrabold | 1.25 | 页面/面板标题、手机页头 | TitleXB20 | FONT_TITLE 22 | — |
| `type/headline` | 16 | extrabold | 1.3 | 卡片标题、分组标题 | RowTitleXB15（15→16） | FONT_BODY 16 | — |
| `type/body` | 14 | regular/bold | 1.4 | 正文、NPC 台词（最多 3 行） | BodyR14 / BodyB14 | FONT_LABEL 14 | NPC 台词约 12.5（放大到 14 保证可读） |
| `type/button` | 15 | extrabold | 1.2 | 按钮、CTA 条 | ButtonXB15 | FONT_PILL 15 | CTA 条约 14 |
| `type/label` | 13 | bold | 1.2 | 名牌、标签胶囊（Bag、Pip · Courier Kid） | C13B | — | 名牌约 13 |
| `type/hudNumber` | 13 | extrabold | 1.0 | HUD 数值（200/200、1533） | C13XB | — | 约 12 |
| `type/caption` | 12 | bold | 1.3 | 说明、关系等级、手机任务行 | CaptionB12 | FONT_CAPTION 12 | 手机任务行约 11（放大到 12） |
| `type/micro` | 10 | extrabold | 1.1 | 数量角标（x22）、容量（2/20）、页签文字 | C10XB | FONT_MICRO 10 | 约 10 |

- 最小字号 10，只给数量角标、容量和页签文字；可读正文不小于 14。概念稿里 NPC 台词约 12.5、手机任务约 11，统一放大。
- 中文粗体：仓库只有 Noto Sans SC Regular，粗体暂用 `FontVariation.variation_embolden = 0.6`；所有者已在 Q-121 确认补入 Noto Sans SC Bold（OFL）。

### 2.3 圆角、间距、层级（图 12）

| v3 圆角 | 值 | 用途 | v2 | GameUi | DesignTokens | 概念稿 |
|---|---|---|---|---|---|---|
| `radius/none` | 0 | 贴边元素 | — | — | — | — |
| `radius/xs` | 4 | 小角标、提示点外的方形元素 | RADIUS_TRACK 3 | — | — | — |
| `radius/sm` | 8 | “…”对话气泡、小标签 | RADIUS_CAPTION_PILL 8 | — | — | “…”气泡约 7 |
| `radius/md` | 12 | 快捷栏格、离开按钮、手机内小卡 | RADIUS_CELL 11 / RADIUS_HUD_CHIP 12 | card_style 12 / surface 12 | RADIUS_CARD 12 | 快捷栏格约 12 |
| `radius/lg` | 16 | 快捷栏底、NPC 卡、手机内容卡、Toast | RADIUS_CARD 14 / RADIUS_PIN_MENU 14 | card_surface 16 / panel_style 14 | RADIUS_SHEET 16 | 快捷栏约 16、NPC 卡约 16 |
| `radius/xl` | 20 | 模态面板（背包等） | RADIUS_SHEET 24 / BAG_DRAWER_TOP 24 | panel_style 20 | — | 背包面板约 21.5 |
| `radius/xxl` | 28 | 手机屏幕内圆角 | — | — | — | 约 28 |
| `radius/device` | 36 | 手机外框圆角 | — | — | — | 约 38 |
| `radius/pill` | 999 | 胶囊：体力、金币、名牌、按钮、页签栏、进度条 | RADIUS_PILL 22 / RADIUS_CHIP 13 | — | RADIUS_PILL 24 | 全部胶囊为半圆端 |

| v3 间距 | 值 | 用途 | v2 | DesignTokens |
|---|---|---|---|---|
| `space/s0` | 0 | — | — | — |
| `space/s1` | 2 | 描边内缩、体力填色内缩 | — | — |
| `space/s2` | 4 | 图标与数字、紧凑间距 | SPACE_QUICK_BAR_GAP 4 | SPACE_1 4 |
| `space/s3` | 6 | HUD 元素间距、标签内间距 | SPACE_WITHIN 6 | — |
| `space/s4` | 8 | 快捷栏格间距、行间距、安全区内缩 | SPACE_HUD_ROW_GAP 8 / OVERLAY_BODY 8 | SPACE_2 8 |
| `space/s5` | 12 | 屏幕边距、列表行距 | SPACE_ROW 12 / OVERLAY_BLOCK 12 | SPACE_3 12 |
| `space/s6` | 16 | 卡片内边距、背包格间距 | SPACE_PAGE 16 | SPACE_4 16 |
| `space/s7` | 20 | 面板内边距、分组间距 | SPACE_SECTION 20 | — |
| `space/s8` | 24 | 大块分隔 | — | SPACE_6 24 |
| `space/s9` | 32 | 页面级留白 | — | — |

| v3 层级 | 投影 | 用途 | v2 |
|---|---|---|---|
| `elevation/e0` | 无 | 玻璃件、贴图件（不加投影） | — |
| `elevation/e1` | `#1A140A` @0.18，模糊 6，下移 2 | 白色小件：按钮、名牌 | SHADOW_KEY 2E3B33@0.12 r6 y2 |
| `elevation/e2` | `#1A140A` @0.22，模糊 24，下移 8 | 卡片、模态面板、手机 | SHADOW_CARD 2E3B33@0.16 r24 y8 |
| `elevation/e3` | `#1A140A` @0.25，模糊 8，下移 3 | 世界气泡、飘浮提示 | SHADOW_FLOAT 2E3B33@0.16 r8 y3 |

Godot 落地：`StyleBoxFlat.shadow_size ≈ 模糊 ÷ 2`，`shadow_offset.y = 下移`。

### 2.4 尺寸

| v3 尺寸 | 值 | 用途 | v2 对应 |
|---|---|---|---|
| `size/screen/edge` | 12 | HUD 与屏幕左右边距 | SIZE_HUD_X 8 |
| `size/screen/safeInset` | 8 | 安全区内再缩进 | SIZE_HUD_TOP 16（含状态栏估计） |
| `size/touch/min` | 44 | 最小点击区 | SIZE_TOUCH 44 |
| `size/hud/rowH` | 52 | HUD 顶栏行高 | SIZE_HUD_ROW1_H 46 |
| `size/hud/avatar` | 52 | 头像外径（环 4、内盘 44） | SIZE_HUD_AVATAR 38 / SKILL_RING 44 |
| `size/hud/energyW` | 70 | 体力胶囊宽 | SIZE_ENERGY_CHIP_W 100 |
| `size/hud/energyH` | 20 | 体力胶囊高 | SIZE_ENERGY_CHIP_H 42（两行版） |
| `size/hud/capsuleH` | 24 | 金币等胶囊高 | SIZE_HUD_CAPSULE_H 26 |
| `size/hud/coinIcon` | 18 | 金币图标 | — |
| `size/hud/sideButton` | 36 | 右侧竖排按钮视觉直径（点击区 44） | SIZE_INBOX 32 |
| `size/hud/sideGap` | 8 | 右侧竖排按钮间距 | — |
| `size/quick/slotW` | 48 | 快捷栏格宽 | SIZE_QUICK_SLOT_W 52 |
| `size/quick/slotH` | 56 | 快捷栏格高 | SIZE_QUICK_SLOT_H 68 |
| `size/quick/icon` | 32 | 快捷栏物品图标 | SIZE_QUICK_SLOT_ICON 22 |
| `size/quick/pad` | 12 | 快捷栏左右内边距（上下 10） | — |
| `size/quick/bottom` | 16 | 快捷栏距安全区底 | SIZE_QUICK_BAR_BOTTOM 24 |
| `size/panel/w` | 288 | 模态面板宽（背包类） | — |
| `size/panel/headerH` | 40 | 面板标题色带高 | — |
| `size/panel/pad` | 20 | 面板内边距 | SIZE_SHEET_PAD 16 |
| `size/panel/slot` | 72 | 背包圆格直径 | SIZE_INVENTORY_CELL 52 |
| `size/panel/slotIcon` | 48 | 背包物品图标 | SIZE_INVENTORY_ICON 27 |
| `size/panel/slotGap` | 16 | 背包格列间距 | — |
| `size/panel/rowGap` | 28 | 背包格行间距（容纳数量角标） | — |
| `size/panel/padTop` | 28 | 面板正文上内边距（下 24、左右 20） | — |
| `size/panel/hero` | 80 | 面板头图物件（突出标题条） | — |
| `size/tag/h` | 28 | 名牌/标签胶囊高 | SIZE_CAPTION_PILL_H 18 |
| `size/npc/w` | 312 | NPC 卡宽 | — |
| `size/npc/portraitW` | 96 | NPC 立绘区宽（3D 渲染头像） | — |
| `size/npc/portraitH` | 112 | NPC 立绘区高（上溢 28） | — |
| `size/npc/ctaH` | 48 | NPC 卡底部操作条高 | SIZE_COMMAND 48 |
| `size/phone/w` | 224 | 手机外框宽 | — |
| `size/phone/h` | 436 | 手机外框高 | — |
| `size/phone/bezel` | 9 | 手机边框厚 | — |
| `size/phone/tabH` | 48 | 手机页签栏高 | SIZE_SEGMENT_TAB 44 |
| `size/todo/rowH` | 24 | 任务下拉行高（勾选圆 20） | SIZE_TODAY_ROW_H 40 |
| `size/phone/rowH` | 28 | 手机任务行高（勾选圆 20） | — |
| `size/bubble/talkW` | 32 | “…”气泡宽（高 24） | — |
| `size/bubble/npc` | 68 | NPC 头像气泡直径（白边 3，尾巴 8） | SIZE_STATUS_BADGE_NPC 36 |
| `size/bubble/action` | 40 | 交互气泡直径（白边 2.5，图标 22，尾巴 6） | SIZE_STATUS_BADGE_WORLD 28 |
| `size/world/selectionStroke` | 2.5 | 地块虚线框线宽（虚线 8 / 间隔 5） | DASH_DROP_TARGET 4/3 |

### 2.5 动效令牌（图 14）

| v3 时长 | 毫秒 | 用途 | v2 对应 |
|---|---|---|---|
| `motion/duration/instant` | 80 | 按下反馈 | MOTION_JOYSTICK_FADE_IN_MS 80 |
| `motion/duration/fast` | 120 | 选中、页签内容淡入、遮罩淡出 | MOTION_RADIAL_RETRACT_MS 120 |
| `motion/duration/quick` | 160 | 面板退出、抬起回弹 | MOTION_DISSOLVE_MS 150 |
| `motion/duration/base` | 200 | 遮罩淡入、气泡出现、抖动 | MOTION_RADIAL_FADE_MS 200 / SHAKE 200 |
| `motion/duration/moderate` | 260 | 面板进入 | MOTION_DRAWER_MS 250 |
| `motion/duration/emphasis` | 320 | 手机滑入、头图跳出 | — |
| `motion/duration/slow` | 400 | 计数滚动 | — |
| `motion/duration/fly` | 520 | 奖励飞入 | MOTION_QUICK_BAR_REFILL_MS 300（补位，保留） |
| `motion/duration/float` | 800 | 飘字全程（上升 40） | MOTION_FLOAT_TEXT_MS 800 / RISE 40 |
| `motion/duration/loopBob` | 1600 | 气泡待机浮动周期 | — |

| v3 缓动 | cubic-bezier | Godot Tween | 用途 |
|---|---|---|---|
| `motion/easing/standard` | (0.2, 0, 0, 1) | `TRANS_CUBIC + EASE_OUT` | 进入、位移 |
| `motion/easing/exit` | (0.4, 0, 1, 1) | `TRANS_CUBIC + EASE_IN` | 退出 |
| `motion/easing/pop` | (0.34, 1.56, 0.64, 1) | `TRANS_BACK + EASE_OUT` | 弹出、回弹、图标跳出 |
| `motion/easing/emphasized` | (0.16, 1, 0.3, 1) | `TRANS_QUART + EASE_OUT` | 手机滑入、大位移 |
| `motion/easing/arc` | (0.45, 0, 0.55, 1) | `TRANS_QUAD + EASE_IN_OUT` | 奖励飞行轨迹 |
| `motion/easing/linear` | (0, 0, 1, 1) | `TRANS_LINEAR` | 遮罩透明度 |
| `motion/easing/loop` | (0.37, 0, 0.63, 1) | `TRANS_SINE + EASE_IN_OUT` | 待机循环 |

其他：`pressScale 0.94`、`selectScale 1.06`、`panelEnterScale 0.88`、`phoneEnterOffsetY 40`、`floatTextRise 40`（沿用 v2）、`bobAmplitude 2`、`shakeAmplitude 4`、错峰间隔 `grid 20 / list 40 / float 90`。

### 2.6 与三套旧样式的对照（图 15）

| 旧样式 | 在用范围（C-82#7） | v3 处理 |
|---|---|---|
| UiTokens v2（`tokens-v2.json` 2.1-draft → `UiTokens` + `gensen_theme.tres`） | P0 与动态农场，166 个脚本引用，75 个 `Ui*` 组件 | 升级为 v3：同一生成链路，改值、补令牌；保留 v2 常量名一个版本作为别名（如 `COLOR_PRIMARY` → `action/primary`） |
| GameUi（`modules/ui/game_ui.gd`） | 旧 Journey、换装间、登录面板、钓鱼等 63 个脚本 | 常量改为指向 v3 令牌的别名（`GREEN` → `action/primary`，`PAPER` → `surface/paper` …）；`icon()` 的 lucide 线性图标由 C-86 泥塑图标替换 |
| DesignTokens + `app_theme.tres` | 更早的一套，5 个脚本（导演面板、map_poc、压测场景等） | 常量改为别名；`app_theme.tres` 停止维护，场景改用 `gensen_theme.tres` 的 variation |
| 动态农场地图手写颜色（`FBF8F1`、`263E31`、`314637` 等） | `dynamic_farm_map.gd`、`parcel_farming.gd`、`dynamic_controls.gd` | C-106 重做时改用令牌 |

各令牌的逐项对应见 2.1～2.5 表格的 v2 / GameUi / DesignTokens 列，以及 `tokens-v3.json`。主要变化：

1. 主操作色从 v2 深绿 `#3E7D43`（GameUi `#5d8f2e`、DesignTokens 青绿 `#239f9f`）改为青柠 `#94C242`。
2. 新增“玻璃”组（压场景的深色半透明底），v2 里 HUD 是白底胶囊。
3. 遮罩从 v2 的 `#2F3A33` @0.32 加深到 `#17150F` @0.60（概念稿面板背后的场景几乎看不清）。
4. 面板圆角从 v2 sheet 24 改为 20，卡片从 14 改为 16；物品格从描边方格改为实心圆。
5. HUD 头像从 38 放大到 52，快捷栏图标从 22 放大到 32，背包图标从 27 放大到 48。
6. 描边整体取消（v2 / GameUi 的 1px 描边），层次靠底色和投影。

## 3. 布局（图 13）

| 编号 | 规则 |
|---|---|
| C-L1 | 安全区：用 `DisplayServer.get_display_safe_area()` 换算到逻辑像素；常驻 UI 全部放在安全区内。 |
| C-L2 | 屏幕左右边距 12；HUD 顶 = `safe_top + 8`；快捷栏底 = 安全区底 − 16。 |
| C-L3 | 右侧竖排按钮右对齐 12，自下而上：背包（与快捷栏垂直居中对齐，下方容量文字）、手机、地图，间距 8。快捷栏与右侧按钮至少留 8。 |
| C-L4 | 模态面板水平居中，垂直中心在屏幕中线上方 4%（NPC 卡 8%）；打开时快捷栏隐藏（M-16），遮罩盖住 HUD。图 13C 里快捷栏仍显示，只是示意位置，以本条和 M-16 为准（C-84 验收 V-239 备注）。 |
| C-L5 | 手机弹层右对齐 14，底边在手机按钮上方 8；360×640 小屏时顶部可压住 HUD（有遮罩）。 |
| C-L6 | 视觉小于 44 的可点元素一律扩到 44×44 点击区（`touch/min`）。 |

## 4. 组件规范

### 4.1 HUD 顶栏（图 2）

| 编号 | 元素 | 规格 | 状态 / 交互 |
|---|---|---|---|
| C-H1 | 头像 | Ø52；进度环 4（`hud/ringTrack` 轨道，`hud/ringFrom → hud/ringTo` 渐变）；内盘白 Ø44，放 3D 渲染头像 | 点按 → 个人主页；按下 M-01；升级时环满后闪一下（M-12 前奏） |
| C-H2 | 体力胶囊 | 70×20，外框 `glass/fill` pill，内填 `hud/energyFill` 内缩 2；`type/hudNumber` 白字 + 深色描边；左缘压住头像 4 | 低于 20% 填色 `hud/energyLow`；超上限加成段 `hud/energyBonus`；数值变化 M-07 |
| C-H3 | 任务按钮 | 图标 24（泥塑记事本 + 铅笔），点击区 44，与体力间距 6 | 点按展开任务下拉（C-T1）；有新任务时右上 Ø8 `badge/notify` |
| C-H4 | 金币胶囊 | 高 24，`glass/fill` pill，左内距 10、右内距 3，金币 Ø18 在右；宽随数字，最小 56；右对齐 12 | 数值变化 M-07；获得金币时 M-11 飞入目标 |

### 4.2 快捷栏与右侧按钮（图 3、图 11）

| 编号 | 元素 | 规格 | 状态 |
|---|---|---|---|
| C-Q1 | 快捷栏 | 240×76，`glass/fill`，`radius/lg`，内边距左右 12 上下 10，4 格，格距 8 | 打开面板/手机时隐藏（M-16） |
| C-Q2 | 快捷栏格 | 48×56，`radius/md`，空格 `glass/slot`；图标 32；数量 `type/micro` 白字底部居中 | 空格（保留占位）/ 有物 / 选中（描边 2 `action/selected` + 图标 ×1.06，M-03）/ 按下（M-01）/ 拖放目标（虚线 6/5） |
| C-R1 | 右侧按钮 | 视觉 Ø36 `glass/fill` 圆底 + 泥塑图标 24；点击区 44；间距 8 | 常态 / 按下（透明度 0.62→0.75 + 缩放 0.94）/ 角标 Ø14 `badge/notify`；背包下方 `type/micro` 容量“2/20” |
| C-R2 | 离开按钮（地块模式） | 36×36 `glass/fillStrong`，`radius/md`，右侧中部 | 同 C-R1 |

### 4.3 模态面板（背包类）（图 4、图 11）

| 编号 | 元素 | 规格 |
|---|---|---|
| C-P1 | 面板 | 宽 288，`radius/xl`，`surface/paper`，`elevation/e2`；标题色带 `surface/header` 高 40（只有上圆角）；正文内边距上 28、左右 20、下 24；遮罩 `scrim/modal`，点遮罩或 ✕ 关闭 |
| C-P2 | 头图物件 | 80×80 立体物件，左缘距面板 12，上溢色带约 50%；每类面板一件（背包、商店、换装、收件箱…），由 C-86 生成 |
| C-P3 | 标签胶囊 | 高 28，`surface/tag`，`type/label` 白字，左右内边距 12，左侧尾巴 6；紧贴头图右侧 |
| C-P4 | 关闭 | ✕ 字形 14 `#555550`，点击区 44，距右 12，与色带垂直居中 |
| C-P5 | 物品格 | Ø72 `surface/slot`，图标 48，数量 `type/micro` `text/primary` 贴右下（可越出圆边 4）；3 列，列距 16、行距 28；最后一格“＋”扩容 |
| C-P6 | 物品格状态 | 空 / 有物 / 选中（环 3 `action/primary`）/ 新获得（Ø8 `badge/unread`）/ 锁定（50% + 锁 16）/ 扩容（＋ 20） |
| C-P7 | 空状态 | 整个背包为空时格子照常显示空圆；不加说明文字 |

### 4.4 NPC 对话卡（图 5）

| 编号 | 元素 | 规格 |
|---|---|---|
| C-N1 | 卡片 | 宽 312，`radius/lg`，`surface/paper`，`elevation/e2`；水平居中、垂直中心偏上 8%；`scrim/modal` |
| C-N2 | 立绘区 | 96×112，左缘 4，上溢卡片顶 28；放 3D 部件自动渲染的 NPC 头像（C-30#36 不变，不画手绘立绘） |
| C-N3 | 名牌 | 同 C-P3，内容“名字 · 身份”，压在卡片顶边（上溢 12），左缘对齐正文 |
| C-N4 | 关系行 | `type/caption` `text/muted` 等级名 + 进度条 56×6 pill（`progress/fill` / `progress/track`）；第二行“2/15 · next Acquainted” |
| C-N5 | 台词 | `type/body` bold `text/secondary`，最多 3 行，超出截断加“…”；点卡片翻下一句 |
| C-N6 | 操作条 | 卡片底部整条高 48，`action/primary`，`type/button` 白字 + 描边，前置图标 20；无可用操作时显示原因文字，不响应按下 |
| C-N7 | 关闭 | 同 C-P4 |

### 4.5 按钮（图 11）

| 编号 | 类型 | 规格 |
|---|---|---|
| C-B1 | 主按钮 | 高 44，pill，`action/primary`，`type/button` 白字 + 描边；左右内边距 20，最小宽 96 |
| C-B2 | 次按钮 | 同尺寸，`surface/raised` 底 + 1.5 描边 `#CFCBBE`，`text/primary` 字 |
| C-B3 | 危险按钮 | 同尺寸，`action/danger` |
| C-B4 | 状态 | 常态 / 按下（缩放 0.94 + 按下色，M-01）/ 不可用（`action/disabled` + `action/disabledInk`，点按抖动并提示原因，M-02）/ 焦点（2 `action/focus` 外扩 3）/ 加载中（文字换成三点，宽度不变） |
| C-B5 | 紧凑按钮 | 高 34，`type/caption`，用于列表行内；点击区仍扩到 44 |

### 4.6 游戏内手机（图 7、图 11）

| 编号 | 元素 | 规格 |
|---|---|---|
| C-M1 | 外框 | 224×436，`phone/bezel` 厚 9，外圆角 36，屏幕 `phone/screen` 内圆角 28，`elevation/e2`，`scrim/phone`；刘海 44×12 `phone/notch`（装饰）；✕ 12 `phone/textMuted` |
| C-M2 | 内容卡 | `phone/card`，`radius/lg`，内缩 8 |
| C-M3 | 任务行 | 勾选圆 Ø20 + 行胶囊高 28 pill，`phone/row` 底，`type/caption` bold `phone/text`；完成：勾 + 删除线 + `phone/textMuted`（实测行高约 20，放大到 28 便于点按） |
| C-M4 | 页签栏 | 高 48 pill，`phone/row`，内缩 8，3 格等分：图标 22 + `type/micro`；选中彩色图标 + `phone/text`，未选中灰图标 + `phone/textMuted`。页签为 **任务 / 收件箱 / 收集**（概念稿第 3 格是 Updates，按 C-82#19 改为收集） |
| C-M5 | 页内空状态 | 只写最短事实：“没有任务”“没有包裹”“还没有收集” |

### 4.7 任务下拉（图 7）

| 编号 | 规格 |
|---|---|
| C-T1 | 点任务按钮展开，左对齐头像左缘，首行距 HUD 底 10；行高 24（勾选圆 Ø20 + 行胶囊），行距 4；`glass/fillStrong`；`type/caption` 白字；完成项删除线 + `text/onDarkMuted` |
| C-T2 | 最多 3 行；超过时第 3 行显示“更多…”，点按打开手机任务页 |
| C-T3 | 4 秒无操作自动收起（M-13）；不开遮罩，不挡场景操作 |

### 4.8 场景内元素（图 6）

| 编号 | 元素 | 规格 |
|---|---|---|
| C-W1 | 对话提示“…” | 32×24，`radius/sm`，`world/bubble`，尾巴 6 在左下；3 个点 Ø4 `text/muted`；`elevation/e3`；待机浮动 M-14 |
| C-W2 | NPC 头像气泡 | Ø68，`world/bubbleNpc`，白边 3，尾巴 8 朝下指向 NPC 头顶；内放 3D 渲染头像；玩家靠近 NPC 时出现，点按打开 NPC 卡 |
| C-W3 | 交互气泡 | Ø40，按类型着色（`world/actionFish` 钓鱼、`world/actionCook` 烹饪、`world/actionFeed` 喂养、`world/actionSit` 坐下），白边 2.5，白色字形 22，尾巴 6 朝下；出现在玩家头顶，点按执行 |
| C-W4 | 地块选中框 | `world/selection`，线宽 2.5，虚线 8 / 间隔 5，沿地块外沿；淡入 120（M-15），不做循环 |
| C-W5 | 收获飘字 | 物品图标 24 + “×1”（`type/hudNumber` 14 级 ExtraBold，`float/default` + 2 描边 `float/outline`）；其他类型用 `float/coins` / `float/energyCost` / `float/energyGain` / `float/xp` / `float/affinity`；动效 M-10、M-11 |
| C-W6 | 屏幕尺寸 | 场景内元素按屏幕像素固定大小（不随镜头缩放），锚点在世界坐标上投影 |

### 4.9 沿用 v2 的组件

Toast（v2 R1，SGODOT-202）、EmptyState（SGODOT-206）、Radial 菜单、摇杆、状态徽章：结构不变，只按第 2 节换色和圆角；动效沿用 v2 令牌（`toastBaseMs` 等）。

## 5. 动效规范（图 14）

实现约定：全部用 Godot `Tween`（`create_tween().set_trans().set_ease()`），时长与缓动读 v3 令牌；缩放前设好 `pivot_offset`；UI 补间设 `TWEEN_PAUSE_PROCESS`，暂停时也能关面板；任何动效都不锁输入超过 320 ms。

| 编号 | 场景 | 属性与数值 | 时长 | 缓动（Godot） |
|---|---|---|---|---|
| M-01 | **按钮反馈**（按钮、格子、右侧按钮、气泡） | 按下：缩放 1→0.94，底色换按下色；抬起：缩放回 1；在抬起时触发，手指移出点击区则取消 | 按下 80（`instant`），抬起 160（`quick`） | 按下 `TRANS_CUBIC/EASE_OUT`；抬起 `TRANS_BACK/EASE_OUT` |
| M-02 | 不可用点击 | x 方向 ±4 往返 3 次，同时弹出原因 Toast | 200（`base`） | `TRANS_LINEAR` |
| M-03 | 选中（快捷栏格、背包格、页签） | 选中描边透明度 0→1；图标缩放 1→1.06；取消反向 | 120（`fast`） | 描边 `TRANS_CUBIC/EASE_OUT`；图标 `TRANS_BACK/EASE_OUT`；取消 `EASE_IN` |
| M-04 | **面板进入**（背包、NPC 卡、其他模态） | 遮罩透明度 0→目标；面板缩放 0.88→1 + 透明度 0→1；轴心：背包为面板中心，NPC 卡为底边中点 | 遮罩 200，面板 260（`moderate`） | 遮罩 `TRANS_LINEAR`；面板 `TRANS_BACK/EASE_OUT` |
| M-05 | **面板退出** | 面板缩放 1→0.94 + 透明度→0；遮罩→0；退出一开始就放开输入 | 面板 160（`quick`），遮罩 200 | 面板 `TRANS_CUBIC/EASE_IN`；遮罩 `TRANS_LINEAR` |
| M-06 | 头图跳出与内容错峰 | 头图延迟 80，从 y+12、缩放 0.6 → 原位、1；名牌延迟 140，x −8→0 + 淡入 120；格子从 120 开始每格 +20 淡入 + 缩放 0.9→1（单格 120），错峰总长不超过 200 | 头图 320（`emphasis`） | 头图 `TRANS_BACK/EASE_OUT`；其余 `TRANS_CUBIC/EASE_OUT` |
| M-07 | 计数滚动（体力、金币、数量） | 数字从旧值补间到新值；增加时目标缩放 1→1.15→1；减少时不弹，数字闪 `hud/energyLow` 120 | 400（`slow`），弹跳 200 | 数字 `TRANS_CUBIC/EASE_OUT`；弹跳 `TRANS_BACK/EASE_OUT` |
| M-08 | **手机滑入** | 遮罩 0→0.5；手机从手机按钮处出现：y +40→0、缩放 0.9→1、透明度 0→1，轴心右下角；内容在 200 后淡入 120；手机按钮角标清除 | 遮罩 200，手机 320（`emphasis`） | 手机 `TRANS_QUART/EASE_OUT`；遮罩 `TRANS_LINEAR` |
| M-09 | 手机滑出、页签切换 | 滑出：y +24、缩放 0.96、透明度→0；页签：旧内容淡出并向反方向移 16，新内容从 16 移入并淡入；选中图标 1→1.12→1 | 滑出 200；页签各 120，图标 200 | 滑出 `TRANS_CUBIC/EASE_IN`；页签进入 `TRANS_CUBIC/EASE_OUT`；图标 `TRANS_BACK/EASE_OUT` |
| M-10 | **飘字** | 出现缩放 0.6→1（120）；上升 40；透明度前 480 保持 1、后 320 淡出；多条同时出现间隔 90、x 随机 ±6；同时最多 4 条，多余的合并为“×n” | 全程 800（`float`，沿用 v2） | 上升 `TRANS_CUBIC/EASE_OUT`；淡出 `TRANS_LINEAR` |
| M-11 | **获得奖励（飞入）** | ① 物品图标在来源处缩放 0→1.15→1（200）并停 120；② 沿二次贝塞尔曲线飞向目标（控制点在中点上方 60），缩放 1→0.6（520）；③ 目标（快捷栏格 / 背包按钮 / 金币胶囊）弹跳 1→1.15→1 并计数滚动（M-07）。目标不在屏幕上时飞向背包按钮。多件间隔 60，最多 5 个图标，其余并入计数。普通奖励全程 ≤ 900 | 出现 200，飞行 520（`fly`），到达 200 | 出现 `TRANS_BACK/EASE_OUT`；飞行 `TRANS_QUAD/EASE_IN_OUT`；到达 `TRANS_BACK/EASE_OUT` |
| M-12 | 大奖励弹窗（新物品、升级、蓝图） | 遮罩 0→0.6；奖励卡缩放 0.6→1；标题延迟 200 从 y−12 落下；背后光芒 8 秒一圈循环；按钮延迟 300 淡入；关闭时按 M-05，并把物品按 M-11 飞进背包 | 卡片 320 | 卡片 `TRANS_BACK/EASE_OUT`；光芒 `TRANS_LINEAR` |
| M-13 | 任务下拉 | 展开：每行 y −8→0 + 淡入，每行 160、间隔 40；收起：全部一起淡出 120；4 秒无操作自动收起 | 160 / 120 | 展开 `TRANS_CUBIC/EASE_OUT`；收起 `TRANS_CUBIC/EASE_IN` |
| M-14 | 世界气泡 | 出现：缩放 0→1，轴心在尾巴尖；待机：y ±2 循环；消失：缩放→0.8 + 淡出 | 出现 200，循环周期 1600，消失 120 | 出现 `TRANS_BACK/EASE_OUT`；循环 `TRANS_SINE/EASE_IN_OUT`；消失 `TRANS_CUBIC/EASE_IN` |
| M-15 | 地块选中框 | 透明度 0→1；切换地块时旧框同时淡出 | 120 | `TRANS_CUBIC/EASE_OUT` |
| M-16 | 快捷栏显隐与补位 | 隐藏：y +24 + 淡出；显示：反向；物品用完后补位沿用 v2 | 隐藏 200，显示 260，补位 300（v2 `quickBarRefillMs`） | 隐藏 `EASE_IN`；显示 `EASE_OUT` |

验收要求里点名的 5 类动效：按钮反馈 = M-01（另 M-02、M-03），面板进出 = M-04、M-05（另 M-06），手机滑入 = M-08（另 M-09），飘字 = M-10，获得奖励 = M-11（另 M-12）。

**减少动效**：设置里加“减少动效”开关（默认关）。打开后所有缩放、位移、循环改为 120 ms 淡入淡出；飘字不上升只淡出；奖励不飞行，只让目标弹跳并计数。

## 6. 图标与素材制作规范（交 C-86，图 10）

| 编号 | 类别 | 规格 |
|---|---|---|
| C-I1 | 物品图标 | 手绘写实、柔光立体，无描边，自带浅投影；正方形透明画布，主体占 80%；导出 128、256 两档；游戏内 32（快捷栏）、48（背包）、24（飘字） |
| C-I2 | 头图物件 | 更完整的立体静物，暖色、轻卡通比例；256 画布导出，游戏内 80，可超出面板边框 |
| C-I3 | 系统图标 | 浅灰白泥塑质感，双色明暗，无描边；导出 96，游戏内 24，放在 36 的 `glass/fill` 圆底上 |
| C-I4 | 页签图标 | 选中为彩色扁平立体，未选中由代码去色并降低亮度 50%（只出彩色一套）；游戏内 22 |
| C-I5 | 字形图标 | ✕、对话、勾、＋、锁：实心、圆角端点、单色，可用矢量（SVG）直接绘制，不走生图 |
| C-I6 | 统一光照 | 左上 45° 主光、暖色环境光、软阴影朝右下；同一批次同一提示词前缀 |
| C-I7 | 命名与记录 | `icon_<类>_<名>.png`（如 `icon_item_corn.png`、`icon_sys_phone.png`）、`hero_<面板>.png`；每张图的提示词、种子和来源写进同目录 `assets.json`（沿用 `docs/design/game-ui-2026-09-21/assets.json` 的格式） |
| C-I8 | 面板与按钮底 | 面板、按钮、胶囊优先用 `StyleBoxFlat` 按令牌绘制，不做九宫格贴图；只有头图物件和图标走生图 |

## 7. 给实现卡的迁移说明（C-105）

1. 把 `tokens-v3.json` 放到 `docs/design/tokens/`，扩展 `tools/ui/gen_theme.gd` 读 schema 3，生成 `UiTokens`（VERSION `3.0`）和 `gensen_theme.tres`。
2. `UiTokens` 保留 v2 常量名一个版本（指向 v3 值），`GameUi`、`DesignTokens` 的颜色/圆角常量改为读取 `UiTokens`，旧场景先整体换色，再逐页按本规范改结构。
3. 新增组件：`UiGlassCapsule`（体力/金币）、`UiSideButton`、`UiModalPanel`（含头图与标签胶囊）、`UiBagSlot`（圆格）、`UiCtaBar`、`UiPhoneFrame`、`UiWorldBubble`、`UiFloatText`、`UiRewardFly`；动效统一放在一个 `UiMotion` 工具里，参数全部读令牌。
4. `tests/ui_kit/snapshots` 的 73 张组件快照需要整体更新；改前快照保留作对照。
5. 不改玩法和存档；换装页、个人主页按 C-82#19 已解除 LOCK-22，设计稿在 C-85 出。

## 8. 所有者确认结果（Q-121：按方案定稿）

| # | 事项 | 本规范的做法 |
|---|---|---|
| 1 | 白字在青柠主色（2.1:1）和体力绿（1.8:1）上对比度不足 | 保留概念稿配色，文字加粗加深色描边；如需更稳妥，可把主色加深到约 `#6E9A2A`（白字约 3.3:1），观感会偏暗 |
| 2 | 字号比概念稿大（台词 12.5→14，手机任务 11→12，右侧按钮 20～33→36） | 为安卓小屏可读和可点而放大 |
| 3 | 名牌和次要文字比概念稿略深（`surface/tag`、`text/muted`） | 为达到 4.5:1 对比度 |
| 4 | 中文粗体字体 | 先用加粗变体；建议补 Noto Sans SC Bold |

结论：所有者 2026-11-24 在 Q-121 选“按方案定稿”，以上 4 项全部按本规范的做法执行。

## 附录 A：取样方法与误差

- 原尺寸帧（attachment-580～584，668×1448）直接测量；总览图（attachment-576～579）是每 2 秒一帧的半尺寸缩略图，测量值 ×2 后换算，误差约 ±2 逻辑像素。
- 颜色用 ffmpeg 解码后取 5×5 均值。遮罩下或半透明元素的取样受背景影响，表中“概念稿取样”列只作来源，规范值以 v3 列为准。交互气泡颜色取自缩略帧，为目测值。
- 概念稿是渲染视频，不是可交互原型；未出现的状态（不可用、焦点、加载中、锁定等）按同一风格推导，已在图 11 中画出。
