class_name UiShowPill
extends Button
## The guide-only `Show` pill (SGODOT-222; LOCK-06 / 08 / 10): an outlined primary pill with an ExtraBold 12 label
## that only moves the camera or opens the map on a pin, never acts. Two mains:
##   TODAY   "Show pill" of TodayRow 1145:81714: stroke 1.2, padding 10 / 5, radius 14 (`Show` = 55 × 28)
##   SOURCE  "Show · guide only" of NeedSource 1092:77266: stroke 1.5, padding 12 · 10 / 6, radius 16 (65 × 31)
## It draws at the main's size; the touch area reaches 44 × 44 around it without changing the layout (安其拉's
## design check on PR #11). Emits Button `pressed`.

enum Kind { TODAY, SOURCE }

# TodayRow / NeedSource mains (WP1b, not exported as tokens yet; see UiTokens.PENDING "wp1b"):
# Height is the main's (12 × 1.35 line + padding + stroke); width hugs the label the same way.
const _SPEC := {
	Kind.TODAY: {stroke = 1.2, left = 10.0, right = 10.0, y = 5.0, radius = 14.0, h = 28.0},
	Kind.SOURCE: {stroke = 1.5, left = 12.0, right = 10.0, y = 6.0, radius = 16.0, h = 31.0},
}

var kind: Kind
var _label: Label

func _init(text_: String = "Show", kind_: Kind = Kind.TODAY) -> void:
	kind = kind_
	focus_mode = Control.FOCUS_NONE
	size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var s: Dictionary = _SPEC[kind]
	var box := UiStyleBox.make(Color(UiTokens.COLOR_PRIMARY, 0.0), s.radius, UiTokens.COLOR_PRIMARY, s.stroke) \
		.with_margins(s.left, s.y, s.right, s.y)
	var down := UiStyleBox.make(UiTokens.COLOR_PRIMARY_TINT, s.radius, UiTokens.COLOR_PRIMARY, s.stroke) \
		.with_margins(s.left, s.y, s.right, s.y)
	for st in [&"normal", &"hover", &"focus", &"disabled"]: add_theme_stylebox_override(st, box)
	for st in [&"pressed", &"hover_pressed"]: add_theme_stylebox_override(st, down)
	_label = UiKit.label(text_, UiTokens.STYLE_CAPTION_XB12, UiTokens.COLOR_PRIMARY)
	_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_label)
	_label.resized.connect(_fit)

func label_text() -> String: return _label.text

func set_label_text(v: String) -> void:
	_label.text = v
	_fit()

## Hugs the label plus the main's padding (a Button does not size itself around a child Label).
func _fit() -> void:
	var s: Dictionary = _SPEC[kind]
	var m := _label.get_combined_minimum_size()
	custom_minimum_size = Vector2(roundf(m.x + s.left + s.right + s.stroke * 2.0), s.h)
	_label.position = Vector2(s.left + s.stroke, (s.h - m.y) * 0.5)

func _notification(what: int) -> void:
	if what == NOTIFICATION_THEME_CHANGED: _fit()

## The touch area: the pill grown to at least 44 × 44 around its centre.
func _has_point(point: Vector2) -> bool:
	var grow := Vector2(maxf(0.0, UiTokens.SIZE_TOUCH - size.x), maxf(0.0, UiTokens.SIZE_TOUCH - size.y)) * 0.5
	return Rect2(-grow, size + grow * 2.0).has_point(point)
