class_name DesignTokens
extends RefCounted
## 统一设计语言的单一取值来源。
##
## app_theme.tres 与此处保持同源：色板、4dp 间距、圆角、字阶与触摸内边距。
## 场景只选择语义化的 Theme variation，不再自己拼 StyleBox。

# —— 色板 ——
# 薄荷绿承接角色资产；珊瑚色只用于地图动态，避免界面变成单一绿色系。
const ACCENT := Color("#2fcf9f")
const ACCENT_DEEP := Color("#13956f")
const INK := Color("#17211f")
const INK_SUB := Color("#5f6f6a")
const INK_MUTED := Color("#899792")
const SURFACE := Color("#ffffff")
const SURFACE_SUNK := Color("#f2f5f4")
const SURFACE_TINT := Color("#e6f7f1")
const BORDER := Color("#d9e1de")
const MARKER := Color("#ff765f")
const MARKER_PRESSED := Color("#e56a58")
const DANGER := Color("#d85f58")

# —— 4dp 间距栅格 ——
const SPACE_1 := 4
const SPACE_2 := 8
const SPACE_3 := 12
const SPACE_4 := 16
const SPACE_6 := 24

# —— 圆角三档 ——
const RADIUS_SHEET := 16 # 底部编辑器
const RADIUS_CARD := 8 # 卡片 / 选项 / 普通按钮
const RADIUS_PILL := 24 # 仅用于圆形地图控件

# —— 字阶五档 ——
const FONT_TITLE := 22
const FONT_BODY := 16
const FONT_LABEL := 14
const FONT_CAPTION := 12
const FONT_MICRO := 10

## 紧凑行动控件的中间字号。
const FONT_PILL := 15

# —— 触摸目标 ——
## 16 号字约 19 单位高 + 上下各 14 → 约 47~48，达到 48dp 标准。
## 改这两个值会让真机按钮变得点不到（tests/ui/test_app_theme.gd 守护）。
const BTN_PAD_V := 14
const BTN_PAD_H := 16
