class_name DesignTokens
extends RefCounted
## 统一设计语言的单一取值来源（方向 B：薄荷绿体系化，2026-09-01 决策者选定）。
##
## 本文件是 app_theme.tres 里以下几类取值的来源：色板（ACCENT/INK/SURFACE 等）、
## 4dp 间距栅格、圆角三档、字阶（含 FONT_PILL 这个胶囊按钮专用的中间档）、
## 触摸目标内边距。下周设计会要换风格时，改这个文件 + 同步 app_theme.tres 这
## 两处，不必翻场景。
##
## 不在此列、目前仍是 app_theme.tres 里硬编码、没有对应常量的取值（本轮任务
## 范围之外，留给后续设计通道决定是否要收编）：各 StyleBox 的阴影
## （shadow_color/size/offset）、表面透明度档位（0.94/0.96/0.97 等 alpha）、
## 非 accent 圆按钮/胶囊按钮按下态的中性灰、滚动条抓手颜色、
## SB_chip / SB_pill* 的内边距（14/8、18/11）。

# —— 色板 ——
const ACCENT := Color("#34d399") # 主行动色（角色短裤薄荷绿）
const ACCENT_DEEP := Color("#059669") # 按下态 / 描边
const INK := Color("#123028") # 主文字（墨色，保证按钮上的对比度）
const INK_SUB := Color("#7d9089") # 次级文字
const SURFACE := Color("#ffffff") # 浮层表面
const SURFACE_SUNK := Color("#f3f6f5") # 凹陷格（部件槽、未选中按钮）
const SURFACE_TINT := Color("#ecf7f2") # 选中态浅薄荷

# —— 4dp 间距栅格 ——
const SPACE_1 := 4
const SPACE_2 := 8
const SPACE_3 := 12
const SPACE_4 := 16
const SPACE_6 := 24

# —— 圆角三档 ——
const RADIUS_SHEET := 22 # 底部抽屉
const RADIUS_CARD := 14 # 卡片 / 部件格 / 气泡 / 普通按钮
const RADIUS_PILL := 21 # 胶囊按钮（= 高度一半）

# —— 字阶五档 ——
const FONT_TITLE := 20
const FONT_BODY := 16
const FONT_LABEL := 13
const FONT_CAPTION := 11
const FONT_MICRO := 9

## 胶囊按钮专用的中间字号，故意介于 FONT_LABEL(13) 与 FONT_BODY(16) 之间、
## 不属于上面的五档主字阶。PillButton / AccentPillButton 的
## font_sizes/font_size 对应这个值。历史遗留（未经视觉复核），本轮任务只是
## 给它命名纳入 token 系统，不改动数值——改动前先过一遍设计视觉复核。
const FONT_PILL := 14

# —— 触摸目标 ——
## 16 号字约 19 单位高 + 上下各 14 → 约 47~48，达到 48dp 标准。
## 改这两个值会让真机按钮变得点不到（tests/ui/test_app_theme.gd 守护）。
const BTN_PAD_V := 14
const BTN_PAD_H := 16
