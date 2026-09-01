class_name DesignTokens
extends RefCounted
## 统一设计语言的单一取值来源（方向 B：薄荷绿体系化，2026-09-01 决策者选定）。
## app_theme.tres 的每个取值都应能在这里找到对应常量。
## 下周设计会要换风格时，只改这个文件 + 同步 app_theme.tres，不必翻场景。

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

# —— 触摸目标 ——
## 16 号字约 19 单位高 + 上下各 14 → 约 47~48，达到 48dp 标准。
## 改这两个值会让真机按钮变得点不到（tests/ui/test_app_theme.gd 守护）。
const BTN_PAD_V := 14
const BTN_PAD_H := 16
