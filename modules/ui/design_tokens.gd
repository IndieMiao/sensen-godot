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

# —— 社交主线壳（GameUi）的纸色系 ——
# A7（SGODOT-19）：GameUi 的常量全部指到这里；改这一组就换掉登录 / 四 Tab / 子页的全局风格。
# 地图 HUD 与农场面板仍用上面的薄荷系（ACCENT / INK…），两套并存是现状，不在本卡里合并。
const UI_INK := Color("243d35")
const UI_MUTED := Color("64786e")
const UI_GREEN := Color("287c59")
const UI_MINT := Color("e8f4ed")
const UI_PAPER := Color("fcfefa")
const UI_BORDER := Color("d2e2d6")
const UI_GOLD := Color("ecc568")
const UI_CORAL := Color("ce705c")
const UI_BLUE := Color("43869f")
## 禁用态底、只读输入框底、输入框底。
const UI_SURFACE_DISABLED := Color("edf1ed")
const UI_SURFACE_SUNK := Color("f2f5f2")
const UI_FIELD := Color("fbfcfb")

## 4dp 栅格之间的半档：现有版式里 2 / 6 / 10 都在用，收口时保留原值而不是硬改成 4 的倍数
## （改版式是设计的事，A7 只负责把取值收到一处）。
const SPACE_HALF := 2
const SPACE_1H := 6
const SPACE_2H := 10

# —— 壳的字阶与尺寸 ——
## 壳的正文 14（比地图 / 农场的 FONT_BODY 16 小一号：手机上四 Tab 页信息密度更高）。
const UI_FONT_BODY := 14
const UI_FONT_TAB := 11
const UI_FONT_CAPTION := 12
const UI_FONT_TITLE := 20
## 卡片标题 / 主名字。
const UI_FONT_LEAD := 18
## 触摸目标最小边（Apple HIG 44pt）。
const UI_TOUCH_MIN := 44
const UI_ICON_MAX := 20
const UI_TAB_ICON_MAX := 18
const UI_RADIUS := 8
const UI_PAD := 12

